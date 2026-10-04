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
/// same server user on different profiles. The binder binds every such row
/// with the connection's current `accessToken`, never the row's own token, so
/// within a connection of two or more rows:
///
/// 1. A row whose effective token (its own, else the connection's) differs
///    from `accessToken` is stale and becomes borrowed. This covers a lender
///    who signed in again after lending: the connection and the lender's row
///    carry the new token, the borrower row keeps the old copy.
/// 2. Among the rows left, which all carry `accessToken` and are therefore
///    copies of one login, the row with the unique earliest non-null
///    `tokenAcquiredAt` is the original and stays owned. A tie or a null
///    earliest time marks all of them borrowed.
///
/// Both rules err on the closed side. Accepted false positive of rule 1: an
/// owner who signed in separately on two profiles loses the rights on the
/// older one until signing in again there. Signing in again restores any
/// owner row (`freshLogin` clears `borrowed`).
///
/// Residual: a borrowed row whose source profile was deleted is the only row
/// of its connection and cannot be told apart from an own login.
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
    final current = [
      for (final pc in rows)
        if ((pc.hasToken ? pc.userToken! : accessToken) == accessToken) pc,
    ];
    final owner = current.length == 1 ? current.single : _uniqueEarliest(current);
    if (owner == null) {
      appLogger.w(
        'Borrowed backfill: no unique original for $connectionId '
        '(${rows.length} profiles), marking all borrowed',
      );
    }
    for (final pc in rows) {
      if (identical(pc, owner) || pc.borrowed) continue;
      await profileConnections.markBorrowed(pc.profileId, pc.connectionId);
      marked++;
    }
  }

  await storage.writeBool(borrowedBackfillDoneKey, true);
  if (marked > 0) appLogger.i('Borrowed backfill: marked $marked Jellyfin row${marked == 1 ? '' : 's'} borrowed');
  return marked;
}

/// The row with the strictly earliest non-null `tokenAcquiredAt`, or `null`
/// on a tie, when the earliest is unknown, or when [group] is empty.
ProfileConnection? _uniqueEarliest(List<ProfileConnection> group) {
  if (group.isEmpty) return null;
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
