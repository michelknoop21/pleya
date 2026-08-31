import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Thrown when a `/__verify/*` control-plane call to the fixture server does
/// not complete within [FixtureServerHandle.timeout] — the same "fail fast
/// rather than hang the whole run" property `VerifyClient` already gives
/// every `/v1/*` call. A `fixture_mutate`/`seed`/`sign_in` step that never
/// gets an answer must fail the step, not wedge the scenario forever.
class FixtureControlTimeoutException implements Exception {
  final String path;
  final Duration timeout;

  const FixtureControlTimeoutException({required this.path, required this.timeout});

  @override
  String toString() => 'FixtureControlTimeoutException: $path did not answer within $timeout';
}

/// Spawns and talks to a real `pleya_verify/fixture_server` process
/// (`bin/serve.dart`) — the fixture a scenario's `sign_in`/`seed`/
/// `fixture_mutate` setup/steps run against. One process per scenario run;
/// [stop] closes its stdin, the same clean-shutdown contract `bin/serve.dart`
/// documents itself.
class FixtureServerHandle {
  final Process process;
  final int port;
  final String controlToken;

  /// Deadline on every `/__verify/*` control call — see
  /// [FixtureControlTimeoutException]. [start]'s own 30s wait for the
  /// `{port, controlToken}` boot line is separate: that is process startup,
  /// this is steady-state control-plane traffic against an already-running
  /// fixture, which every one of its handlers answers from memory.
  final Duration timeout;

  FixtureServerHandle._({
    required this.process,
    required this.port,
    required this.controlToken,
    this.timeout = const Duration(seconds: 10),
  });

  /// Test seam only — builds a handle against a server the test already
  /// controls directly (e.g. a bare `HttpServer` that never answers),
  /// bypassing [start]'s real `bin/serve.dart` subprocess spawn. [process]
  /// still has to be a real process because [stop] uses it; the test is
  /// free to hand it something unrelated to what [port]/[controlToken]
  /// point at, since this seam exists to exercise `_controlGet`/
  /// `_controlPost`'s timeout, not process lifecycle.
  factory FixtureServerHandle.debugForTesting({
    required Process process,
    required int port,
    required String controlToken,
    Duration timeout = const Duration(seconds: 10),
  }) => FixtureServerHandle._(process: process, port: port, controlToken: controlToken, timeout: timeout);

  String get baseUrl => 'http://127.0.0.1:$port';

  /// Starts `bin/serve.dart`, killing it on any failure before a usable
  /// handle exists — a timeout waiting for the boot line, a stdout that
  /// closes before printing one, or a boot line that fails to parse all
  /// leave a live child process behind otherwise, with nothing left able to
  /// stop it: [stop] can only ever be called on the handle this method never
  /// got to return.
  static Future<FixtureServerHandle> start({required Directory fixtureServerPackageDir}) async {
    final process = await Process.start('dart', [
      'run',
      'bin/serve.dart',
    ], workingDirectory: fixtureServerPackageDir.path);

    Future<void> killOrphan() async {
      process.kill(ProcessSignal.sigkill);
      // Reap it rather than fire-and-forget: an unawaited kill can leave a
      // zombie around just long enough to confuse the next `ps`/`lsof` a
      // developer runs while chasing an unrelated failure.
      await process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
    }

    try {
      final firstLine = await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () =>
                throw StateError('fixture server did not print its {port, controlToken} line within 30s'),
          );
      final decoded = jsonDecode(firstLine) as Map<String, Object?>;
      final port = decoded['port'];
      final controlToken = decoded['controlToken'];
      if (port is! int || controlToken is! String) {
        throw StateError('fixture server boot line is missing "port"/"controlToken": $firstLine');
      }
      return FixtureServerHandle._(process: process, port: port, controlToken: controlToken);
    } catch (e) {
      await killOrphan();
      rethrow;
    }
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

  /// Races [body] against [timeout], throwing [FixtureControlTimeoutException]
  /// naming [path] on expiry — the single deadline every `_controlGet`/
  /// `_controlPost` call shares, covering connect, response headers, and
  /// reading the whole response body as one bounded operation.
  Future<T> _withTimeout<T>(String path, Future<T> body) => body.timeout(
    timeout,
    onTimeout: () => throw FixtureControlTimeoutException(path: path, timeout: timeout),
  );

  Future<Map<String, Object?>> _controlGet(String path) async {
    final client = HttpClient();
    try {
      return await _withTimeout(path, () async {
        final request = await client.getUrl(Uri.parse('$baseUrl$path'));
        _controlHeaders.forEach(request.headers.set);
        final response = await request.close();
        final responseBody = await response.transform(utf8.decoder).join();
        return jsonDecode(responseBody) as Map<String, Object?>;
      }());
    } finally {
      // force: true so a connection stuck mid-request (the exact case a
      // timeout above just fired for) does not keep the client open waiting
      // for it to finish gracefully.
      client.close(force: true);
    }
  }

  Future<Map<String, Object?>> _controlPost(String path, Map<String, Object?> body) async {
    final client = HttpClient();
    try {
      return await _withTimeout(path, () async {
        final request = await client.postUrl(Uri.parse('$baseUrl$path'));
        _controlHeaders.forEach(request.headers.set);
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
        final response = await request.close();
        final responseBody = await response.transform(utf8.decoder).join();
        return jsonDecode(responseBody) as Map<String, Object?>;
      }());
    } finally {
      client.close(force: true);
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
