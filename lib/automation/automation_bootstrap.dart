import 'automation_server.dart';
import 'pleya_verify.dart';

/// Single always-reachable entrypoint for Pleya Verify. `main.dart` calls
/// [start] unconditionally on every build — the `if (!kPleyaVerify) return;`
/// guard is what keeps a normal build's behavior unchanged, while making the
/// whole `lib/automation/` tree reachable from `main()` in source, which is
/// what satisfies the `check-unused-code`/`check-unused-files` CI gates.
/// Real release builds still tree-shake the guarded branch out entirely
/// (verified in A.4b).
class AutomationBootstrap {
  AutomationBootstrap._();

  static AutomationServer? _instance;

  static Future<void> start() async {
    if (!kPleyaVerify) return;
    final server = AutomationServer();
    _instance = server;
    await server.start();
  }

  /// Test seam, same shape as `SelectTraceRecorder.debugSetInstance`.
  static void debugSetInstance(AutomationServer? instance) {
    _instance = instance;
  }

  static AutomationServer? get instanceOrNull => _instance;
}
