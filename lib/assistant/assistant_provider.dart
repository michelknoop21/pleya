import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../services/base_shared_preferences_service.dart';
import '../services/credential_vault.dart';
import '../utils/log_redaction_manager.dart';

/// Where the Assistant's language model runs. This is inference only: it
/// decides nothing about rights or about the Pleya Assistant entitlement.
enum AssistantProviderKind { ollamaServer, ollamaCloud, openRouter }

class AssistantProviderConfig {
  const AssistantProviderConfig({
    required this.kind,
    required this.baseUrl,
    this.model = '',
    this.apiKey = '',
    this.headerName = '',
    this.headerValue = '',
  });

  static const String ollamaCloudUrl = 'https://ollama.com';
  static const String openRouterUrl = 'https://openrouter.ai/api';

  final AssistantProviderKind kind;

  /// Without `/v1`: `http://nas.lan:11434`, [ollamaCloudUrl], [openRouterUrl].
  final String baseUrl;
  final String model;
  final String apiKey;

  /// Optional extra header for an Ollama server behind a reverse proxy.
  final String headerName;
  final String headerValue;

  bool get isOllama => kind != AssistantProviderKind.openRouter;

  bool get isComplete =>
      baseUrl.isNotEmpty && model.isNotEmpty && (kind == AssistantProviderKind.ollamaServer || apiKey.isNotEmpty);

  AssistantProviderConfig copyWith({
    String? baseUrl,
    String? model,
    String? apiKey,
    String? headerName,
    String? headerValue,
  }) => AssistantProviderConfig(
    kind: kind,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    apiKey: apiKey ?? this.apiKey,
    headerName: headerName ?? this.headerName,
    headerValue: headerValue ?? this.headerValue,
  );

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'baseUrl': baseUrl,
    'model': model,
    'apiKey': apiKey,
    'headerName': headerName,
    'headerValue': headerValue,
  };

  static AssistantProviderConfig? fromJson(Map<String, Object?> json) {
    final kind = AssistantProviderKind.values.where((k) => k.name == json['kind']).firstOrNull;
    if (kind == null) return null;
    String read(String key) => json[key] is String ? json[key] as String : '';
    return AssistantProviderConfig(
      kind: kind,
      baseUrl: read('baseUrl'),
      model: read('model'),
      apiKey: read('apiKey'),
      headerName: read('headerName'),
      headerValue: read('headerValue'),
    );
  }
}

/// Device-wide provider settings. One vault-protected blob under a key that
/// `PreferenceSyncPolicy` marks secret: never synced, never exported.
class AssistantProviderStore {
  AssistantProviderStore._();
  static final AssistantProviderStore instance = AssistantProviderStore._();

  static const String key = 'assistant_provider';

  Future<AssistantProviderConfig?> load() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final config = AssistantProviderConfig.fromJson(
        jsonDecode(await CredentialVault.reveal(raw)) as Map<String, Object?>,
      );
      if (config != null) _registerSecrets(config);
      return config;
    } catch (_) {
      // Unreadable is "not configured": the setup state offers a way back.
      return null;
    }
  }

  Future<void> save(AssistantProviderConfig config) async {
    _registerSecrets(config);
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(key, await CredentialVault.protect(jsonEncode(config.toJson())));
  }

  Future<void> clear() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.remove(key);
  }

  static void _registerSecrets(AssistantProviderConfig config) {
    LogRedactionManager.registerCustomValue(config.apiKey);
    LogRedactionManager.registerCustomValue(config.headerValue);
  }
}

/// The base URL without trailing slashes or the `/v1` / `/api` suffix that
/// provider docs print, so `https://ollama.com/v1` and `https://ollama.com`
/// reach the same endpoints.
String normaliseBaseUrl(String url) {
  var result = url.trim().replaceAll(RegExp(r'/+$'), '');
  if (result.endsWith('/v1')) result = result.substring(0, result.length - 3);
  if (result.endsWith('/api') && !result.endsWith('openrouter.ai/api')) result = result.substring(0, result.length - 4);
  return result;
}

/// A header the user may add for a reverse proxy: an HTTP token as name and
/// a value without line breaks.
bool isValidProxyHeader(String name, String value) =>
    RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(name) && !RegExp(r'[\r\n\x00]').hasMatch(value);

enum AssistantModelError { toolsUnsupported, unauthorized, unreachable, timeout, badResponse }

class AssistantModelException implements Exception {
  const AssistantModelException(this.error, [this.detail = '']);
  final AssistantModelError error;
  final String detail;

  @override
  String toString() => 'AssistantModelException(${error.name}${detail.isEmpty ? '' : ': $detail'})';
}

class AssistantToolCall {
  const AssistantToolCall({required this.id, required this.name, required this.arguments});
  final String id;
  final String name;

  /// The raw JSON text the model produced; parsed and validated by the run.
  final String arguments;
}

class AssistantReply {
  const AssistantReply({required this.content, required this.toolCalls, required this.message});
  final String content;
  final List<AssistantToolCall> toolCalls;

  /// The assistant message to append to the history unchanged, so every
  /// provider sees its own tool-call ids back.
  final Map<String, Object?> message;
}

/// One client for all three providers: each speaks OpenAI chat completions
/// with tool calling. Only the base URL, auth and model discovery differ.
class AssistantModelClient {
  AssistantModelClient(this.config, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final AssistantProviderConfig config;
  final http.Client _http;

  static const Duration _chatTimeout = Duration(seconds: 90);
  static const Duration _lookupTimeout = Duration(seconds: 15);

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (config.apiKey.isNotEmpty) 'Authorization': 'Bearer ${config.apiKey}',
    if (config.headerName.isNotEmpty && isValidProxyHeader(config.headerName, config.headerValue))
      config.headerName: config.headerValue,
    if (config.kind == AssistantProviderKind.openRouter) ...{'HTTP-Referer': 'https://pleya.app', 'X-Title': 'Pleya'},
  };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${normaliseBaseUrl(config.baseUrl)}$path').replace(queryParameters: query);

  Future<AssistantReply> chat(List<Map<String, Object?>> messages, List<Map<String, Object?>> tools) async {
    final body = {
      'model': config.model,
      'messages': messages,
      'stream': false,
      if (tools.isNotEmpty) 'tools': tools,
      // OpenRouter otherwise drops `tools` silently on a provider without them.
      if (config.kind == AssistantProviderKind.openRouter) 'provider': {'require_parameters': true},
    };
    final response = await _send(
      () => _http.post(_uri('/v1/chat/completions'), headers: _headers, body: jsonEncode(body)),
      _chatTimeout,
    );
    if (response.statusCode == 400 || response.statusCode == 404) {
      // Ollama: 400 "does not support tools". OpenRouter: 404 "No endpoints
      // found that support tool use".
      final body = response.body.toLowerCase();
      if (body.contains('does not support tools') || body.contains('support tool use')) {
        throw const AssistantModelException(AssistantModelError.toolsUnsupported);
      }
    }
    final data = _json(response);
    final choices = data['choices'];
    final message = choices is List && choices.isNotEmpty && choices.first is Map
        ? (choices.first as Map)['message']
        : null;
    if (message is! Map) throw const AssistantModelException(AssistantModelError.badResponse, 'no message');
    final rawCalls = message['tool_calls'];
    final calls = <AssistantToolCall>[];
    final kept = <Map<String, Object?>>[];
    if (rawCalls is List) {
      for (final (index, raw) in rawCalls.indexed) {
        final function = raw is Map ? raw['function'] : null;
        if (function is! Map || function['name'] is! String) continue;
        kept.add((raw as Map).cast<String, Object?>());
        final args = function['arguments'];
        calls.add(
          AssistantToolCall(
            id: raw['id'] is String && (raw['id'] as String).isNotEmpty ? raw['id'] as String : 'call_$index',
            name: function['name'] as String,
            arguments: args is String ? args : jsonEncode(args ?? const {}),
          ),
        );
      }
    }
    final content = message['content'] is String ? message['content'] as String : '';
    // Back unchanged (reasoning fields included; OpenRouter requires that),
    // with only ids filled in and arguments as text.
    final echo = Map<String, Object?>.of(message.cast<String, Object?>())..['content'] = content;
    if (calls.isNotEmpty) {
      echo['tool_calls'] = [
        for (final (index, c) in calls.indexed)
          {
            ...kept[index],
            'id': c.id,
            'type': 'function',
            'function': {'name': c.name, 'arguments': c.arguments},
          },
      ];
    }
    return AssistantReply(content: content, toolCalls: calls, message: echo);
  }

  /// Models that can call tools. Anything else cannot drive the Assistant,
  /// so it is never offered.
  Future<List<String>> toolModels() async {
    if (config.kind == AssistantProviderKind.openRouter) {
      final data = _json(
        await _send(
          () => _http.get(_uri('/v1/models', {'supported_parameters': 'tools'}), headers: _headers),
          _lookupTimeout,
        ),
      );
      final models = data['data'];
      return [
        if (models is List)
          for (final m in models)
            if (m is Map && m['id'] is String) m['id'] as String,
      ]..sort();
    }
    final tags = _json(await _send(() => _http.get(_uri('/api/tags'), headers: _headers), _lookupTimeout));
    final names = [
      if (tags['models'] is List)
        for (final m in tags['models'] as List)
          if (m is Map && m['name'] is String) m['name'] as String,
    ];
    // `/api/tags` says nothing about tools; `/api/show` does, per model.
    // Four at a time: fast on a LAN, gentle on a small box.
    final result = <String>[];
    var failures = 0;
    for (var i = 0; i < names.length; i += 4) {
      final batch = names.skip(i).take(4);
      await Future.wait([
        for (final name in batch)
          () async {
            try {
              final show = _json(
                await _send(
                  () => _http.post(_uri('/api/show'), headers: _headers, body: jsonEncode({'model': name})),
                  _lookupTimeout,
                ),
              );
              final capabilities = show['capabilities'];
              if (capabilities is List && capabilities.contains('tools')) result.add(name);
            } on AssistantModelException catch (e) {
              if (e.error == AssistantModelError.unauthorized) rethrow;
              failures++;
            }
          }(),
      ]);
    }
    // Every lookup failing is a broken connection, not "no tool models".
    if (names.isNotEmpty && failures == names.length) {
      throw const AssistantModelException(AssistantModelError.badResponse, 'model details unavailable');
    }
    return result..sort();
  }

  Future<http.Response> _send(Future<http.Response> Function() request, Duration timeout) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw const AssistantModelException(AssistantModelError.timeout);
    } on IOException {
      // Sockets, TLS handshakes (a self-signed NAS certificate), HTTP.
      throw const AssistantModelException(AssistantModelError.unreachable);
    } on http.ClientException {
      throw const AssistantModelException(AssistantModelError.unreachable);
    } on FormatException {
      // A malformed header or URL; its message may hold the value.
      throw const AssistantModelException(AssistantModelError.badResponse, 'invalid request');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AssistantModelException(AssistantModelError.unauthorized);
    }
    return response;
  }

  Map<String, dynamic> _json(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AssistantModelException(AssistantModelError.badResponse, 'HTTP ${response.statusCode}');
    }
    try {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) return data;
    } on FormatException {
      // fall through
    }
    throw const AssistantModelException(AssistantModelError.badResponse, 'not JSON');
  }

  void close() => _http.close();
}
