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
}
