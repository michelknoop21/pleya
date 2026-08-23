import 'dart:async';

import '../connection/connection.dart';
import '../exceptions/media_server_exceptions.dart';
import '../models/pleya_server/pleya_wire.dart';
import '../utils/app_logger.dart';
import '../utils/log_redaction_manager.dart';
import 'pleya_server_auth_service.dart';

/// Holds the access token for one Pleya Server connection and keeps it alive.
///
/// ## Why this is a class and not three lines in the client
///
/// The refresh token rotates on every use and the old one dies immediately, so
/// two refreshes running at once are by definition a reuse: the second one
/// presents a token the server has already retired, answers
/// `auth.refresh_token_reused`, and the server may revoke the whole chain. A
/// screen that opens with four parallel requests would hit exactly that on the
/// first launch after a restart, when every one of them finds an expired
/// access token at the same moment.
///
/// So refreshing is single-flight: the first caller performs it and everyone
/// else awaits the same future. Pleya Web landed on the same rule for the same
/// reason.
///
/// ## What survives a restart
///
/// Only the refresh token, in the connection row. An access token is short
/// lived, so persisting one buys a few minutes and widens the window in which
/// a usable secret sits on disk. After a restart the session therefore starts
/// with no access token and mints one on the first request.
// The two private fields below are assigned from named parameters rather than
// through initializing formals so the public constructor keeps documented
// parameter names; dart_code_linter flags the pattern, and this is the one
// place it is deliberate.
// ignore_for_file: prefer_initializing_formals

class PleyaServerSession {
  PleyaServerSession({
    required PleyaServerConnection connection,
    required PleyaServerAuthService auth,
    this.onTokensRotated,
    DateTime Function()? now,
  }) : _connection = connection,
       _auth = auth,
       _now = now ?? DateTime.now;

  /// Refresh this long before the access token actually expires. A token that
  /// is valid for another two seconds is not worth starting a request with:
  /// the request would outlive it and come back 401.
  static const Duration refreshMargin = Duration(seconds: 30);

  final PleyaServerAuthService _auth;
  final DateTime Function() _now;

  /// Called with the connection carrying the rotated refresh token, before the
  /// new access token is handed to anyone. Persisting must happen first: a
  /// rotation that is used but not stored leaves the row holding a token the
  /// server has already retired, and the next launch spends it on a revocation.
  final Future<void> Function(PleyaServerConnection connection)? onTokensRotated;

  PleyaServerConnection _connection;
  PleyaServerConnection get connection => _connection;

  String? _accessToken;
  DateTime? _accessTokenExpiry;
  Future<String>? _inFlight;

  /// True once this session has stopped trusting its refresh token. It stays
  /// dead for the rest of its own life, because retrying a token the server
  /// just rejected only re-triggers the rejection.
  ///
  /// In memory only, and deliberately so. This used to also erase the token
  /// from the connection row, which turned a single bad answer into a
  /// permanent condition: the empty token survived the restart, every launch
  /// then failed before it reached the network, and the only way out was
  /// typing the server address again. Three things reach this line without
  /// anything having been revoked — a rotation whose response was lost, a
  /// second session spending the same token, and a 401 from a proxy or captive
  /// portal that never reached Pleya — so the token is kept and the next
  /// launch is allowed to try it. A chain that really is dead costs one failed
  /// refresh per launch; a chain that was fine recovers on its own.
  ///
  /// The connection itself is only ever removed by the user.
  bool get isRevoked => _revoked;
  bool _revoked = false;

  /// The current access token, minting or refreshing one when needed.
  ///
  /// Throws [PleyaRefreshChainRevokedException] when the chain is gone, and
  /// whatever the transport threw when the server is simply unreachable. The
  /// two are deliberately different: one means sign in again, the other means
  /// try again later.
  ///
  /// Deliberately `async` so a revoked session rejects the returned future
  /// instead of throwing at the call site. Half the callers are inside a
  /// `Future.wait` or a `then`, and a synchronous throw there escapes the error
  /// handling they already have. The body still runs to `_refreshOnce`
  /// synchronously, which is what keeps the single-flight guarantee.
  Future<String> accessToken() async {
    if (_revoked) {
      throw const PleyaRefreshChainRevokedException('auth.refresh_token_reused');
    }
    final token = _accessToken;
    final expiry = _accessTokenExpiry;
    if (token != null && expiry != null && _now().isBefore(expiry.subtract(refreshMargin))) {
      return token;
    }
    return _refreshOnce();
  }

  /// The access token this session last minted, or null when there is none or
  /// it has run out.
  ///
  /// Synchronous and therefore never mints. It exists for
  /// `MediaServerClient.streamHeaders`, which is a getter the player reads at
  /// open time and cannot await. Handing over an expired token there would be
  /// worse than handing over nothing: nothing gives a clean 401 the player
  /// surfaces, an expired one gives the same 401 while looking authorised.
  String? get cachedAccessToken {
    final token = _accessToken;
    final expiry = _accessTokenExpiry;
    if (token == null || expiry == null) return null;
    return _now().isBefore(expiry) ? token : null;
  }

  /// Force the next request to mint a fresh token. Called after a 401 on a
  /// request that carried a token the session believed was still good, which
  /// happens when a server restarts and drops its signing key.
  void invalidateAccessToken() {
    _accessToken = null;
    _accessTokenExpiry = null;
  }

  /// Let a revoked session spend its stored refresh token one more time.
  ///
  /// A cold start already gets this for free: a fresh session object starts
  /// with `_revoked == false` and the kept token, which is how a chain that
  /// was never actually dead recovers after a restart. Within a running app
  /// there was no equivalent, so "reconnect" probed health forever without a
  /// single POST to `/auth/refresh` (log jv19q: four probes, zero attempts).
  ///
  /// Only ever called from an explicit user action. Wiring it to a timer or a
  /// sweep would turn a genuinely dead chain into a refresh storm, and the
  /// server answers each of those with the same rejection.
  void retryAfterRejection() {
    if (!_revoked) return;
    _revoked = false;
    invalidateAccessToken();
  }

  Future<String> _refreshOnce() {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _performRefresh();
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<String> _performRefresh() async {
    final refreshToken = _connection.refreshToken;
    if (refreshToken.isEmpty) {
      _revoked = true;
      throw const PleyaNoStoredCredentialsException();
    }
    final PleyaTokenPair pair;
    try {
      pair = await _auth.refresh(baseUrl: _connection.baseUrl, refreshToken: refreshToken);
    } on PleyaRefreshChainRevokedException {
      // Dead for this session, but the token stays on disk. See the note on
      // [isRevoked] for why erasing it was worse than keeping it.
      _revoked = true;
      rethrow;
    } on MediaServerAuthException catch (e) {
      // A 401 or 403 means this token did not work. That is a reason to stop
      // spending it for now, not a reason to destroy it.
      if (e.statusCode == 401 || e.statusCode == 403) {
        _revoked = true;
      }
      rethrow;
    }

    LogRedactionManager.registerServer(_connection.baseUrl, pair.accessToken);
    _connection = _connection.copyWith(
      refreshToken: pair.refreshToken,
      status: ConnectionStatus.online,
      lastAuthenticatedAt: _now(),
    );
    // Persist before handing the access token out. If the app dies between
    // these two lines the worst case is a refresh that is stored but unused,
    // which costs one extra rotation. The reverse order costs the chain.
    await _persist();
    _accessToken = pair.accessToken;
    _accessTokenExpiry = _now().add(Duration(milliseconds: pair.expiresInMs));
    return pair.accessToken;
  }

  /// Seed the session from a sign-in that just happened, so the first request
  /// does not spend a rotation on a token that is seconds old.
  void adoptTokens(PleyaTokenPair pair) {
    LogRedactionManager.registerServer(_connection.baseUrl, pair.accessToken);
    _revoked = false;
    _accessToken = pair.accessToken;
    _accessTokenExpiry = _now().add(Duration(milliseconds: pair.expiresInMs));
    _connection = _connection.copyWith(
      refreshToken: pair.refreshToken,
      status: ConnectionStatus.online,
      lastAuthenticatedAt: _now(),
    );
  }

  Future<void> _persist() async {
    final listener = onTokensRotated;
    if (listener == null) return;
    try {
      await listener(_connection);
    } catch (e, st) {
      appLogger.e('PleyaServerSession: failed to persist rotated refresh token', error: e, stackTrace: st);
    }
  }

  /// Authorization header for a request, or an empty map when the session
  /// cannot produce a token. Callers that must fail loudly use [accessToken].
  Future<Map<String, String>> authHeaders() async {
    final token = await accessToken();
    return {'Authorization': 'Bearer $token'};
  }
}
