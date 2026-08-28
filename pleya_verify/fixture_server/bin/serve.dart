import 'dart:convert';
import 'dart:io';

import 'package:pleya_verify_fixture_server/http_adapter.dart';
import 'package:pleya_verify_fixture_server/pleya_fake_server.dart';

/// Standalone fixture-server process. Usage: `dart run bin/serve.dart [--port N]`
/// (or the `dart compile exe`d binary directly — see pleya_verify/README.md).
///
/// Prints exactly one JSON line to stdout once bound:
/// `{"port": N, "controlToken": "..."}`. Lifecycle is tied to stdin: the
/// runner that spawned this process closes stdin to shut it down cleanly
/// (SIGINT/SIGTERM also work, for a human running it by hand).
Future<void> main(List<String> args) async {
  var port = 0;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--port' && i + 1 < args.length) {
      port = int.tryParse(args[i + 1]) ?? 0;
    }
  }

  final controlToken = FixtureHttpServer.generateControlToken();
  final adapter = FixtureHttpServer(server: PleyaFakeServer(), controlToken: controlToken);
  await adapter.start(port: port);

  stdout.writeln(jsonEncode({'port': adapter.port, 'controlToken': controlToken}));

  var stopping = false;
  Future<void> stop() async {
    if (stopping) return;
    stopping = true;
    await adapter.stop();
    exit(0);
  }

  stdin.listen((_) {}, onDone: stop, onError: (_) => stop());
  ProcessSignal.sigint.watch().listen((_) => stop());
  ProcessSignal.sigterm.watch().listen((_) => stop());
}
