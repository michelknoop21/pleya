import '../connection/connection.dart';
import '../connection/connection_registry.dart';
import '../services/storage_service.dart';
import '../utils/app_logger.dart';
import 'profile_connection.dart';
import 'profile_connection_registry.dart';

/// Set once [backfillBorrowedJellyfinRows] has run on this install.
const borrowedBackfillDoneKey = 'profile_connections_borrowed_backfill_v20_done';

/// One-time repair for Jellyfin join rows written before schema v20, when the
/// borrow flow did not yet record `borrowed`. Such a row still carries the
/// lender's admin rights. Runs after the database is open, not in `onUpgrade`:
/// tokens are CredentialVault ciphertext with a random nonce, so comparing
/// them needs the registry's async decrypt.
///
/// A Jellyfin connection id is `machineId/userId`, so rows sharing one are the
/// same server user on different profiles. The borrow flow copies the source
/// row's token (or the connection's access token); a separate login always
/// mints a new one. Equal effective tokens therefore mean a copy. Per token
/// group of two or more rows, the row with the unique earliest non-null
/// `tokenAcquiredAt` is the original and stays owned; every other row becomes
/// borrowed. A tie or a null earliest time marks the whole group borrowed
/// (the closed side; signing in again restores the owner row).
///
/// Residual: a borrowed row whose lender signed in again (new token) or whose
/// source profile was deleted falls outside every group and stays unmarked.
///
/// Returns the number of rows marked borrowed. Idempotent via
/// [borrowedBackfillDoneKey].
Future<int> backfillBorrowedJellyfinRows({
  required ProfileConnectionRegistry profileConnections,
  required ConnectionRegistry connections,
  required StorageService storage,
}) async {
  if (storage.readBool(borrowedBackfillDoneKey)) return 0;

  final jellyfin = {for (final c in (await connections.list()).whereType<JellyfinConnection>()) c.id: c};
  final byConnection = <String, List<ProfileConnection>>{};
  for (final pc in await profileConnections.listAll()) {
    if (jellyfin.containsKey(pc.connectionId)) (byConnection[pc.connectionId] ??= []).add(pc);
  }

  var marked = 0;
  for (final MapEntry(key: connectionId, value: rows) in byConnection.entries) {
    if (rows.length < 2) continue;
    final accessToken = jellyfin[connectionId]!.accessToken;
    final byToken = <String, List<ProfileConnection>>{};
    for (final pc in rows) {
      (byToken[pc.hasToken ? pc.userToken! : accessToken] ??= []).add(pc);
    }
    for (final group in byToken.values) {
      if (group.length < 2) continue;
      final owner = _uniqueEarliest(group);
      if (owner == null) {
        appLogger.w(
          'Borrowed backfill: no unique original for $connectionId '
          '(${group.length} profiles), marking all borrowed',
        );
      }
      for (final pc in group) {
        if (identical(pc, owner) || pc.borrowed) continue;
        await profileConnections.markBorrowed(pc.profileId, pc.connectionId);
        marked++;
      }
    }
  }

  await storage.writeBool(borrowedBackfillDoneKey, true);
  if (marked > 0) appLogger.i('Borrowed backfill: marked $marked Jellyfin row${marked == 1 ? '' : 's'} borrowed');
  return marked;
}

/// The row with the strictly earliest non-null `tokenAcquiredAt`, or `null`
/// on a tie or when the earliest is unknown.
ProfileConnection? _uniqueEarliest(List<ProfileConnection> group) {
  final sorted = [...group]
    ..sort((a, b) {
      final at = a.tokenAcquiredAt, bt = b.tokenAcquiredAt;
      if (at == null || bt == null) return at == null ? (bt == null ? 0 : -1) : 1;
      return at.compareTo(bt);
    });
  final first = sorted.first.tokenAcquiredAt;
  if (first == null || sorted[1].tokenAcquiredAt == first) return null;
  return sorted.first;
}
