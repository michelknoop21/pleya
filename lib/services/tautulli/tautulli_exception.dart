/// Typed Tautulli error so the UI can tell a wrong token from an unreachable
/// host and say something useful instead of "something went wrong".
///
/// [isNotTautulli] and [isMalformed] reach the user as the same sentence on
/// purpose, but they stay apart here and in the log, because they send you to
/// different places: the first means whatever answered was not Tautulli at all
/// (a proxy, an SSO login page, the wrong address), the second means it spoke
/// JSON that this client does not recognise (another API on that path, or a
/// version that moved the envelope).
class TautulliException implements Exception {
  final String message;
  final bool isAuth;
  final bool isNetwork;
  final bool isNotTautulli;
  final bool isMalformed;

  /// Set only when the failure *is* the HTTP status, so the UI can name the
  /// code instead of guessing at a cause.
  final int? statusCode;

  const TautulliException(
    this.message, {
    this.isAuth = false,
    this.isNetwork = false,
    this.isNotTautulli = false,
    this.isMalformed = false,
    this.statusCode,
  });

  factory TautulliException.auth() => const TautulliException('Invalid apikey', isAuth: true);
  factory TautulliException.network(String m) => TautulliException(m, isNetwork: true);
  factory TautulliException.notTautulli() => const TautulliException('not a Tautulli response', isNotTautulli: true);
  factory TautulliException.malformed() => const TautulliException('unrecognised response shape', isMalformed: true);

  /// A status code that carried no usable envelope. 401 and 403 are the two
  /// that mean the credential rather than the server, whatever the body says.
  factory TautulliException.http(int statusCode) =>
      TautulliException('HTTP $statusCode', statusCode: statusCode, isAuth: statusCode == 401 || statusCode == 403);

  @override
  String toString() => message;
}
