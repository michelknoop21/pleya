import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/services/memory/memory_service.dart';

import 'memory_test_support.dart';

void main() {
  late AppDatabase db;
  late TickingClock clock;
  late MemoryService memory;

  setUp(() async {
    await resetMemoryPrefs();
    db = memoryTestDatabase();
    clock = TickingClock();
    memory = MemoryService(database: db, profileId: 'profile-a', now: clock.call);
  });

  tearDown(() => db.close());

  Future<String> hash([String locale = 'nl']) => memory.takenHash(locale: locale);

  Future<MemoryResult> save(
    MemoryOverviewStatus status, {
    String body = '{"overview":"tekst"}',
    String locale = 'nl',
  }) async => memory.saveOverview(factsHash: await hash(locale), locale: locale, status: status, body: body);

  group('facts hash', () {
    test('changes on add, update and delete', () async {
      final seen = <String>{await hash()};

      final added = await memory.remember('Houdt van westerns');
      expect(seen.add(await hash()), isTrue, reason: 'add');

      await memory.update(added.fact!.id, value: 'Houdt van musicals');
      expect(seen.add(await hash()), isTrue, reason: 'update');

      await memory.remember('Kijkt op vrijdag');
      expect(seen.add(await hash()), isTrue, reason: 'second add');

      await memory.delete(added.fact!.id);
      expect(seen.add(await hash()), isTrue, reason: 'delete');
    });

    test('a category change moves it even inside the same clock tick', () async {
      final added = await memory.remember('Houdt van westerns');
      final before = await hash();
      clock.frozen = true;

      await memory.update(added.fact!.id, category: MemoryCategory.other);

      expect(await hash(), isNot(before));
    });

    test('does not change on reading, on a refused write or on an update that changes nothing', () async {
      final added = await memory.remember('Houdt van westerns');
      final before = await hash();

      await memory.list();
      await memory.list(query: 'westerns', category: MemoryCategory.preference);
      await memory.relevantFor('Welke westerns zijn er?');
      await memory.resolve(added.fact!.ref);
      await memory.overview();
      await memory.overviewIsStale(locale: 'nl');
      await memory.remember('Houdt van westerns');
      await memory.remember('Onze dochter is 8');
      await memory.update(added.fact!.id, value: 'Houdt van westerns', category: MemoryCategory.preference);
      await memory.update('no-such-id', value: 'iets anders');
      await memory.setEnabled(false);
      await memory.setEnabled(true);

      expect(await hash(), before);
      expect((await memory.list()).single.source, MemorySource.userExplicit);
    });

    test('covers the locale', () async {
      await memory.remember('Houdt van westerns');
      expect(await hash('nl'), isNot(await hash('en')));
    });
  });

  group('stored overview', () {
    test('none stored is stale, a saved one is shown until the facts change and is dropped then', () async {
      await memory.remember('Houdt van westerns');
      expect(await memory.overview(), isNull);
      expect(await memory.overviewIsStale(locale: 'nl'), isTrue);

      await save(MemoryOverviewStatus.ok);

      final stored = (await memory.overview())!;
      expect(stored.status, MemoryOverviewStatus.ok);
      expect(stored.body, '{"overview":"tekst"}');
      expect(stored.locale, 'nl');
      expect(stored.factsHash, await hash());
      expect(await memory.overviewIsStale(locale: 'nl'), isFalse);

      await memory.remember('Kijkt op vrijdag');
      expect(await memory.overviewIsStale(locale: 'nl'), isTrue);
      expect(await memory.overview(), isNull, reason: 'dropped with the change, not left behind');
    });

    test('every change to the facts drops the stored text in the database; a refused or empty one keeps it', () async {
      Future<List<String>> bodies() async => [
        for (final row in await db.select(db.assistantMemoryOverviews).get()) row.body,
      ];
      final first = (await memory.remember('Houdt niet van horror')).fact!;
      final second = (await memory.remember('Kijkt op vrijdag')).fact!;

      await save(MemoryOverviewStatus.ok, body: '{"overview":"Je slaat horror over."}');
      await memory.remember('Houdt niet van horror');
      await memory.update(first.id, value: 'Houdt niet van horror');
      await memory.update('no-such-id', value: 'iets');
      await memory.delete('no-such-id');
      await memory.resolve(first.ref);
      expect(await bodies(), ['{"overview":"Je slaat horror over."}'], reason: 'nothing changed');

      await memory.remember('Houdt van westerns');
      expect(await bodies(), isEmpty, reason: 'add');

      await save(MemoryOverviewStatus.ok, body: '{"overview":"Je slaat horror over."}');
      await memory.update(first.id, value: 'Houdt van horror');
      expect(await bodies(), isEmpty, reason: 'update of the text');

      await save(MemoryOverviewStatus.ok, body: '{"overview":"Je houdt van horror."}');
      await memory.update(second.id, category: MemoryCategory.habit);
      expect(await bodies(), isEmpty, reason: 'update of the category');

      await save(MemoryOverviewStatus.ok, body: '{"overview":"Je houdt van horror."}');
      await memory.delete(first.id);
      expect(await bodies(), isEmpty, reason: 'delete');
    });

    test('the last fact deleted leaves no body in the database', () async {
      final only = (await memory.remember('Houdt niet van horror')).fact!;
      await save(MemoryOverviewStatus.ok, body: '{"overview":"Je slaat horror over."}');

      await memory.delete(only.id);

      expect(await db.select(db.assistantMemoryOverviews).get(), isEmpty);
      expect(await memory.overview(), isNull);
    });

    test('a change in one profile keeps the overview of another', () async {
      final other = MemoryService(database: db, profileId: 'profile-b', now: clock.call);
      await other.remember('Houdt van musicals');
      await other.saveOverview(
        factsHash: await other.takenHash(),
        locale: 'nl',
        status: MemoryOverviewStatus.ok,
        body: '{"overview":"b"}',
      );

      await memory.remember('Houdt van westerns');

      expect((await other.overview())!.body, '{"overview":"b"}');
    });

    test('another app language makes it stale', () async {
      await memory.remember('Houdt van westerns');
      await save(MemoryOverviewStatus.ok);
      expect(await memory.overviewIsStale(locale: 'en'), isTrue);
    });

    test('asking whether it is stale does not open the way to a save', () async {
      await memory.remember('Houdt van westerns');
      final taken = await hash();
      final other = MemoryService(database: db, profileId: 'profile-a', now: clock.call);

      expect(await other.overviewIsStale(locale: 'nl'), isTrue);
      final saved = await other.saveOverview(
        factsHash: taken,
        locale: 'nl',
        status: MemoryOverviewStatus.ok,
        body: '{}',
      );

      expect(saved.code, MemoryCode.staleHash);
      expect(await memory.overview(), isNull);
    });

    test('a failed attempt stays while the hash is the same and lapses on a changed fact', () async {
      final added = await memory.remember('Houdt van westerns');
      await save(MemoryOverviewStatus.failed, body: 'ongeldige uitvoer');

      final failed = (await memory.overview())!;
      expect(failed.status, MemoryOverviewStatus.failed);
      expect(failed.body, isEmpty, reason: 'invalid output is not kept');
      expect(await memory.overviewIsStale(locale: 'nl'), isFalse);

      await memory.list();
      await memory.relevantFor('westerns');
      expect(await memory.overviewIsStale(locale: 'nl'), isFalse);
      expect((await memory.overview())!.status, MemoryOverviewStatus.failed);

      await memory.update(added.fact!.id, value: 'Houdt van musicals');
      expect(await memory.overviewIsStale(locale: 'nl'), isTrue);
    });

    test('saving again replaces the one row of the profile', () async {
      await memory.remember('Houdt van westerns');
      await save(MemoryOverviewStatus.failed);
      await save(MemoryOverviewStatus.ok, body: '{"overview":"tweede"}');

      expect(await db.select(db.assistantMemoryOverviews).get(), hasLength(1));
      expect((await memory.overview())!.body, '{"overview":"tweede"}');
    });

    test('a body that is not a JSON object, or is too large, is refused and nothing is stored', () async {
      await memory.remember('Houdt van westerns');
      for (final body in ['', 'geen json', '{"open":', '[1,2]', '{"t":"${'a' * kMemoryOverviewMaxBytes}"}']) {
        expect((await save(MemoryOverviewStatus.ok, body: body)).code, MemoryCode.invalidOverview);
      }
      expect(await memory.overview(), isNull);

      expect((await save(MemoryOverviewStatus.ok)).code, MemoryCode.ok);
      expect((await save(MemoryOverviewStatus.ok, body: 'kapot')).code, MemoryCode.invalidOverview);
      expect((await memory.overview())!.body, '{"overview":"tekst"}', reason: 'the stored overview is left alone');
    });

    test('clearAll drops the facts and the overview', () async {
      await memory.remember('Houdt van westerns');
      await save(MemoryOverviewStatus.ok);

      await memory.clearAll();

      expect(await memory.list(), isEmpty);
      expect(await memory.overview(), isNull);
      expect(await db.select(db.assistantMemoryOverviews).get(), isEmpty);
    });

    test('switching the memory off and on keeps the overview and does not make it stale', () async {
      await memory.remember('Houdt van westerns');
      await save(MemoryOverviewStatus.ok);

      await memory.setEnabled(false);
      expect((await memory.overview())!.body, '{"overview":"tekst"}');
      expect(await memory.overviewIsStale(locale: 'nl'), isFalse);

      await memory.setEnabled(true);
      expect((await memory.overview())!.body, '{"overview":"tekst"}');
      expect(await memory.overviewIsStale(locale: 'nl'), isFalse);
    });
  });

  group('relevantFor', () {
    int cost(Iterable<MemoryFact> facts) =>
        facts.fold(0, (sum, f) => sum + f.ref.length + 1 + f.value.runes.length + 1);

    test('picks the facts that share a word, best match first', () async {
      await memory.remember('Houdt van westerns');
      await memory.remember('Kijkt op vrijdag met het gezin');
      await memory.remember('Vindt oude westerns met John Wayne mooi');

      final chosen = await memory.relevantFor('Heb je westerns met John Wayne?');

      expect([for (final f in chosen) f.value], ['Vindt oude westerns met John Wayne mooi', 'Houdt van westerns']);
      expect(chosen.first.ref, hasLength(8));
    });

    test('no shared word, or only function words, gives nothing', () async {
      await memory.remember('Houdt van westerns');
      expect(await memory.relevantFor('Wat is er nieuw?'), isEmpty);
      expect(await memory.relevantFor('van de het'), isEmpty);
      expect(await memory.relevantFor(''), isEmpty);
    });

    test('at most 8 facts', () async {
      for (var i = 0; i < 12; i++) {
        await memory.remember('Horror nummer $i');
      }
      final chosen = await memory.relevantFor('Welke horror past bij mij?');
      expect(chosen, hasLength(kMemoryRelevantMaxFacts));
      // Equal scores: the newest facts win.
      expect(chosen.first.value, 'Horror nummer 11');
    });

    test('at most 600 characters, references included', () async {
      for (var i = 0; i < 8; i++) {
        await memory.remember('thriller $i ${'x' * 180}');
      }
      await memory.remember('thriller kort');

      final chosen = await memory.relevantFor('Een thriller graag');

      expect(cost(chosen), lessThanOrEqualTo(kMemoryRelevantMaxChars));
      expect(chosen.length, lessThan(kMemoryRelevantMaxFacts));
      expect(chosen.length, greaterThanOrEqualTo(3));
      // A long fact that no longer fits is skipped, a short one still goes in.
      expect([for (final f in chosen) f.value], contains('thriller kort'));
    });

    test('gives nothing while the memory is off', () async {
      await memory.remember('Houdt van westerns');
      await memory.setEnabled(false);
      expect(await memory.relevantFor('Welke westerns zijn er?'), isEmpty);
      await memory.setEnabled(true);
      expect(await memory.relevantFor('Welke westerns zijn er?'), hasLength(1));
    });
  });
}
