import 'dart:convert';
import 'dart:io';

import 'package:pleya_verify_runner/src/fixture/fixture_server_handle.dart';
import 'package:test/test.dart';

void main() {
  for (final bodyStarted in [false, true]) {
    test('timeout identifies stalled ${bodyStarted ? 'response body' : 'response headers'} without secrets', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        if (bodyStarted) {
          request.response.contentLength = 100;
          request.response.write('{"ok":');
          await request.response.flush();
        }
      });
      final process = await Process.start(Platform.resolvedExecutable, ['--version']);
      final handle = FixtureServerHandle.debugForTesting(
        process: process,
        port: server.port,
        controlToken: 'private-control-value',
        timeout: const Duration(milliseconds: 300),
      );
      final watch = Stopwatch()..start();
      await expectLater(
        handle.mutate('echo', {'password': 'private-body-value'}),
        throwsA(isA<FixtureControlTimeoutException>()),
      );
      expect(watch.elapsedMilliseconds, lessThan(2000));
      final events = handle.diagnostics.where((e) => e['component'] == 'fixture-client').toList();
      expect(
        events.map((e) => e['stage']),
        containsAllInOrder(['connecting', 'waiting_headers', if (bodyStarted) 'reading_body', 'timeout']),
      );
      expect(events.last['pending_stage'], bodyStarted ? 'reading_body' : 'waiting_headers');
      expect(events.last['request_elapsed_ms'], greaterThanOrEqualTo(250));
      final encoded = jsonEncode(events);
      expect(encoded, isNot(contains('private-control-value')));
      expect(encoded, isNot(contains('private-body-value')));
      await handle.stop();
    });
  }

  test('real fixture emits seed receipt and completion milestones and bounded exit evidence', () async {
    final handle = await FixtureServerHandle.start(fixtureServerPackageDir: Directory('../fixture_server'));
    try {
      await handle.seed('catalog.mixed.v1');
    } finally {
      await handle.stop();
    }
    final events = handle.diagnostics;
    final server = events.where((e) => e['component'] == 'fixture-server').toList();
    expect(
      server.map((e) => e['stage']),
      containsAllInOrder(['seed_received', 'seed_body_read', 'seed_applied', 'seed_response_closed']),
    );
    expect(server.every((e) => e['child_elapsed_ms'] is int && e['observed_at_utc'] is String), isTrue);
    expect(events.any((e) => e['stage'] == 'process_exit' && e['exit_code'] == 0), isTrue);
    expect(jsonEncode(events), isNot(contains(handle.controlToken)));
  });

  test('stderr floods are drained and discarded without leaking payloads or unbounded evidence', () async {
    final dir = Directory.systemTemp.createTempSync('verify-diagnostic-child-');
    addTearDown(() => dir.deleteSync(recursive: true));
    Directory('${dir.path}/bin').createSync();
    File(
      '${dir.path}/pubspec.yaml',
    ).writeAsStringSync('name: diagnostic_child\nenvironment:\n  sdk: ">=3.12.0 <4.0.0"\n');
    File('${dir.path}/bin/serve.dart').writeAsStringSync(r'''import 'dart:io';
void main() async {
  print('{"port":9,"controlToken":"private-boot-value"}');
  stderr.writeln('private-stderr-value' * 10000);
  for (var i=0; i<200; i++) {
    stderr.writeln('{"verify_fixture":"seed","stage":"seed_received","elapsed_ms":0,"password":"private-body-value"}');
  }
  await stderr.flush();
  exit(7);
}
''');
    final handle = await FixtureServerHandle.start(fixtureServerPackageDir: dir);
    await handle.stop();
    final events = handle.diagnostics;
    expect(events, isNotEmpty);
    expect(events.length, lessThanOrEqualTo(128));
    expect(events.any((e) => e['stage'] == 'process_exit' && e['exit_code'] == 7), isTrue);
    for (final secret in ['private-boot-value', 'private-stderr-value', 'private-body-value']) {
      expect(jsonEncode(events), isNot(contains(secret)));
    }
  });

  test('stop retains bounded kill and exit evidence when child ignores stdin', () async {
    final dir = Directory.systemTemp.createTempSync('verify-diagnostic-hang-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/hang.dart')
      ..writeAsStringSync("import 'dart:io'; void main() { sleep(const Duration(seconds:30)); }");
    final child = await Process.start(Platform.resolvedExecutable, [file.path]);
    final handle = FixtureServerHandle.debugForTesting(process: child, port: 9, controlToken: 'unused');
    final watch = Stopwatch()..start();
    await handle.stop();
    expect(watch.elapsedMilliseconds, lessThan(8000));
    final events = handle.diagnostics;
    expect(events.any((e) => e['stage'] == 'stop_kill'), isTrue);
    expect(events.any((e) => e['stage'] == 'process_exit'), isTrue);
  }, timeout: const Timeout(Duration(seconds: 15)));
}
