import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../transport/verify_client.dart';
import 'verification_driver.dart';

/// Drives a local macOS build of Pleya.
///
/// **Isolation, not sandboxing.** A plain `flutter build macos` binary
/// shares the developer's real `~/Library/Application Support/
/// nl.michelknoop.pleya` — confirmed by hand: even overriding `$HOME` for
/// the child process did not redirect `path_provider`'s directory
/// resolution away from it, and a manual launch made real calls to the
/// developer's real Plex/Jellyfin servers within seconds. [build] instead
/// copies the compiled `.app`, rewrites `CFBundleIdentifier` to
/// [verifyBundleId] (default `nl.michelknoop.pleya.verify`, never the real
/// `nl.michelknoop.pleya`), and re-signs ad hoc — proven by hand to give
/// the copy its own, empty `~/Library/Application Support/<verifyBundleId>`
/// with zero real network calls in its log. The source Xcode project is
/// never touched; this all happens on a build-output copy.
class MacosDriver implements VerificationDriver {
  final Directory repoRoot;
  final String verifyBundleId;
  final int port;
  final void Function(String line)? onDriverLog;

  Process? _process;
  final List<String> _driverLog = [];
  VerifyClient? _client;

  MacosDriver({
    required this.repoRoot,
    this.verifyBundleId = 'nl.michelknoop.pleya.verify',
    this.port = 47317,
    this.onDriverLog,
  });

  @override
  String get target => 'macos';

  @override
  VerifyClient? get client => _client;

  @override
  String get inputRoute => 'transport';

  Directory get _sourceAppDir => Directory('${repoRoot.path}/build/macos/Build/Products/Debug/Pleya.app');

  /// The isolated, re-signed copy this driver actually launches — kept
  /// outside any per-run evidence bundle so repeated runs reuse one build
  /// instead of copying+re-signing a multi-hundred-MB `.app` every time.
  Directory get isolatedAppDir => Directory('${repoRoot.path}/.build/pleya-verify/macos-app/Pleya.app');

  Directory get _isolatedAppSupportDir => Directory('$_homeLibrary/Application Support/$verifyBundleId');
  Directory get _isolatedCachesDir => Directory('$_homeLibrary/Caches/$verifyBundleId');
  File get _isolatedPrefsFile => File('$_homeLibrary/Preferences/$verifyBundleId.plist');

  String get _homeLibrary => '${Platform.environment['HOME']}/Library';

  void _log(String line) {
    _driverLog.add(line);
    onDriverLog?.call(line);
  }

  @override
  List<String> get driverLog => List.unmodifiable(_driverLog);

  @override
  Future<DriverDoctorReport> doctor() async {
    final checks = <String, Object?>{};

    final flutterVersion = await _run('flutter', ['--version']);
    checks['flutter'] = flutterVersion.exitCode == 0;

    final xcodebuild = await _run('xcodebuild', ['-version']);
    checks['xcodebuild'] = xcodebuild.exitCode == 0;

    checks['sourceAppBuilt'] = _sourceAppDir.existsSync();
    checks['isolatedAppReady'] = isolatedAppDir.existsSync();

    final ready = checks.values.every((v) => v == true || v is! bool);
    return DriverDoctorReport(ready: ready, checks: checks);
  }

  @override
  Future<void> build() async {
    _log('flutter build macos --debug --dart-define=PLEYA_VERIFY=true');
    final gitCommit = await _gitCommit();
    final result = await _run('flutter', [
      'build',
      'macos',
      '--debug',
      '--dart-define=PLEYA_VERIFY=true',
      if (gitCommit != null) '--dart-define=GIT_COMMIT=$gitCommit',
    ], workingDirectory: repoRoot.path);
    _log(result.stdout.toString());
    if (result.exitCode != 0) {
      _log(result.stderr.toString());
      throw StateError('flutter build macos failed (exit ${result.exitCode})');
    }
    if (!_sourceAppDir.existsSync()) {
      throw StateError('flutter build macos reported success but ${_sourceAppDir.path} does not exist');
    }

    if (isolatedAppDir.existsSync()) {
      isolatedAppDir.deleteSync(recursive: true);
    }
    isolatedAppDir.parent.createSync(recursive: true);
    _log('copying ${_sourceAppDir.path} -> ${isolatedAppDir.path}');
    await _run('cp', ['-R', _sourceAppDir.path, isolatedAppDir.path]);

    final infoPlist = File('${isolatedAppDir.path}/Contents/Info.plist');
    await _run('plutil', ['-replace', 'CFBundleIdentifier', '-string', verifyBundleId, infoPlist.path]);

    _log('codesign --force --deep --sign - ${isolatedAppDir.path}');
    final sign = await _run('codesign', ['--force', '--deep', '--sign', '-', isolatedAppDir.path]);
    if (sign.exitCode != 0) {
      throw StateError('codesign failed on the isolated app copy (exit ${sign.exitCode}): ${sign.stderr}');
    }
  }

  @override
  Future<void> installFresh() async {
    for (final dir in [_isolatedAppSupportDir, _isolatedCachesDir]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
    if (_isolatedPrefsFile.existsSync()) _isolatedPrefsFile.deleteSync();
    _log('installFresh: cleared $verifyBundleId app state');
  }

  @override
  Future<void> launch({Duration timeout = const Duration(seconds: 20)}) async {
    final binary = File('${isolatedAppDir.path}/Contents/MacOS/Pleya');
    if (!binary.existsSync()) {
      throw StateError('${binary.path} does not exist — call build() first');
    }

    _log('launching ${binary.path}');
    final process = await Process.start(binary.path, const [], mode: ProcessStartMode.normal);
    _process = process;
    process.stdout.transform(const SystemEncoding().decoder).listen(_log);
    process.stderr.transform(const SystemEncoding().decoder).listen(_log);

    _client = VerifyClient(baseUri: Uri.parse('http://127.0.0.1:$port'));

    final deadline = DateTime.now().add(timeout);
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      try {
        await _client!.health();
        _log('health check succeeded');
        return;
      } catch (e) {
        lastError = e;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    throw StateError('app did not respond on /v1/health within $timeout (last error: $lastError)');
  }

  @override
  Future<void> terminate() async {
    final process = _process;
    if (process == null) return;
    _log('terminating pid ${process.pid}');
    process.kill(ProcessSignal.sigterm);
    final exited = await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return process.exitCode;
      },
    );
    _log('process exited with code $exited');
    _client?.close();
    _client = null;
    _process = null;
  }

  @override
  Future<Map<String, Object?>> uiTree() => _requireClient().uiTree();

  @override
  Future<Map<String, Object?>> focus() => _requireClient().focus();

  @override
  Future<List<Map<String, Object?>>> screensSnapshot() async {
    final result = await _requireClient().screens();
    return (result['screens'] as List).cast<Map<String, Object?>>();
  }

  @override
  Future<List<Map<String, Object?>>> eventsSince(int since) async {
    final result = await _requireClient().events(since: since);
    return (result['events'] as List).cast<Map<String, Object?>>();
  }

  @override
  Future<List<Map<String, Object?>>> focusLogSince(int since) async {
    final result = await _requireClient().focusLog(since: since);
    return (result['entries'] as List).cast<Map<String, Object?>>();
  }

  @override
  Future<List<Map<String, Object?>>> logsSince(int since) async {
    final result = await _requireClient().logs(since: since);
    return (result['entries'] as List).cast<Map<String, Object?>>();
  }

  @override
  Future<Uint8List> screenshot() async {
    final tempFile = File(
      '${Directory.systemTemp.path}/pleya-verify-macos-screenshot-${DateTime.now().microsecondsSinceEpoch}.png',
    );
    // The [C5] authoritative capture: the real macOS compositor, not
    // Flutter's own RepaintBoundary (`/v1/screenshot`, diagnostic-only).
    final result = await _run('screencapture', ['-x', tempFile.path]);
    if (result.exitCode != 0 || !tempFile.existsSync()) {
      throw StateError('screencapture failed (exit ${result.exitCode}): ${result.stderr}');
    }
    final bytes = tempFile.readAsBytesSync();
    tempFile.deleteSync();
    return bytes;
  }

  @override
  Future<void> press(String key) async {
    await _requireClient().inputKey(key);
  }

  @override
  Future<void> typeText(String text) {
    throw UnsupportedError(
      'typeText: no /v1/input/text endpoint exists yet — not needed by any Fase 8-11 scenario so far',
    );
  }

  @override
  Future<void> tap(double x, double y) async {
    await _requireClient().inputPointer(x, y);
  }

  VerifyClient _requireClient() {
    final c = _client;
    if (c == null) throw StateError('driver not launched — call launch() first');
    return c;
  }

  Future<ProcessResult> _run(String executable, List<String> args, {String? workingDirectory}) =>
      Process.run(executable, args, workingDirectory: workingDirectory);

  Future<String?> _gitCommit() async {
    final result = await _run('git', ['rev-parse', 'HEAD'], workingDirectory: repoRoot.path);
    if (result.exitCode != 0) return null;
    return (result.stdout as String).trim();
  }
}
