import '../../media/ids.dart';
import '../../models/tautulli/tautulli_models.dart';

/// The only route by which a non-admin profile uses the admin's Tautulli
/// credential.
///
/// Nothing here hands out a token, a session or a client. The implementation
/// looks the integration up itself, re-checks that import is still enabled, and
/// issues exactly one kind of request: a history page for one pinned server.
///
/// Note which parameter is absent: the *user*. An earlier shape took a
/// `userId`, which made this a confused deputy — the credential belongs to the
/// admin, so a caller passing a housemate's account id would have read that
/// housemate's history through it. The profile is named instead, and the
/// implementation resolves the account id from it and refuses anything but the
/// profile that is active right now. A caller therefore cannot aim the
/// credential at anyone, because there is no parameter that would let it.
///
/// What this is: an API boundary, enforced by there being no public field or
/// getter that reaches the token. What it is not: memory isolation. Everything
/// still runs in one Dart isolate, and this interface makes no claim beyond the
/// shape of the calls that cross it.
abstract class TautulliImportAccess {
  /// Machine identifiers whose imported history may currently be used, which is
  /// also exactly the set that may be fetched. Empty when nothing is paired,
  /// the profile does not have the server, the admin turned it off, the pairing
  /// is disconnected, the credential is unreadable, or a migration conflict is
  /// unresolved.
  Set<String> enabledImportServerIds();

  /// One page of [profileId]'s own history on [serverId], or null when the
  /// integration is gone, no longer enabled, or [profileId] is not the profile
  /// that is active right now.
  ///
  /// [after] and [before] are `YYYY-MM-DD` date bounds, both inclusive, and
  /// [start] is a pagination offset inside that window.
  Future<TautulliHistoryPage?> fetchImportHistory(
    ServerId serverId, {
    required String profileId,
    required int length,
    required int start,
    String? after,
    String? before,
  });
}
