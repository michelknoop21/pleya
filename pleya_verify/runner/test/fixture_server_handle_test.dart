import 'dart:io';

import 'package:pleya_verify_runner/src/fixture/fixture_server_handle.dart';
import 'package:test/test.dart';

/// Exercises the handle against a **real** `bin/serve.dart` process, because
/// the thing worth proving is the wire contract between the two packages —
/// a mock of the fixture server would only prove this file agrees with
/// itself.
///
/// This is the mutation path `media-detail.episode-refresh` depends on:
/// seed a show with ten episodes, look the season's id up by its readable
/// slug, add an eleventh, and see the count grow. Getting that wrong is a
/// scenario that fails twenty minutes into a tvOS run for a reason that has
/// nothing to do with the app.
void main() {
  late FixtureServerHandle fixture;

  final packageDir = Directory('${Directory.current.path}/../fixture_server');

  setUp(() async {
    fixture = await FixtureServerHandle.start(fixtureServerPackageDir: packageDir);
  });

  tearDown(() async {
    await fixture.stop();
  });

  test('a seeded fixture publishes the ids it minted, keyed by readable slug', () async {
    await fixture.seed('catalog.shows.v1');

    final ids = await fixture.seededIds();

    expect(ids.keys, containsAll(['show/testserie', 'season/testserie-s01', 'library/shows']));
    expect(ids['season/testserie-s01'], isNotEmpty);
    // A truncated sha256 — stable, and exactly why a scenario cannot write
    // it down and needs this map.
    expect(ids['season/testserie-s01'], matches(RegExp(r'^[0-9a-f]{16}$')));
  });

  test('seededIds is empty before anything is seeded', () async {
    expect(await fixture.seededIds(), isEmpty);
  });

  test('add_episode against the seeded season id grows the catalog', () async {
    await fixture.seed('catalog.shows.v1');
    final before = (await fixture.verifyState())['itemCount']! as int;
    final seasonId = (await fixture.seededIds())['season/testserie-s01']!;

    final result = await fixture.mutate('add_episode', {'parent_id': seasonId, 'title': 'S01E11'});

    expect(result['ok'], isTrue);
    expect(result['id'], isNotEmpty);
    expect((await fixture.verifyState())['itemCount'], before + 1);
  });

  test('a mutation the server rejects throws with the server response in it', () async {
    await fixture.seed('catalog.shows.v1');

    await expectLater(
      fixture.mutate('add_episode', {'parent_id': 'not-a-real-id'}),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('add_episode'), contains('unknown parent_id')),
        ),
      ),
    );
  });

  test('re-seeding replaces the catalog rather than stacking a second copy', () async {
    await fixture.seed('catalog.shows.v1');
    final first = (await fixture.verifyState())['itemCount']! as int;

    await fixture.seed('catalog.shows.v1');

    expect((await fixture.verifyState())['itemCount'], first);
  });

  group('control-plane calls are bounded', () {
    late HttpServer deadServer;
    late Process dummyProcess;
    late FixtureServerHandle handleAgainstDeadServer;

    setUp(() async {
      // A real socket that accepts every connection and then never answers
      // — the "endpoint/server die accepteert maar niet antwoordt" case:
      // proves _controlGet/_controlPost fail fast rather than hang forever,
      // against a real hung request rather than a mocked-out Future.
      deadServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      deadServer.listen((request) {
        // Deliberately never touches request.response — the connection
        // just sits open past whatever deadline the test below sets.
      });
      dummyProcess = await Process.start(Platform.resolvedExecutable, const ['--version']);
      handleAgainstDeadServer = FixtureServerHandle.debugForTesting(
        process: dummyProcess,
        port: deadServer.port,
        controlToken: 'irrelevant-for-this-test',
        timeout: const Duration(milliseconds: 300),
      );
    });

    tearDown(() async {
      await deadServer.close(force: true);
    });

    test('a GET control call that never gets a response times out', () async {
      await expectLater(
        handleAgainstDeadServer.verifyState(),
        throwsA(
          isA<FixtureControlTimeoutException>().having((e) => e.path, 'path', '/__verify/state'),
        ),
      );
    });

    test('a POST control call that never gets a response times out', () async {
      await expectLater(
        handleAgainstDeadServer.seed('catalog.shows.v1'),
        throwsA(isA<FixtureControlTimeoutException>().having((e) => e.path, 'path', '/__verify/seed')),
      );
    });
  });

  test('start() kills the child process on a malformed boot line, rather than leaving it running', () async {
    // A package dir with a `bin/serve.dart` that immediately prints
    // something that is not the {port, controlToken} JSON start() expects,
    // then hangs — exercises the same catch-and-kill path start()'s doc
    // covers for every startup failure (timeout, early stdout close,
    // malformed JSON, missing fields), without paying for the real 30s
    // boot-line timeout to prove it.
    final packageDir = Directory.systemTemp.createTempSync('pleya-verify-fixture-start-orphan-test');
    addTearDown(() {
      if (packageDir.existsSync()) packageDir.deleteSync(recursive: true);
    });
    File(
      '${packageDir.path}/pubspec.yaml',
    ).writeAsStringSync('name: fake_fixture_server\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n');
    Directory('${packageDir.path}/bin').createSync();
    File('${packageDir.path}/bin/serve.dart').writeAsStringSync('''
import 'dart:io';
void main() {
  // A pid file so the test can watch it, then a line start() cannot
  // decode as JSON, then a hang — proves the process is actually killed
  // rather than merely that start() eventually throws.
  File('pid').writeAsStringSync('\$pid');
  print('not valid json');
  sleep(const Duration(hours: 1));
}
''');

    await expectLater(FixtureServerHandle.start(fixtureServerPackageDir: packageDir), throwsA(anything));

    final pidFile = File('${packageDir.path}/pid');
    expect(pidFile.existsSync(), isTrue, reason: 'the child should have started and announced its own pid');
    final pid = pidFile.readAsStringSync().trim();
    final aliveCheck = await Process.run('kill', ['-0', pid]);
    expect(aliveCheck.exitCode, isNot(0), reason: 'pid $pid should not still be running after start() threw');
  }, timeout: const Timeout(Duration(seconds: 30)));
}
