import 'dart:convert';
import 'dart:io';

import 'package:pleya_verify_runner/src/driver/instance_discovery.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pleya-verify-discovery-test');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File writeInstance(Map<String, Object?> json, {DateTime? modified}) {
    final file = File('${tempDir.path}/instance.json')..writeAsStringSync(jsonEncode(json));
    if (modified != null) file.setLastModifiedSync(modified);
    return file;
  }

  group('awaitInstance', () {
    test('reads the port the app announced, not the base port', () async {
      final file = writeInstance({'port': 47321, 'protocolVersion': 1, 'pid': 999});

      final instance = await awaitInstance(file: file, notBefore: DateTime.now().subtract(const Duration(minutes: 1)));

      expect(instance.port, 47321);
      expect(instance.pid, 999);
      expect(instance.source, file.path);
    });

    test('rejects an announcement older than this launch instead of using it', () async {
      // The stale-file case: clearInstanceFile could not remove it and the
      // app never rewrote it. Silently trusting it is how a run drives a
      // leftover instance and reports PASS on the wrong app.
      final file = writeInstance(
        {'port': 47317, 'protocolVersion': 1},
        modified: DateTime.now().subtract(const Duration(hours: 2)),
      );

      await expectLater(
        awaitInstance(file: file, notBefore: DateTime.now(), timeout: const Duration(milliseconds: 400)),
        throwsA(
          isA<InstanceDiscoveryException>().having(
            (e) => e.message,
            'message',
            allOf(contains('from before this launch'), contains('PLEYA_VERIFY=true')),
          ),
        ),
      );
    });

    test('picks up an announcement that appears after the wait starts', () async {
      final file = File('${tempDir.path}/instance.json');
      final notBefore = DateTime.now().subtract(const Duration(seconds: 1));

      final pending = awaitInstance(file: file, notBefore: notBefore, timeout: const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      file.writeAsStringSync(jsonEncode({'port': 47318, 'protocolVersion': 1}));

      expect((await pending).port, 47318);
    });

    test('a missing file times out with the path in the message — never a base-port fallback', () async {
      final file = File('${tempDir.path}/nope.json');

      await expectLater(
        awaitInstance(file: file, notBefore: DateTime.now(), timeout: const Duration(milliseconds: 300)),
        throwsA(isA<InstanceDiscoveryException>().having((e) => e.message, 'message', contains(file.path))),
      );
    });
  });

  group('clearInstanceFile', () {
    test('removes an existing announcement and tolerates a missing one', () {
      final file = writeInstance({'port': 47317, 'protocolVersion': 1});
      clearInstanceFile(file);
      expect(file.existsSync(), isFalse);

      clearInstanceFile(File('${tempDir.path}/never-existed.json'));
    });
  });

  group('assertHealthIdentity', () {
    const instance = VerifyInstance(port: 47318, protocolVersion: 1, source: 'test');
    final launchedAt = DateTime.utc(2026, 8, 29, 12);

    test('accepts an app on the announced port that booted for this launch', () {
      expect(
        () => assertHealthIdentity(
          {'port': 47318, 'bootedAt': launchedAt.add(const Duration(seconds: 2)).toIso8601String()},
          instance: instance,
          notBefore: launchedAt,
        ),
        returnsNormally,
      );
    });

    test('refuses an app answering on a different port', () {
      expect(
        () => assertHealthIdentity(
          {'port': 47317, 'bootedAt': launchedAt.add(const Duration(seconds: 2)).toIso8601String()},
          instance: instance,
          notBefore: launchedAt,
        ),
        throwsA(
          isA<InstanceDiscoveryException>().having((e) => e.message, 'message', contains('refusing to drive')),
        ),
      );
    });

    test('refuses an app that booted before this launch — a leftover from an earlier run', () {
      expect(
        () => assertHealthIdentity(
          {'port': 47318, 'bootedAt': launchedAt.subtract(const Duration(hours: 1)).toIso8601String()},
          instance: instance,
          notBefore: launchedAt,
        ),
        throwsA(isA<InstanceDiscoveryException>().having((e) => e.message, 'message', contains('leftover instance'))),
      );
    });

    test('refuses a health body with no usable bootedAt rather than assuming the best', () {
      expect(
        () => assertHealthIdentity({'port': 47318}, instance: instance, notBefore: launchedAt),
        throwsA(isA<InstanceDiscoveryException>().having((e) => e.message, 'message', contains('bootedAt'))),
      );
    });
  });

  group('parseListeningPort', () {
    test('takes the last boot line, so a multi-launch driver log yields the current instance', () {
      final instance = parseListeningPort([
        'launching /path/Pleya.app',
        '[PleyaVerify] listening on 127.0.0.1:47317',
        'terminating pid 1',
        '[PleyaVerify] listening on 127.0.0.1:47320',
      ]);

      expect(instance?.port, 47320);
      expect(instance?.source, 'driver log');
    });

    test('returns null when the app never logged a boot line', () {
      expect(parseListeningPort(['flutter build macos', 'Built build/macos/…']), isNull);
    });
  });
}
