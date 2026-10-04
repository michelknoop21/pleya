part of 'assistant_provider.dart';

/// Rough cost of an OpenRouter model, from its prompt price per million
/// tokens. Enough to tell a free model from an expensive one at a glance.
enum AssistantPriceClass { free, low, medium, high }

/// One tool-capable model with what the picker shows about it. Ollama fills
/// size, parameters and [modifiedAt]; OpenRouter fills context and price.
class AssistantModelInfo {
  const AssistantModelInfo({
    required this.id,
    String? name,
    this.sizeBytes,
    this.modifiedAt,
    this.parameterSize,
    this.quantization,
    this.family,
    this.contextLength,
    this.promptPrice,
    this.completionPrice,
  }) : name = name ?? id;

  /// What goes into [AssistantProviderConfig.model].
  final String id;
  final String name;
  final int? sizeBytes;

  /// Ollama: when the model was last pulled. OpenRouter: when it was added.
  final DateTime? modifiedAt;
  final String? parameterSize;
  final String? quantization;
  final String? family;
  final int? contextLength;

  /// USD per token, as OpenRouter publishes it.
  final double? promptPrice;
  final double? completionPrice;

  /// `openai` for `openai/gpt-4o`; empty for an Ollama name.
  String get vendor => id.contains('/') ? id.substring(0, id.indexOf('/')) : '';

  AssistantPriceClass? get priceClass {
    final prompt = promptPrice;
    if (prompt == null) return null;
    if (prompt == 0 && (completionPrice ?? 0) == 0) return AssistantPriceClass.free;
    final perMillion = prompt * 1e6;
    if (perMillion < 0.5) return AssistantPriceClass.low;
    if (perMillion < 3) return AssistantPriceClass.medium;
    return AssistantPriceClass.high;
  }

  /// One entry of Ollama's `/api/tags`, or null without a name.
  static AssistantModelInfo? fromOllamaTag(Object? raw) {
    if (raw is! Map || raw['name'] is! String) return null;
    final details = raw['details'] is Map ? raw['details'] as Map : const {};
    String? text(Object? v) => v is String && v.isNotEmpty ? v : null;
    return AssistantModelInfo(
      id: raw['name'] as String,
      sizeBytes: raw['size'] is num ? (raw['size'] as num).toInt() : null,
      modifiedAt: raw['modified_at'] is String ? DateTime.tryParse(raw['modified_at'] as String) : null,
      parameterSize: text(details['parameter_size']),
      quantization: text(details['quantization_level']),
      family: text(details['family']),
    );
  }

  /// One entry of OpenRouter's `/api/v1/models`, or null without an id.
  static AssistantModelInfo? fromOpenRouter(Object? raw) {
    if (raw is! Map || raw['id'] is! String) return null;
    final pricing = raw['pricing'] is Map ? raw['pricing'] as Map : const {};
    double? price(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
    final created = raw['created'];
    return AssistantModelInfo(
      id: raw['id'] as String,
      name: raw['name'] is String && (raw['name'] as String).isNotEmpty ? raw['name'] as String : null,
      modifiedAt: created is num ? DateTime.fromMillisecondsSinceEpoch(created.toInt() * 1000, isUtc: true) : null,
      contextLength: raw['context_length'] is num ? (raw['context_length'] as num).toInt() : null,
      promptPrice: price(pricing['prompt']),
      completionPrice: price(pricing['completion']),
    );
  }
}

/// One line of Ollama's streamed `/api/pull`.
class AssistantPullProgress {
  const AssistantPullProgress({required this.status, this.completed, this.total});
  final String status;
  final int? completed;
  final int? total;

  /// 0..1 while a layer downloads, otherwise null.
  double? get fraction {
    final t = total, c = completed;
    return t != null && t > 0 && c != null ? (c / t).clamp(0, 1).toDouble() : null;
  }

  bool get isSuccess => status == 'success';
}

/// The `error` an Ollama pull reported, verbatim, for the screen to map.
class AssistantPullException implements Exception {
  const AssistantPullException(this.message);
  final String message;

  @override
  String toString() => 'AssistantPullException($message)';
}

/// Model discovery, updating and preloading. Ollama API:
/// https://docs.ollama.com/api (`/api/tags`, `/api/show`, `/api/pull`,
/// `/api/generate`); OpenRouter: https://openrouter.ai/docs (models list).
extension AssistantModelCatalog on AssistantModelClient {
  /// Models that can call tools, most recent first. Anything else cannot
  /// drive the Assistant, so it is never offered.
  Future<List<AssistantModelInfo>> models() async {
    final List<AssistantModelInfo> result;
    if (config.kind == AssistantProviderKind.openRouter) {
      final data = _json(
        await _send(
          () => _http.get(_uri('/v1/models', {'supported_parameters': 'tools'}), headers: _headers),
          AssistantModelClient._lookupTimeout,
        ),
      );
      result = [
        if (data['data'] is List)
          for (final m in data['data'] as List) ?AssistantModelInfo.fromOpenRouter(m),
      ];
    } else {
      result = await _ollamaToolModels();
    }
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return result..sort((a, b) {
      final byDate = (b.modifiedAt ?? epoch).compareTo(a.modifiedAt ?? epoch);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
  }

  Future<List<AssistantModelInfo>> _ollamaToolModels() async {
    final tags = _json(
      await _send(() => _http.get(_uri('/api/tags'), headers: _headers), AssistantModelClient._lookupTimeout),
    );
    final installed = [
      if (tags['models'] is List)
        for (final m in tags['models'] as List) ?AssistantModelInfo.fromOllamaTag(m),
    ];
    // `/api/tags` says nothing about tools; `/api/show` does, per model.
    // Four at a time: fast on a LAN, gentle on a small box.
    final result = <AssistantModelInfo>[];
    var failures = 0;
    for (var i = 0; i < installed.length; i += 4) {
      await Future.wait([
        for (final model in installed.skip(i).take(4))
          () async {
            try {
              final show = _json(
                await _send(
                  () => _http.post(_uri('/api/show'), headers: _headers, body: jsonEncode({'model': model.id})),
                  AssistantModelClient._lookupTimeout,
                ),
              );
              final capabilities = show['capabilities'];
              if (capabilities is List && capabilities.contains('tools')) result.add(model);
            } on AssistantModelException catch (e) {
              if (e.error == AssistantModelError.unauthorized) rethrow;
              failures++;
            }
          }(),
      ]);
    }
    // Every lookup failing is a broken connection, not "no tool models".
    if (installed.isNotEmpty && failures == installed.length) {
      throw const AssistantModelException(AssistantModelError.badResponse, 'model details unavailable');
    }
    return result;
  }

  /// Pulls [model] again on an Ollama server, which fetches only the layers
  /// that changed. Emits each streamed status line; throws
  /// [AssistantPullException] on an `error` line.
  Stream<AssistantPullProgress> pullModel(String model) async* {
    final request = http.Request('POST', _uri('/api/pull'))
      ..headers.addAll(_headers)
      ..body = jsonEncode({'model': model, 'stream': true});
    final response = await _guard(() => _http.send(request), AssistantModelClient._lookupTimeout);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AssistantModelException(AssistantModelError.unauthorized);
    }
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        // A pull may run for minutes, but a silent minute is a dead stream.
        .timeout(const Duration(minutes: 1));
    try {
      await for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final Object? data;
        try {
          data = jsonDecode(line);
        } on FormatException {
          throw const AssistantModelException(AssistantModelError.badResponse, 'not JSON');
        }
        if (data is! Map) continue;
        if (data['error'] != null) throw AssistantPullException('${data['error']}');
        if (response.statusCode < 200 || response.statusCode >= 300) continue;
        yield AssistantPullProgress(
          status: data['status'] is String ? data['status'] as String : '',
          completed: data['completed'] is num ? (data['completed'] as num).toInt() : null,
          total: data['total'] is num ? (data['total'] as num).toInt() : null,
        );
      }
    } on TimeoutException {
      throw const AssistantModelException(AssistantModelError.timeout);
    } on IOException {
      throw const AssistantModelException(AssistantModelError.unreachable);
    } on http.ClientException {
      throw const AssistantModelException(AssistantModelError.unreachable);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AssistantModelException(AssistantModelError.badResponse, 'HTTP ${response.statusCode}');
    }
  }

  /// Loads the configured model into memory without a prompt, so the first
  /// real question does not wait for it (Ollama FAQ, "preload a model").
  Future<void> preload({String keepAlive = '10m'}) async {
    _json(
      await _send(
        () => _http.post(
          _uri('/api/generate'),
          headers: _headers,
          body: jsonEncode({'model': config.model, 'keep_alive': keepAlive}),
        ),
        AssistantModelClient._preloadTimeout,
      ),
    );
  }
}
