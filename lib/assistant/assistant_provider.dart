import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

import '../services/base_shared_preferences_service.dart';
import '../services/credential_vault.dart';
import '../services/pleya_keychain.dart';
import '../utils/abortable_http_request.dart';
import '../utils/app_logger.dart';
import '../utils/log_redaction_manager.dart';
import '../utils/media_server_http_client.dart' show AbortController;

part 'assistant_models.dart';
part 'assistant_provider_store.dart';

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
    this.webSearchChoice,
    this.ollamaWebKey = '',
    this.timeoutOverride,
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

  /// The user's explicit web-search switch; null until they touch it.
  final bool? webSearchChoice;

  /// Big P may look a title up on the web. Unset, a cloud provider allows it
  /// and an Ollama server does not: local stays local until the user says so.
  bool get webSearch => webSearchChoice ?? kind != AssistantProviderKind.ollamaServer;

  /// An ollama.com key for Ollama web search, for Ollama-server users only;
  /// Ollama Cloud reuses [apiKey].
  final String ollamaWebKey;

  bool get isOllama => kind != AssistantProviderKind.openRouter;

  /// A chat timeout set for this provider and model; null uses the
  /// provider's default.
  final Duration? timeoutOverride;

  /// How long one chat call may take: [timeoutOverride], else the default
  /// of the kind. A hosted router answers fast; Ollama Cloud queues; an
  /// Ollama server may first load the model from disk.
  Duration get providerTimeout => timeoutOverride ?? defaultProviderTimeout(kind);

  static Duration defaultProviderTimeout(AssistantProviderKind kind) => switch (kind) {
    AssistantProviderKind.openRouter => const Duration(seconds: 20),
    AssistantProviderKind.ollamaCloud => const Duration(seconds: 60),
    AssistantProviderKind.ollamaServer => const Duration(seconds: 90),
  };

  bool get isComplete =>
      baseUrl.isNotEmpty && model.isNotEmpty && (kind == AssistantProviderKind.ollamaServer || apiKey.isNotEmpty);

  AssistantProviderConfig copyWith({
    String? baseUrl,
    String? model,
    String? apiKey,
    String? headerName,
    String? headerValue,
    bool? webSearch,
    String? ollamaWebKey,
  }) => AssistantProviderConfig(
    kind: kind,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    apiKey: apiKey ?? this.apiKey,
    headerName: headerName ?? this.headerName,
    headerValue: headerValue ?? this.headerValue,
    webSearchChoice: webSearch ?? webSearchChoice,
    ollamaWebKey: ollamaWebKey ?? this.ollamaWebKey,
    // Set for one model: another model starts from the default again.
    timeoutOverride: model == null || model == this.model ? timeoutOverride : null,
  );

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'baseUrl': baseUrl,
    'model': model,
    'apiKey': apiKey,
    'headerName': headerName,
    'headerValue': headerValue,
    if (webSearchChoice != null) 'webSearch': webSearchChoice,
    'ollamaWebKey': ollamaWebKey,
    if (timeoutOverride case final timeout?) 'timeoutSeconds': timeout.inSeconds,
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
      // Absent until the user chooses: [webSearch] then follows the kind.
      webSearchChoice: json['webSearch'] is bool ? json['webSearch'] as bool : null,
      ollamaWebKey: read('ollamaWebKey'),
      timeoutOverride: switch (json['timeoutSeconds']) {
        final int seconds when seconds > 0 => Duration(seconds: seconds),
        _ => null,
      },
    );
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

  static const Duration _lookupTimeout = Duration(seconds: 15);
  static const Duration _preloadTimeout = Duration(seconds: 60);

  bool _modelMissing = false;

  /// True once [chat] heard that [AssistantProviderConfig.model] is gone
  /// (uninstalled, renamed, withdrawn). The run then ends in a provider
  /// error; the caller reads this to say "pick another model".
  bool get modelMissing => _modelMissing;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (config.apiKey.isNotEmpty) 'Authorization': 'Bearer ${config.apiKey}',
    if (config.headerName.isNotEmpty && isValidProxyHeader(config.headerName, config.headerValue))
      config.headerName: config.headerValue,
    if (config.kind == AssistantProviderKind.openRouter) ...{'HTTP-Referer': 'https://pleya.app', 'X-Title': 'Pleya'},
  };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${normaliseBaseUrl(config.baseUrl)}$path').replace(queryParameters: query);

  /// One model turn, bounded by [AssistantProviderConfig.providerTimeout].
  /// [abort] cancels the request on the wire (the user left); it then ends
  /// as [AssistantModelError.unreachable].
  Future<AssistantReply> chat(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools, {
    AbortController? abort,
  }) async {
    final body = {
      'model': config.model,
      'messages': messages,
      'stream': false,
      if (tools.isNotEmpty) 'tools': tools,
      // OpenRouter otherwise drops `tools` silently on a provider without them.
      if (config.kind == AssistantProviderKind.openRouter) 'provider': {'require_parameters': true},
    };
    final response = await _send(
      () => sendAbortableHttpRequest(
        _http,
        'POST',
        _uri('/v1/chat/completions'),
        headers: _headers,
        body: jsonEncode(body),
        timeout: config.providerTimeout,
        abortTrigger: abort?.trigger,
      ),
      config.providerTimeout,
    );
    if (response.statusCode == 400 || response.statusCode == 404) {
      // Ollama: 400 "does not support tools". OpenRouter: 404 "No endpoints
      // found that support tool use".
      final body = response.body.toLowerCase();
      if (body.contains('does not support tools') || body.contains('support tool use')) {
        throw const AssistantModelException(AssistantModelError.toolsUnsupported);
      }
      // Ollama: 404 `model "x" not found, try pulling it first`.
      // OpenRouter: 400 `x is not a valid model ID`.
      if ((body.contains('model') && body.contains('not found')) || body.contains('not a valid model')) {
        _modelMissing = true;
        throw const AssistantModelException(AssistantModelError.badResponse, 'model not found');
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

  /// Ids of the models that can call tools, sorted; [models] has the details.
  Future<List<String>> toolModels() async => [for (final m in await models()) m.id]..sort();

  Future<http.Response> _send(Future<http.Response> Function() request, Duration timeout) async {
    final response = await _guard(request, timeout);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AssistantModelException(AssistantModelError.unauthorized);
    }
    return response;
  }

  /// Transport failures as [AssistantModelException]s, for plain and
  /// streamed requests alike.
  Future<T> _guard<T>(Future<T> Function() request, Duration timeout) async {
    try {
      return await request().timeout(timeout);
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
