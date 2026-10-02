import '../connection/connection.dart';
import 'profile.dart';

/// Why a profile got no Pleya Server credential. Every value here is a normal
/// outcome, and none of them is a reason to substitute a different identity.
enum PleyaServerCredentialMiss {
  /// The profile carries no connection id: a row written before this kind
  /// existed, or a bind that never completed.
  noConnection,

  /// The profile names a different connection than the one offered. On a
  /// server with two household accounts signed in, this is the case that
  /// matters: the offered connection is perfectly usable and belongs to
  /// somebody else.
  otherAccount,
}

/// Which credential a profile may act with on a Pleya Server, and when it may
/// act with none.
///
/// ## Why this exists as its own thing
///
/// `UserProfileProvider._resolvePlexAuth` is a three-step chain that can end at
/// the account owner's token twice over: once as the correct answer for a local
/// profile bound to a plain Plex account, and once as a stopgap for a Home
/// profile whose binder has not run. On plex.tv the worst case of that fallback
/// is reading the owner's settings instead of yours. Chapter 4.1 of the
/// architecture names it as the thing that stops being defensible here: a Pleya
/// Server has real roles and real per-library permissions, so acting as the
/// owner is not "the wrong settings" but "somebody else's access".
///
/// So there is no fallback in this file at all. A [PleyaServerProfile] acts
/// with the connection it names, or with nothing. The credential *is* the
/// connection: one Pleya Server connection carries exactly one account's
/// refresh token, which is what makes the answer unambiguous rather than a
/// best guess.
///
/// A profile of another kind is a different question and gets a different
/// answer: [resolve] passes those through unchanged, because a local profile
/// bound to a Pleya Server connection is the pre-PS-9 shape and still works.
/// Restructuring the Plex and Jellyfin resolution paths to share an abstraction
/// with this one is explicitly out of scope for PS-9.
class PleyaServerCredentialResolver {
  const PleyaServerCredentialResolver();

  /// Whether [profile] may bind and act with [connection].
  ///
  /// Deliberately synchronous and dependency-free. The decision is a property
  /// of the two arguments, and a resolver that had to reach into a registry to
  /// answer it would be a resolver that could fail open on a slow read.
  PleyaServerResolution resolve(Profile? profile, PleyaServerConnection connection) {
    if (profile is! PleyaServerProfile) {
      // A local profile with a Pleya Server connection on it is what every
      // sign-in produced before PS-9, and it keeps working: there is exactly
      // one identity in play, so there is nothing to confuse it with.
      return PleyaServerResolution.hit(connection);
    }

    final named = profile.pleyaConnectionId;
    if (named == null || named.isEmpty) {
      return const PleyaServerResolution.miss(PleyaServerCredentialMiss.noConnection);
    }
    if (named != connection.id) {
      return const PleyaServerResolution.miss(PleyaServerCredentialMiss.otherAccount);
    }
    return PleyaServerResolution.hit(connection);
  }
}

/// Either the connection a profile acts with, or the reason it acts with none.
/// Never both, and never a substitute.
class PleyaServerResolution {
  const PleyaServerResolution.hit(PleyaServerConnection this.connection) : miss = null;
  const PleyaServerResolution.miss(PleyaServerCredentialMiss this.miss) : connection = null;

  final PleyaServerConnection? connection;
  final PleyaServerCredentialMiss? miss;

  bool get isHit => connection != null;
}
