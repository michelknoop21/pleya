import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Spawns and talks to a real `pleya_verify/fixture_server` process
/// (`bin/serve.dart`) — the fixture a scenario's `sign_in`/`seed`/
/// `fixture_mutate` setup/steps run against. One process per scenario run;
/// [stop] closes its stdin, the same clean-shutdown contract `bin/serve.dart`
/// documents itself.
class FixtureServerHandle {
  final Process process;
  final int port;
  final String controlToken;

  FixtureServerHandle._({required this.process, required this.port, required this.controlToken});

  String get baseUrl => 'http://127.0.0.1:$port';

  static Future<FixtureServerHandle> start({required Directory fixtureServerPackageDir}) async {
    final process = await Process.start('dart', [
      'run',
      'bin/serve.dart',
    ], workingDirectory: fixtureServerPackageDir.path);
    final firstLine = await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw StateError('fixture server did not print its {port, controlToken} line within 30s'),
        );
    final decoded = jsonDecode(firstLine) as Map<String, Object?>;
    return FixtureServerHandle._(
      process: process,
      port: decoded['port'] as int,
      controlToken: decoded['controlToken'] as String,
    );
  }

  Map<String, String> get _controlHeaders => {'Authorization': 'Bearer $controlToken'};

  Future<Map<String, Object?>> verifyState() => _controlGet('/__verify/state');

  /// `PleyaFakeServer.requests` (and so the `/__verify/requests` response)
  /// is a list of bare path strings, not records — casting straight to
  /// `Map<String, Object?>` threw on every real run, and the exception was
  /// swallowed by `runScenario`'s own catch, so every bundle's
  /// `fixture/requests.jsonl` was silently empty. Wrapping each path here
  /// keeps the bundle format (one JSON object per line) without changing
  /// the server's wire shape.
  Future<List<Map<String, Object?>>> requestsSince(int since) async {
    final result = await _controlGet('/__verify/requests?since=$since');
    final raw = result['requests'] as List;
    return [
      for (final entry in raw) entry is Map ? entry.cast<String, Object?>() : {'path': entry},
    ];
  }

  Future<void> seed(String fixtureName) => _controlPost('/__verify/seed', {'fixture': fixtureName});

  /// One `fixture_mutate` step: `POST /__verify/<op>` with the step's other
  /// fields as the body.
  ///
  /// Deliberately a thin pass-through rather than a method per operation.
  /// The fixture server's control plane is the contract; a switch here would
  /// be a second, silently-drifting copy of it, and adding a mutation would
  /// mean editing two packages instead of one.
  Future<Map<String, Object?>> mutate(String op, Map<String, Object?> body) async {
    final result = await _controlPost('/__verify/$op', body);
    if (result['ok'] != true) {
      throw StateError('fixture_mutate "$op" failed: $result');
    }
    return result;
  }

  /// `"<kind>/<slug>"` -> fixture id, as published by `/__verify/state`.
  /// Empty before anything is seeded.
  Future<Map<String, String>> seededIds() async {
    final state = await verifyState();
    final ids = state['seededIds'];
    if (ids is! Map) return const {};
    return {for (final e in ids.entries) '${e.key}': '${e.value}'};
  }

  Future<Map<String, Object?>> _controlGet(String path) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse('$baseUrl$path'));
      _controlHeaders.forEach(request.headers.set);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, Object?>;
    } finally {
      client.close();
    }
  }

  Future<Map<String, Object?>> _controlPost(String path, Map<String, Object?> body) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('$baseUrl$path'));
      _controlHeaders.forEach(request.headers.set);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      return jsonDecode(responseBody) as Map<String, Object?>;
    } finally {
      client.close();
    }
  }

  Future<void> stop() async {
    process.stdin.close().ignore();
    await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return process.exitCode;
      },
    );
  }
}
