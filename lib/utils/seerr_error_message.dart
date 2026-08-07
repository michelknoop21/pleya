import '../i18n/strings.g.dart';
import '../services/seerr/seerr_client.dart';

/// Why a seerr call failed, in the terms the user needs to hear.
enum SeerrErrorKind {
  /// The session is no longer valid. Retrying cannot fix this.
  auth,

  /// Authenticated, but the account isn't allowed to do it. Retrying cannot
  /// fix this either.
  forbidden,

  /// The server couldn't be reached at all.
  network,

  /// Anything else: a 5xx, an unexpected payload, a bug on our side.
  generic,
}

/// Classifies whatever a seerr call threw.
///
/// [SeerrClient] already separates 401 and 403 from the rest, but the discover
/// screen used to collapse everything except a transport failure into the
/// generic message — so an expired session read as "Something went wrong. Try
/// again", and trying again never helped.
SeerrErrorKind seerrErrorKindOf(Object error) {
  if (error is! SeerrException) return SeerrErrorKind.generic;
  if (error.isAuth) return SeerrErrorKind.auth;
  if (error.isForbidden) return SeerrErrorKind.forbidden;
  if (error.isNetwork) return SeerrErrorKind.network;
  return SeerrErrorKind.generic;
}

/// The failure to name when several rows failed at once.
///
/// Auth and permission problems win over a generic one: they say something
/// actionable, and no amount of retrying will clear them. A transport failure
/// outranks generic for the same reason — "check the URL" beats "try again".
SeerrErrorKind dominantSeerrErrorKind(Iterable<SeerrErrorKind> kinds) {
  const priority = [SeerrErrorKind.auth, SeerrErrorKind.forbidden, SeerrErrorKind.network];
  final seen = kinds.toSet();
  for (final kind in priority) {
    if (seen.contains(kind)) return kind;
  }
  return SeerrErrorKind.generic;
}

/// User-facing message for [kind].
String seerrErrorMessage(SeerrErrorKind kind) => switch (kind) {
  SeerrErrorKind.auth => t.seerr.errorAuth,
  SeerrErrorKind.forbidden => t.seerr.errorForbidden,
  SeerrErrorKind.network => t.seerr.errorNetwork,
  SeerrErrorKind.generic => t.seerr.errorGeneric,
};
