import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// The constant protocol marker every `/v1/*` request must carry — never a
/// secret, mirrors `kAutomationProtocolMarker` in
/// `lib/automation/pleya_verify.dart`.
const String kVerifyProtocolMarker = 'PleyaVerify/1';

/// Thrown when a `/v1/*` call returns something other than the status this
/// client expected (a 403/401/404/405 that isn't otherwise handled, or a
/// non-JSON body where JSON was expected).
class VerifyClientException implements Exception {
  final String method;
  final String path;
  final int statusCode;
  final String body;

  const VerifyClientException({required this.method, required this.path, required this.statusCode, this.body = ''});

  @override
  String toString() => 'VerifyClientException: $method $path -> $statusCode ${body.isEmpty ? '' : '($body)'}';
}

/// One documented endpoint, `(method, path)` — used only to cross-check
/// against `pleya_verify/contract/verify_api_v1.md` in
/// `test/transport_contract_test.dart` (the runner-side half of [C1]; the
/// app-side half is `test/automation/transport_contract_test.dart`). Not
/// consulted at runtime.
typedef VerifyEndpoint = ({String method, String path});

/// Talks `pleya_verify/contract/verify_api_v1.md`'s `/v1/*` control plane
/// against a running Pleya build. One method per documented endpoint —
/// [implementedEndpoints] is the exhaustive list the contract test checks.
class VerifyClient {
  final Uri baseUri;
  final String? token;
  final http.Client _http;

  VerifyClient({required this.baseUri, this.token, http.Client? httpClient}) : _http = httpClient ?? http.Client();

  Map<String, String> get _headers => {
    'X-Pleya-Verify': kVerifyProtocolMarker,
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Uri _uri(String path, [Map<String, String>? query]) => baseUri.replace(path: path, queryParameters: query);

  Future<Map<String, Object?>> _getJson(String path, [Map<String, String>? query]) async {
    final response = await _http.get(_uri(path, query), headers: _headers);
    return _decodeJsonOrThrow('GET', path, response);
  }

  Future<Map<String, Object?>> _postJson(String path, Map<String, Object?> body) async {
    final response = await _http.post(
      _uri(path),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decodeJsonOrThrow('POST', path, response);
  }

  Map<String, Object?> _decodeJsonOrThrow(String method, String path, http.Response response) {
    if (response.statusCode >= 500) {
      throw VerifyClientException(method: method, path: path, statusCode: response.statusCode, body: response.body);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw VerifyClientException(method: method, path: path, statusCode: response.statusCode, body: response.body);
    }
    return {...decoded, '_statusCode': response.statusCode};
  }

  Future<Map<String, Object?>> health() => _getJson('/v1/health');

  Future<Map<String, Object?>> uiTree() => _getJson('/v1/ui_tree');

  Future<Map<String, Object?>> focus() => _getJson('/v1/focus');

  Future<Map<String, Object?>> focusLog({int since = 0}) => _getJson('/v1/focus/log', {'since': '$since'});

  Future<Map<String, Object?>> events({int since = 0}) => _getJson('/v1/events', {'since': '$since'});

  Future<Map<String, Object?>> screens() => _getJson('/v1/screens');

  Future<Map<String, Object?>> automationIds() => _getJson('/v1/automation_ids');

  Future<Map<String, Object?>> viewport() => _getJson('/v1/viewport');

  Future<Map<String, Object?>> logs({int since = 0}) => _getJson('/v1/logs', {'since': '$since'});

  Future<Map<String, Object?>> wait({
    ({String name, int since})? event,
    ({String id, bool? visible, bool? focused})? node,
    int? stableFrames,
    int timeoutMs = 5000,
  }) => _postJson('/v1/wait', {
    if (event != null) 'event': {'name': event.name, 'since': event.since},
    if (node != null)
      'node': {
        'id': node.id,
        if (node.visible != null) 'visible': node.visible,
        if (node.focused != null) 'focused': node.focused,
      },
    if (stableFrames != null) 'stableFrames': stableFrames,
    'timeoutMs': timeoutMs,
  });

  Future<Map<String, Object?>> inputKey(String key) => _postJson('/v1/input/key', {'key': key});

  Future<Map<String, Object?>> inputPointer(double x, double y) => _postJson('/v1/input/pointer', {'x': x, 'y': y});

  Future<Map<String, Object?>> overlay({bool? enabled, bool? showIds, bool? showBounds}) => _postJson('/v1/overlay', {
    if (enabled != null) 'enabled': enabled,
    if (showIds != null) 'showIds': showIds,
    if (showBounds != null) 'showBounds': showBounds,
  });

  /// Diagnostic-only — see [C5]: never the source for a visual PASS.
  Future<Uint8List> screenshot() async {
    final response = await _http.get(_uri('/v1/screenshot'), headers: _headers);
    if (response.statusCode != 200) {
      throw VerifyClientException(method: 'GET', path: '/v1/screenshot', statusCode: response.statusCode);
    }
    return response.bodyBytes;
  }

  Future<Map<String, Object?>> signin({
    required String baseUrl,
    required String username,
    required String password,
    String? setupCode,
  }) => _postJson('/v1/signin', {
    'base_url': baseUrl,
    'username': username,
    'password': password,
    if (setupCode != null) 'setup_code': setupCode,
  });

  Future<Map<String, Object?>> connectionsSeed({
    required String baseUrl,
    required String serverId,
    required String serverName,
    required String userName,
    required String refreshToken,
  }) => _postJson('/v1/connections/seed', {
    'base_url': baseUrl,
    'server_id': serverId,
    'server_name': serverName,
    'user_name': userName,
    'refresh_token': refreshToken,
  });

  Future<Map<String, Object?>> open(String screen, {int timeoutMs = 5000}) =>
      _postJson('/v1/open', {'screen': screen, 'timeoutMs': timeoutMs});

  void close() => _http.close();

  /// Every endpoint `pleya_verify/contract/verify_api_v1.md` documents,
  /// mirrored here so `test/transport_contract_test.dart` can fail the
  /// moment this list and the spec drift apart — the runner-side half of
  /// [C1] (see `test/automation/transport_contract_test.dart` for the
  /// app-side half, which checks `AutomationServer`'s route table the same
  /// way).
  static const List<VerifyEndpoint> implementedEndpoints = [
    (method: 'GET', path: '/v1/health'),
    (method: 'GET', path: '/v1/ui_tree'),
    (method: 'GET', path: '/v1/focus'),
    (method: 'GET', path: '/v1/focus/log'),
    (method: 'GET', path: '/v1/events'),
    (method: 'GET', path: '/v1/screens'),
    (method: 'GET', path: '/v1/automation_ids'),
    (method: 'GET', path: '/v1/viewport'),
    (method: 'GET', path: '/v1/logs'),
    (method: 'POST', path: '/v1/wait'),
    (method: 'POST', path: '/v1/input/key'),
    (method: 'POST', path: '/v1/input/pointer'),
    (method: 'POST', path: '/v1/overlay'),
    (method: 'GET', path: '/v1/screenshot'),
    (method: 'POST', path: '/v1/signin'),
    (method: 'POST', path: '/v1/connections/seed'),
    (method: 'POST', path: '/v1/open'),
  ];
}
