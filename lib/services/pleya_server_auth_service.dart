import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../connection/connection.dart';
import '../exceptions/media_server_exceptions.dart';
import '../models/pleya_server/pleya_wire.dart';
import '../utils/app_logger.dart';
import '../utils/log_redaction_manager.dart';
import '../utils/media_server_http_client.dart';
import '../utils/media_server_timeouts.dart';

/// The protocol path carries the major version. Every request goes through it;
/// nothing else on the server is part of the contract.
const String pleyaProtocolPrefix = '/pleya/v1';

/// Auth flow for a [PleyaServerConnection], per chapter 6 of the protocol
/// specification and [DEC-039].
///
/// Three ways in, one way to stay in:
///
///   * [completeSetup] exchanges the one-time setup code printed on the
///     server's console for the bootstrap owner and a token pair. Only valid
///     while `info.auth.setup_required` is true.
///   * [login] exchanges a username and password for a token pair.
///   * [refresh] exchanges a refresh token for a new pair. The old token dies
///     on use, so the caller must persist the new one before the next call.
///
/// The service is stateless. Holding the tokens and deciding when to refresh
/// is [PleyaServerSession]'s job, because that is where single-flight has to
/// live.
class PleyaServerAuthService {
  PleyaServerAuthService({http.Client Function()? httpClientFactory}) : _testHttpClientFactory = httpClientFactory;

  /// Injection point for the HTTP transport. Null means the platform default.
  ///
  /// A factory rather than a client, because each [MediaServerHttpClient]
  /// closes its underlying client on `close()` and these are short-lived: one
  /// per call. Tests hand in a `MockClient` factory here, which is the only
  /// way to assert what goes on the wire without a live server.
  final http.Client Function()? _testHttpClientFactory;

  MediaServerHttpClient _http(String baseUrl) {
    LogRedactionManager.registerServerUrl(baseUrl);
    return MediaServerHttpClient(
      baseUrl: '$baseUrl$pleyaProtocolPrefix',
      defaultHeaders: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
      client: _testHttpClientFactory?.call(),
    );
  }

  /// Normalise what a user typed into a base URL the client can build on.
  ///
  /// Strips a trailing slash and a trailing `/pleya/v1`, because someone who
  /// copies the URL out of a browser tab or out of the documentation lands on
  /// the protocol root as often as on the server root, and `/pleya/v1/pleya/v1`
  /// is a 404 that reads like a broken server.
  static String normaliseBaseUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) throw const MediaServerUrlException('Enter a server address');
    if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'http://$url';
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith(pleyaProtocolPrefix)) {
      url = url.substring(0, url.length - pleyaProtocolPrefix.length);
    }
    return url;
  }

  /// Read `GET /info` without authenticating.
  ///
  /// This is what tells the UI whether it is looking at a Pleya Server at all,
  /// whether setup still has to happen, and what the server can do. It carries
  /// no server name and no version on purpose; those live behind auth in
  /// `GET /server`.
  Future<PleyaInfo> probe(String baseUrl) async {
    final normalised = normaliseBaseUrl(baseUrl);
    final client = _http(normalised);
    try {
      final response = await client.get('/info', timeout: MediaServerTimeouts.jellyfinManualConnect);
      if (response.statusCode != 200) {
        throw MediaServerUrlException('Server answered HTTP ${response.statusCode} on /info');
      }
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const MediaServerUrlException('That address did not answer with Pleya Protocol');
      }
      final info = PleyaInfo.fromJson(data);
      if (info.major != 1) {
        throw MediaServerUrlException('Server speaks Pleya Protocol v${info.major}, this app speaks v1');
      }
      return info;
    } on PleyaWireFormatException catch (e) {
      throw MediaServerUrlException('That address did not answer with Pleya Protocol: ${e.message}');
    } on TimeoutException {
      throw const MediaServerUrlException('Server did not respond in time');
    } on MediaServerHttpException catch (e) {
      throw MediaServerUrlException(e.message.isEmpty ? 'Could not reach that address' : e.message);
    } finally {
      client.close();
    }
  }

  /// Exchange the one-time setup code for the bootstrap owner plus a token
  /// pair. Only reachable while `info.auth.setup_required` is true; a server
  /// that already has an owner answers 409.
  Future<PleyaAuthResult> completeSetup({
    required String baseUrl,
    required String setupCode,
    required String username,
    required String password,
    String? deviceId,
    String? deviceName,
  }) => _authenticate(
    baseUrl: baseUrl,
    path: '/auth/setup',
    body: {'setup_code': setupCode, 'username': username, 'password': password},
    username: username,
    deviceId: deviceId,
    deviceName: deviceName,
  );

  /// Exchange a username and password for a token pair.
  Future<PleyaAuthResult> login({
    required String baseUrl,
    required String username,
    required String password,
    String? deviceId,
    String? deviceName,
  }) => _authenticate(
    baseUrl: baseUrl,
    path: '/auth/login',
    body: {'username': username, 'password': password},
    username: username,
    deviceId: deviceId,
    deviceName: deviceName,
  );

  Future<PleyaAuthResult> _authenticate({
    required String baseUrl,
    required String path,
    required Map<String, Object?> body,
    required String username,
    String? deviceId,
    String? deviceName,
  }) async {
    final normalised = normaliseBaseUrl(baseUrl);
    final info = await probe(normalised);
    final client = _http(normalised);
    // The device fields go on the wire only when the server says it knows
    // them. `LoginRequest` and `SetupRequest` are closed schemas, so a server
    // without `capabilities.sessions` refuses the whole request rather than
    // ignoring two unknown fields — which is exactly why the probe above runs
    // before the post rather than after a failure.
    if (info.capabilities.sessions) {
      if (deviceId != null && deviceId.isNotEmpty) body['device_id'] = deviceId;
      if (deviceName != null && deviceName.isNotEmpty) body['device_name'] = deviceName;
    }
    try {
      final response = await client.post(
        path,
        body: jsonEncode(body),
        timeout: MediaServerTimeouts.jellyfinManualConnect,
      );
      if (response.statusCode != 200) throw _authFailure(response);
      final data = response.data;
      if (data is! Map<String, dynamic>) throw const MediaServerAuthException('Auth response was not JSON');
      return PleyaAuthResult(
        baseUrl: normalised,
        info: info,
        tokens: PleyaTokenPair.fromJson(data),
        userName: username,
      );
    } on PleyaWireFormatException catch (e) {
      throw MediaServerAuthException('Auth response did not match the contract: ${e.message}');
    } on TimeoutException {
      throw const MediaServerUrlException('Server did not respond in time');
    } finally {
      client.close();
    }
  }

  /// Exchange a refresh token for a new pair.
  ///
  /// The token rotates on every use and the old one dies immediately, so a
  /// caller that loses the answer has lost the chain. A second call with the
  /// same token yields `auth.refresh_token_reused` and the server is allowed to
  /// revoke everything behind it, which is why this must only ever be called
  /// from one place at a time. [PleyaServerSession] is that place.
  Future<PleyaTokenPair> refresh({required String baseUrl, required String refreshToken}) async {
    final normalised = normaliseBaseUrl(baseUrl);
    final client = _http(normalised);
    try {
      final response = await client.post(
        '/auth/refresh',
        body: jsonEncode({'refresh_token': refreshToken}),
        timeout: MediaServerTimeouts.interactive,
      );
      if (response.statusCode != 200) throw _authFailure(response);
      final data = response.data;
      if (data is! Map<String, dynamic>) throw const MediaServerAuthException('Refresh response was not JSON');
      return PleyaTokenPair.fromJson(data);
    } on PleyaWireFormatException catch (e) {
      throw MediaServerAuthException('Refresh response did not match the contract: ${e.message}');
    } on TimeoutException {
      throw const MediaServerUrlException('Server did not respond in time');
    } finally {
      client.close();
    }
  }

  /// Read `GET /server` with an access token. Gives the connection its real
  /// name; before the first successful call the connection wears a placeholder.
  Future<PleyaServerDetail?> fetchServerDetail({required String baseUrl, required String accessToken}) async {
    final client = _http(normaliseBaseUrl(baseUrl));
    try {
      final response = await client.get(
        '/server',
        headers: {'Authorization': 'Bearer $accessToken'},
        timeout: MediaServerTimeouts.interactive,
      );
      if (response.statusCode != 200) return null;
      final data = response.data;
      if (data is! Map<String, dynamic>) return null;
      return PleyaServerDetail.fromJson(data);
    } catch (e) {
      appLogger.d('PleyaServerAuthService: /server unavailable', error: e);
      return null;
    } finally {
      client.close();
    }
  }

  /// Translate a non-200 auth answer into the app's exception vocabulary.
  ///
  /// The protocol error code decides, not the status code. A 401 on login is a
  /// wrong password and a 401 on refresh is a dead chain, and those are two
  /// different things for a caller even though HTTP spells them the same.
  MediaServerException _authFailure(MediaServerResponse response) {
    final error = PleyaError.tryParse(response.data);
    final code = error?.code;
    if (code == 'auth.refresh_token_reused') {
      return PleyaRefreshChainRevokedException(code!);
    }
    if (code == 'auth.rate_limited') {
      return PleyaRateLimitedException(retryAfterMs: error?.retryAfterMs);
    }
    if (code == 'auth.setup_already_done') {
      return const MediaServerAuthException('This server already has an owner; sign in instead', statusCode: 409);
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      final message = error?.message.isNotEmpty == true ? 'Sign-in was rejected' : 'Invalid username or password';
      // Only Pleya's own envelope proves this came from Pleya. A reverse
      // proxy, a captive portal or an auth gateway in front of the server
      // answers 401 too, and those say nothing about the session.
      if (code != null && code.startsWith('auth.')) {
        return PleyaAuthRejectedException(code, message, statusCode: response.statusCode);
      }
      return MediaServerAuthException(message, statusCode: response.statusCode);
    }
    if (response.statusCode == 409) {
      return MediaServerAuthException(code ?? 'Conflict', statusCode: 409);
    }
    return MediaServerHttpException(
      type: MediaServerHttpErrorType.unknown,
      statusCode: response.statusCode,
      responseData: response.data,
      message: code ?? 'HTTP ${response.statusCode}',
    );
  }
}

/// What a successful setup or login yields: where the server is, what it says
/// it can do, and the token pair to say it with.
class PleyaAuthResult {
  const PleyaAuthResult({required this.baseUrl, required this.info, required this.tokens, required this.userName});

  final String baseUrl;
  final PleyaInfo info;
  final PleyaTokenPair tokens;
  final String userName;
}

/// A rejection Pleya itself spoke: a 401 or 403 carrying an `auth.*` code from
/// the protocol envelope.
///
/// The type exists so the health probe can tell a real verdict from a 401 that
/// some box in between produced. Without it the two are the same status code
/// and the app tells people their session expired because a captive portal
/// wanted a click.
class PleyaAuthRejectedException extends MediaServerAuthException {
  const PleyaAuthRejectedException(this.code, super.message, {super.statusCode});

  /// The protocol code, always starting with `auth.`.
  final String code;
}

/// There is no refresh token to spend, so there is nothing to try.
///
/// Its own type because it is the one auth failure that needs no network and
/// cannot resolve itself: only a sign-in produces a token.
class PleyaNoStoredCredentialsException extends MediaServerAuthException {
  const PleyaNoStoredCredentialsException() : super('No stored credentials for this server');
}

/// The refresh chain is gone: the server saw the same refresh token twice and
/// revoked everything behind it.
///
/// Distinct from a plain [MediaServerAuthException] because the recovery is
/// different: a wrong password is retryable by typing a better one, this needs
/// a fresh sign-in. The stored token is kept even so, because a lost rotation
/// response and a second session spending the same token both land here
/// without anything having actually been revoked. See
/// [PleyaServerSession.isRevoked].
class PleyaRefreshChainRevokedException extends MediaServerAuthException {
  const PleyaRefreshChainRevokedException(this.code)
    : super('Refresh token was reused; sign in again', statusCode: 401);

  final String code;
}

/// The server's rate limiter said no. [retryAfterMs] is what it asked for, or
/// null when it did not say, which is not the same as zero.
class PleyaRateLimitedException extends MediaServerAuthException {
  const PleyaRateLimitedException({this.retryAfterMs}) : super('Too many attempts', statusCode: 429);

  final int? retryAfterMs;
}
