import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connection/connection.dart';
import '../connection/connection_registry.dart';
import '../i18n/strings.g.dart';
import '../screens/profile/pin_entry_dialog.dart';
import '../services/plex_auth_service.dart';
import '../utils/app_logger.dart';
import '../utils/snackbar_helper.dart';
import 'active_profile_binder.dart';
import 'active_profile_provider.dart';
import 'plex_home_switch.dart';
import 'profile.dart';
import 'profile_connection.dart';
import 'profile_connection_registry.dart';

/// Activate [profile] from a UI surface, prompting for the PIN when the
/// profile is protected. Returns `true` on successful activation, `false`
/// when the user cancelled the PIN dialog. Loops on wrong-PIN entries
/// until the user submits the right PIN or backs out.
///
/// The retry loop uses the same shake-on-error pattern as Plex Home users
/// — see [showPinEntryDialog].
///
/// For [ProfileKind.plexHome] profiles whose `plexProtected` flag is set,
/// the PIN is validated up front via `/home/users/{uuid}/switch` so a
/// failed PIN never flips `_active`. The minted user-token is saved and
/// the profile is marked pre-verified on the binder, so it reuses the cached
/// token instead of re-prompting for the same PIN.
///
/// [mayActivate] is asked once the PIN is accepted, right before the switch;
/// false returns `false` without switching (a handoff whose phone gave up).
///
/// [verifiedPlexUserToken] replaces the PIN of a protected Plex Home or local
/// profile (A-23c). The caller must have proven it with plex.tv for the one
/// Plex user of [profile] (see `handoffTokenProofUuid`). A Plex Home profile
/// keeps it as its cached user token; should Plex reject it later, the binder
/// asks the PIN as before. [mayActivate] is still asked, before anything is saved.
///
/// [onPinCancelled] is called when the user backed out of the PIN dialog, just
/// before this returns `false`, so a caller can tell that from any other
/// failure (an activation that returned false, a failed save, [mayActivate]).
Future<bool> activateProfileWithPin(
  BuildContext context,
  Profile profile, {
  bool Function()? mayActivate,
  String? verifiedPlexUserToken,
  void Function()? onPinCancelled,
}) async {
  final active = context.read<ActiveProfileProvider>();
  final binder = context.read<ActiveProfileBinder>();
  bool allowed() => mayActivate?.call() ?? true;
  final proven = profile.isPinProtected && verifiedPlexUserToken != null && verifiedPlexUserToken.isNotEmpty;

  if (profile.isPlexHome) {
    if (proven) {
      if (!allowed()) return false;
      final ok = await _keepVerifiedPlexHomeToken(context, profile, verifiedPlexUserToken);
      if (!ok) return false;
    } else {
      if (profile.plexProtected) {
        final ok = await _preVerifyPlexHomePin(context, profile, onPinCancelled: onPinCancelled);
        if (!ok) return false;
      }
      if (!allowed()) return false;
    }
    binder.markUserInitiatedActivation(profile.id);
    return active.activate(profile);
  }

  if (!profile.isPinProtected) {
    if (!allowed()) return false;
    binder.markUserInitiatedActivation(profile.id);
    return active.activate(profile);
  }

  if (proven && profile.isLocal) {
    // The token proved the only Plex user behind this local profile; its join row stays as it is.
    if (!allowed()) return false;
    binder.markUserInitiatedActivation(profile.id);
    return active.activate(profile, pinProven: true);
  }

  String? errorMessage;
  while (true) {
    if (!context.mounted) return false;
    final pin = await showPinEntryDialog(context, profile.displayName, errorMessage: errorMessage);
    if (pin == null) {
      onPinCancelled?.call();
      return false; // user cancelled
    }
    final hash = profile.pinHash;
    if (hash != null && verifyPin(pin, hash)) {
      if (!allowed()) return false;
      binder.markUserInitiatedActivation(profile.id);
      return active.activate(profile, pin: pin);
    }
    errorMessage = t.profiles.incorrectPinTryAgain;
  }
}

/// Activate [profile] from a UI surface, then wait until the active profile's
/// server/token binding has settled. Shows the standard switch failure message
/// for both activation and binding failures. Cancelling the PIN stays silent.
Future<bool> switchProfileFromUi(BuildContext context, Profile profile) async {
  final activeProvider = context.read<ActiveProfileProvider>();
  var pinCancelled = false;
  final ok = await activateProfileWithPin(context, profile, onPinCancelled: () => pinCancelled = true);
  if (!context.mounted) return false;
  if (!ok) {
    if (!pinCancelled) showErrorSnackBar(context, t.errors.failedToSwitchProfile(displayName: profile.displayName));
    return false;
  }

  final bound = await activeProvider.awaitBindingSettle();
  if (!context.mounted) return false;
  if (!bound) {
    showErrorSnackBar(context, t.errors.failedToSwitchProfile(displayName: profile.displayName));
    return false;
  }
  return true;
}

/// Validate [profile]'s PIN with Plex via `/home/users/{uuid}/switch`. On
/// success, persist the minted user-token and mark the profile as
/// pre-verified so [ActiveProfileBinder] reuses the cached token instead
/// of re-prompting. Returns `false` on cancel or a final failure (caller
/// must abort activation in that case).
///
/// Returns `true` without doing anything when the profile lacks the
/// parent/uuid metadata or the parent connection is missing — the
/// binder's existing missing-metadata path will fire and silently
/// produce an empty bind, matching today's behavior. We don't want to
/// fail activation outright for users in unusual data states.
Future<bool> _preVerifyPlexHomePin(BuildContext context, Profile profile, {void Function()? onPinCancelled}) async {
  final parentId = profile.parentConnectionId;
  final homeUuid = profile.plexHomeUserUuid;
  if (parentId == null || homeUuid == null) return true;

  final connections = context.read<ConnectionRegistry>();
  final all = await connections.list();
  PlexAccountConnection? account;
  for (final c in all) {
    if (c.id == parentId && c is PlexAccountConnection) {
      account = c;
      break;
    }
  }
  if (account == null) return true;

  final auth = await PlexAuthService.create();
  try {
    final result = await switchPlexHomeUserWithPin(
      auth: auth,
      accountToken: account.accountToken,
      homeUserUuid: homeUuid,
      requiresPin: true,
      promptForPin: ({String? errorMessage}) async {
        if (!context.mounted) return null;
        return showPinEntryDialog(context, profile.displayName, errorMessage: errorMessage);
      },
      logLabel: profile.displayName,
    );
    if (result.status == PlexHomeSwitchStatus.cancelled) onPinCancelled?.call();
    if (!result.succeeded) return false;
    if (!context.mounted) return false;
    return _savePlexHomeUserToken(
      context,
      profile,
      connectionId: account.id,
      homeUuid: homeUuid,
      userToken: result.userToken,
    );
  } finally {
    auth.dispose();
  }
}

/// A user token the handoff proved for [profile] (A-23c), kept the way a PIN
/// entered here keeps the minted one. Missing metadata or a missing parent
/// account saves nothing and lets the binder decide, as [_preVerifyPlexHomePin]
/// does. A failed save does not mark the profile, so the binder asks the PIN.
Future<bool> _keepVerifiedPlexHomeToken(BuildContext context, Profile profile, String userToken) async {
  final parentId = profile.parentConnectionId;
  final homeUuid = profile.plexHomeUserUuid;
  if (parentId == null || homeUuid == null) return true;
  final connections = context.read<ConnectionRegistry>();
  try {
    final account = await connections.getPlexAccount(parentId);
    if (account == null) return true;
    if (!context.mounted) return false;
    return await _savePlexHomeUserToken(
      context,
      profile,
      connectionId: account.id,
      homeUuid: homeUuid,
      userToken: userToken,
    );
  } catch (e) {
    appLogger.w('Profile activation: the proven Plex token was not saved (${e.runtimeType})');
    return context.mounted;
  }
}

/// Persist [userToken] on [profile]'s row for its Plex account and mark the
/// profile pre-verified, so [ActiveProfileBinder] uses this token once instead
/// of asking the PIN again.
Future<bool> _savePlexHomeUserToken(
  BuildContext context,
  Profile profile, {
  required String connectionId,
  required String homeUuid,
  required String? userToken,
}) async {
  final binder = context.read<ActiveProfileBinder>();
  await context.read<ProfileConnectionRegistry>().upsert(
    ProfileConnection(
      profileId: profile.id,
      connectionId: connectionId,
      userToken: userToken,
      userIdentifier: homeUuid,
      tokenAcquiredAt: DateTime.now(),
    ),
  );
  if (!context.mounted) return false;
  binder.markPlexHomePreVerified(profile.id);
  return true;
}

/// Verify [pin] against [profile]'s stored PIN hash *without* activating it.
/// Used by the borrow flow: we need to confirm the user knows the source
/// profile's PIN before letting them copy a connection out of it.
///
/// Plex Home profiles can't be verified locally — their PIN lives on Plex's
/// servers. Callers should fall through to a real `/home/users/.../switch`
/// call instead.
bool verifyProfilePin(Profile profile, String pin) {
  if (!profile.isLocal) return false;
  final hash = profile.pinHash;
  if (hash == null || hash.isEmpty) return true;
  return verifyPin(pin, hash);
}
