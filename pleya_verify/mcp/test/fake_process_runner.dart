import 'package:pleya_verify_mcp/src/process_runner.dart';

/// A scripted [ProcessRunner] for wrapper-unit tests: no real `dart`
/// subprocess, no scenario execution, no simulator/build dependency. Each
/// test supplies [respond], deciding the result from the argv it receives:
/// exactly what [VerifyCli] would have passed to the real CLI.
class FakeProcessRunner implements ProcessRunner {
  final List<List<String>> calls = [];
  final ProcessRunResult Function(List<String> args) respond;

  FakeProcessRunner(this.respond);

  @override
  Future<ProcessRunResult> run(List<String> args, {required String workingDirectory}) async {
    calls.add(args);
    return respond(args);
  }
}
