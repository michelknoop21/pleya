import '../../media/ids.dart';
import '../../models/plex/plex_home_user.dart';
import '../../profiles/plex_self_account.dart';
import '../tautulli/tautulli_integration_status.dart';

/// Why an import will not run. Logged, never shown: there is no user-facing
/// Tautulli surface outside the admin settings screen, so a refusal is a
/// diagnostic, not a message.
enum TautulliImportRefusalReason {
  personalizedRecommendationsOff,
  noIntegration,
  importDisabled,
  noActiveProfile,
  ambiguousUser,
  serverNotRegistered,
  noCatalogueClient,
}

sealed class TautulliImportBinding {
  const TautulliImportBinding();
}

/// Everything an import needs, all of it verified.
class TautulliImportTarget extends TautulliImportBinding {
  /// The active profile the rows will belong to.
  final String activeProfileId;

  /// The exact plex.tv account id of that profile. Tautulli reports history in
  /// this id space, so it is what makes a row "mine" rather than a housemate's.
  final int userId;

  final ServerId serverId;

  /// Same string as [serverId], carried explicitly because it is also what the
  /// per-row `machine_id` check compares against.
  final String machineIdentifier;

  const TautulliImportTarget({
    required this.activeProfileId,
    required this.userId,
    required this.serverId,
    required this.machineIdentifier,
  });
}

class TautulliImportRefusal extends TautulliImportBinding {
  final TautulliImportRefusalReason reason;
  const TautulliImportRefusal(this.reason);
}

/// Decides whether the active profile may import its own Tautulli history from
/// a given integration.
///
/// Deliberately stricter than `tautulliMonitoredServer`, which falls back to
/// "the only owned server" when Tautulli did not report an identifier. That is
/// defensible for a presence row, which at worst stays inert. It is not
/// defensible here: rating keys are per-server, so a wrong guess writes another
/// server's titles into someone's permanent taste profile. Only an exact match
/// counts.
///
/// Note what is *not* a condition: being an owner or admin. Configuring the
/// integration takes admin rights and is gated at the settings screen and in
/// the provider's mutators. Consuming an integration the admin already
/// authorised does not, otherwise every household member would need their own
/// admin credential. What keeps profiles apart is [userId], which is resolved
/// per profile and fails closed when it cannot be resolved exactly.
///
/// [status] is deliberately the credential-free view and not the integration
/// record: this function runs in every profile's context, so handing it the
/// record would hand a non-admin profile the admin's token.
TautulliImportBinding resolveTautulliImportBinding({
  required bool personalizedRecommendationsEnabled,
  required TautulliIntegrationStatus? status,
  required String? activeProfileId,
  required Map<String, List<PlexHomeUser>> homeUsers,
  required List<String> registeredServerIds,
  required bool Function(ServerId) hasCatalogueClient,
}) {
  if (!personalizedRecommendationsEnabled) {
    return const TautulliImportRefusal(TautulliImportRefusalReason.personalizedRecommendationsOff);
  }
  if (status == null) {
    return const TautulliImportRefusal(TautulliImportRefusalReason.noIntegration);
  }
  // Covers the admin policy, the connection state, a missing or unreadable
  // credential, and an unresolved migration conflict, in one place.
  if (!status.importEnabled) {
    return const TautulliImportRefusal(TautulliImportRefusalReason.importDisabled);
  }
  if (activeProfileId == null || activeProfileId.isEmpty) {
    return const TautulliImportRefusal(TautulliImportRefusalReason.noActiveProfile);
  }

  final userId = plexSelfAccountIdIn(activeProfileId, homeUsers);
  if (userId == null) {
    return const TautulliImportRefusal(TautulliImportRefusalReason.ambiguousUser);
  }

  final identifier = status.machineIdentifier.trim();
  if (identifier.isEmpty || !registeredServerIds.contains(identifier)) {
    return const TautulliImportRefusal(TautulliImportRefusalReason.serverNotRegistered);
  }

  final serverId = ServerId(identifier);
  if (!hasCatalogueClient(serverId)) {
    return const TautulliImportRefusal(TautulliImportRefusalReason.noCatalogueClient);
  }

  return TautulliImportTarget(
    activeProfileId: activeProfileId,
    userId: userId,
    serverId: serverId,
    machineIdentifier: identifier,
  );
}
