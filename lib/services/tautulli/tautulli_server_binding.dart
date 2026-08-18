import '../../media/ids.dart';

/// Which registered Plex server a Tautulli instance is monitoring.
///
/// Tautulli reports rating keys and library paths, and both are per-server
/// integers: resolving them against the wrong Plex server does not fail, it
/// silently returns a different title. So the caller cannot pick "an owned
/// server" and hope, which is what the presence surfaces did while a profile
/// only ever had one.
///
/// [machineIdentifier] is the `pms_identifier` Tautulli reports for the server
/// it watches, and it is the same string a client is registered under. An exact
/// match is the answer. No match means Tautulli watches a server this profile
/// has not connected, and then null is the honest answer: a row that stays
/// inert beats a row that opens someone else's library.
///
/// A session paired before the identifier was recorded has none. Then the
/// single owned server is the only defensible guess, and with more than one
/// there is nothing to go on, so it stays null.
ServerId? tautulliMonitoredServer({
  required String? machineIdentifier,
  required List<String> serverIds,
  required bool Function(ServerId) isOwnerOrAdmin,
}) {
  final reported = machineIdentifier?.trim();
  if (reported != null && reported.isNotEmpty) {
    final match = serverIds.where((id) => id == reported).firstOrNull;
    return match == null ? null : ServerId(match);
  }

  final owned = serverIds.where((id) => isOwnerOrAdmin(ServerId(id))).toList();
  return owned.length == 1 ? ServerId(owned.single) : null;
}
