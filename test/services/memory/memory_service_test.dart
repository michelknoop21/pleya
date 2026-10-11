import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/screens/profile/profile_delete_flow.dart';
import 'package:pleya/services/memory/memory_service.dart';
import 'package:pleya/services/preferences/preference_sync_policy.dart';
import 'package:pleya/services/storage_service.dart';

import 'memory_test_support.dart';

void main() {
  late AppDatabase db;
  late StorageService storage;
  late TickingClock clock;
  late MemoryService a;
  late MemoryService b;

  setUp(() async {
    storage = await resetMemoryPrefs();
    db = memoryTestDatabase();
    clock = TickingClock();
    a = MemoryService(database: db, profileId: 'profile-a', now: clock.call);
    b = MemoryService(database: db, profileId: 'profile-b', now: clock.call);
  });

  tearDown(() => db.close());

  group('add, update, delete', () {
    test('a fact round-trips with its category, source and reference', () async {
      final result = await a.add(
        value: '  Kijkt op vrijdag met het gezin ',
        category: MemoryCategory.habit,
        source: MemorySource.assistantConfirmed,
      );

      expect(result.code, MemoryCode.ok);
      final fact = (await a.list()).single;
      expect(fact.id, result.fact!.id);
      expect(fact.value, 'Kijkt op vrijdag met het gezin');
      expect(fact.category, MemoryCategory.habit);
      expect(fact.source, MemorySource.assistantConfirmed);
      expect(fact.ref, fact.id.substring(0, 8));
      expect(fact.createdAt, fact.updatedAt);
      expect(fact.createdAt.isUtc, isTrue);
    });

    test('the same sentence twice is one row, also under another category', () async {
      final first = await a.remember('Houdt niet van horror');
      final second = await a.remember('houdt NIET van horror!', category: MemoryCategory.dislike);

      expect(second.code, MemoryCode.exists);
      expect(second.fact!.id, first.fact!.id);
      expect(await db.select(db.assistantMemories).get(), hasLength(1));
      expect((await a.list()).single.category, MemoryCategory.preference);
    });

    test('the same sentence with an invisible character or another accent form is the same fact', () async {
      final first = await a.remember('Kijkt graag in Caf\u00E9 Noir');
      final zeroWidth = await a.remember('Kijkt gr\u200Baag in Caf\u00E9 Noir');
      final decomposed = await a.remember('Kijkt graag in Cafe\u0301 Noir');

      expect([zeroWidth.code, decomposed.code], [MemoryCode.exists, MemoryCode.exists]);
      expect(decomposed.fact!.id, first.fact!.id);
      expect(await a.values(), ['Kijkt graag in Caf\u00E9 Noir']);

      // The stored text keeps what was typed; only the key drops it.
      final stored = await b.remember('Hor\u200Bror\u00AD film');
      expect(stored.fact!.value, 'Hor\u200Bror\u00AD film');
      expect((await b.remember('Horror film')).code, MemoryCode.exists);

      // Accent-insensitive on purpose.
      await b.remember('Kijkt een film per week');
      expect((await b.remember('Kijkt \u00E9\u00E9n film per week')).code, MemoryCode.exists);
    });

    test('updating to a sentence another fact holds is refused as duplicate', () async {
      await a.remember('Houdt niet van horror');
      final other = await a.remember('Kijkt graag thrillers');

      final result = await a.update(other.fact!.id, value: 'Houdt niet van horror.');

      expect(result.code, MemoryCode.duplicate);
      expect(await a.values(), containsAll(['Houdt niet van horror', 'Kijkt graag thrillers']));
      expect((await a.list()).firstWhere((f) => f.id == other.fact!.id).source, MemorySource.userExplicit);
    });

    test('a manual update changes the text and marks the source', () async {
      final added = await a.remember('Kijkt op vrijdag');

      final result = await a.update(added.fact!.id, value: 'Kijkt op zaterdag', category: MemoryCategory.habit);

      expect(result.code, MemoryCode.ok);
      final fact = (await a.list()).single;
      expect(fact.value, 'Kijkt op zaterdag');
      expect(fact.category, MemoryCategory.habit);
      expect(fact.source, MemorySource.settingsManual);
      expect(fact.updatedAt.isAfter(fact.createdAt), isTrue);
    });

    test('rewriting only the spelling of a fact is not a duplicate of itself', () async {
      final added = await a.remember('houdt van westerns');
      final result = await a.update(added.fact!.id, value: 'Houdt van westerns.');
      expect(result.code, MemoryCode.ok);
      expect(await a.values(), ['Houdt van westerns.']);
    });

    test('an update is checked like a new fact', () async {
      final added = await a.remember('Kijkt op vrijdag');
      expect((await a.update(added.fact!.id, value: 'regel een\nregel twee')).code, MemoryCode.notSingleLine);
      expect((await a.update(added.fact!.id, value: 'Onze dochter is 8')).code, MemoryCode.ownedKidsAges);
      expect((await a.update(added.fact!.id, value: 'x' * 201)).code, MemoryCode.tooLong);
      expect(await a.values(), ['Kijkt op vrijdag']);
    });

    test('delete removes the fact for good and unknown ids change nothing', () async {
      final added = await a.remember('Kijkt op vrijdag');
      expect((await a.delete('no-such-id')).code, MemoryCode.notFound);
      expect(await a.values(), hasLength(1));

      final removed = await a.delete(added.fact!.id);
      expect(removed.code, MemoryCode.ok);
      expect(removed.fact!.value, 'Kijkt op vrijdag');
      expect(await a.list(), isEmpty);
      expect((await a.update(added.fact!.id, value: 'terug')).code, MemoryCode.notFound);
    });

    test('ages and language preferences are refused and nothing is stored', () async {
      expect((await a.remember('De kinderen zijn 6 en 9 jaar')).code, MemoryCode.ownedKidsAges);
      expect((await a.remember('Wil altijd Nederlandse ondertitels')).code, MemoryCode.ownedLanguage);
      expect((await a.remember('Kijkt het liefst in het Engels')).code, MemoryCode.ownedLanguage);
      expect(await db.select(db.assistantMemories).get(), isEmpty);
    });

    test('the ceiling is 200 facts per profile', () async {
      for (var i = 0; i < kMemoryFactLimit; i++) {
        expect((await a.remember('feit nummer $i')).code, MemoryCode.ok);
      }

      expect((await a.remember('een te veel')).code, MemoryCode.limitReached);
      expect(await a.list(), hasLength(kMemoryFactLimit));
      // A sentence that is already there is still recognised at the ceiling.
      expect((await a.remember('feit nummer 7')).code, MemoryCode.exists);
      // Another profile has its own ceiling.
      expect((await b.remember('een te veel')).code, MemoryCode.ok);

      final oldest = (await a.list()).last;
      await a.delete(oldest.id);
      expect((await a.remember('een te veel')).code, MemoryCode.ok);
    });

    test('list filters on category and on every word of the query', () async {
      await a.remember('Houdt van Franse films');
      await a.remember('Houdt niet van horror', category: MemoryCategory.dislike);
      await a.remember('Kijkt op vrijdag films', category: MemoryCategory.habit);

      expect(await a.values(), ['Kijkt op vrijdag films', 'Houdt niet van horror', 'Houdt van Franse films']);
      expect([for (final f in await a.list(category: MemoryCategory.dislike)) f.value], ['Houdt niet van horror']);
      expect([for (final f in await a.list(query: 'FILMS')) f.value], hasLength(2));
      expect([for (final f in await a.list(query: 'films vrij')) f.value], ['Kijkt op vrijdag films']);
      expect(await a.list(query: 'western'), isEmpty);
      expect(await a.list(query: '  '), hasLength(3));
    });

    test('without a profile nothing is read or written', () async {
      final nobody = MemoryService(database: db, profileId: '', now: clock.call);
      expect((await nobody.remember('Kijkt op vrijdag')).code, MemoryCode.noProfile);
      expect((await nobody.update('x', value: 'y')).code, MemoryCode.noProfile);
      expect((await nobody.delete('x')).code, MemoryCode.noProfile);
      expect((await nobody.resolve('abcdef12')).code, MemoryCode.noProfile);
      expect(await nobody.list(), isEmpty);
      expect(await nobody.enabled, isFalse);
      final saved = await nobody.saveOverview(
        factsHash: await nobody.takenHash(),
        locale: 'nl',
        status: MemoryOverviewStatus.ok,
        body: '{}',
      );
      expect(saved.code, MemoryCode.noProfile);
      expect((await nobody.clearAll()).code, MemoryCode.noProfile);
      expect(await db.select(db.assistantMemories).get(), isEmpty);
      expect(await db.select(db.assistantMemoryOverviews).get(), isEmpty);
    });
  });

  group('profile isolation', () {
    late MemoryFact factOfA;

    setUp(() async {
      factOfA = (await a.remember('Houdt van westerns')).fact!;
    });

    test('another profile does not read the fact, by list, query, reference or question', () async {
      expect(await b.list(), isEmpty);
      expect(await b.list(query: 'westerns'), isEmpty);
      expect((await b.resolve(factOfA.ref)).code, MemoryCode.notFound);
      expect((await b.resolve(factOfA.id)).code, MemoryCode.notFound);
      expect(await b.relevantFor('Welke westerns zijn er?'), isEmpty);
      expect(await a.relevantFor('Welke westerns zijn er?'), hasLength(1));
    });

    test('another profile cannot update the fact with its valid id', () async {
      final result = await b.update(factOfA.id, value: 'Houdt van musicals', category: MemoryCategory.other);

      expect(result.code, MemoryCode.notFound);
      expect(result.fact, isNull);
      final kept = (await a.list()).single;
      expect(kept.value, 'Houdt van westerns');
      expect(kept.category, MemoryCategory.preference);
      expect(kept.updatedAt, factOfA.updatedAt);
      expect(await b.list(), isEmpty);
    });

    test('another profile cannot delete the fact with its valid id', () async {
      final result = await b.delete(factOfA.id);

      expect(result.code, MemoryCode.notFound);
      expect(result.fact, isNull);
      expect(await a.values(), ['Houdt van westerns']);
    });

    test('the same sentence is a row of its own in each profile', () async {
      final own = await b.remember('Houdt van westerns');
      expect(own.code, MemoryCode.ok);
      expect(own.fact!.id, isNot(factOfA.id));

      await b.clearAll();
      expect(await b.list(), isEmpty);
      expect(await a.values(), ['Houdt van westerns']);
    });

    test('the overview of one profile is not read, replaced or cleared by another', () async {
      await a.saveOverview(
        factsHash: await a.takenHash(),
        locale: 'nl',
        status: MemoryOverviewStatus.ok,
        body: '{"overview":"van a"}',
      );

      expect(await b.overview(), isNull);
      expect(await b.overviewIsStale(locale: 'nl'), isTrue);

      await b.saveOverview(
        factsHash: await b.takenHash(),
        locale: 'nl',
        status: MemoryOverviewStatus.ok,
        body: '{"overview":"van b"}',
      );
      expect((await a.overview())!.body, '{"overview":"van a"}');

      await b.clearAll();
      expect(await b.overview(), isNull);
      expect((await a.overview())!.body, '{"overview":"van a"}');
      expect(await a.overviewIsStale(locale: 'nl'), isFalse);
    });

    test('the facts hash of a profile does not move when another profile writes', () async {
      final before = await a.takenHash();
      await b.remember('Kijkt graag thrillers');
      expect(await a.takenHash(), before);
    });
  });

  group('short references', () {
    test('unknown, malformed and ambiguous references change nothing', () async {
      var next = 0;
      final ids = [
        'aaaaaaaa-0000-4000-8000-000000000001',
        'aaaaaaaa-0000-4000-8000-000000000002',
        'bbbbbbbb-0000-4000-8000-000000000003',
      ];
      final fixed = MemoryService(database: db, profileId: 'profile-a', now: clock.call, newId: () => ids[next++]);
      await fixed.remember('Houdt van westerns');
      await fixed.remember('Houdt van musicals');
      await fixed.remember('Houdt van thrillers');
      final before = await fixed.takenHash();

      expect((await fixed.resolve('aaaaaaaa')).code, MemoryCode.ambiguous);
      expect((await fixed.resolve('aaaaaaaa')).fact, isNull);
      expect((await fixed.resolve('cccccccc')).code, MemoryCode.notFound);
      for (final malformed in ['', 'bbbb', '%', '________', 'bbbbbbb%', "bbbbbbbb' OR 1=1 --", 'houdt van']) {
        expect((await fixed.resolve(malformed)).code, MemoryCode.notFound, reason: malformed);
      }

      final unique = await fixed.resolve(' BBBBBBBB ');
      expect(unique.code, MemoryCode.ok);
      expect(unique.fact!.value, 'Houdt van thrillers');
      expect((await fixed.resolve(ids[1])).fact!.value, 'Houdt van musicals');

      expect(await fixed.takenHash(), before);
      expect(await fixed.list(), hasLength(3));
    });
  });

  group('restart', () {
    test('facts, the overview and the switch survive closing and reopening the database file', () async {
      final tempDir = await Directory.systemTemp.createTemp('pleya_memory_restart_test_');
      final file = File('${tempDir.path}/pleya_downloads.db');
      AppDatabase? second;
      try {
        final first = AppDatabase.forTesting(NativeDatabase(file));
        final before = MemoryService(database: first, profileId: 'profile-a', now: clock.call);
        final added = await before.remember('Kijkt op vrijdag met het gezin', category: MemoryCategory.habit);
        final hash = await before.takenHash();
        await before.saveOverview(
          factsHash: hash,
          locale: 'nl',
          status: MemoryOverviewStatus.ok,
          body: '{"overview":"x"}',
        );
        await before.setEnabled(false);
        await first.close();

        second = AppDatabase.forTesting(NativeDatabase(file));
        final after = MemoryService(database: second, profileId: 'profile-a', now: clock.call);
        final fact = (await after.list()).single;
        expect(fact.id, added.fact!.id);
        expect(fact.value, 'Kijkt op vrijdag met het gezin');
        expect(fact.category, MemoryCategory.habit);
        expect(fact.updatedAt, added.fact!.updatedAt);
        expect(await after.takenHash(), hash);
        expect((await after.overview())!.body, '{"overview":"x"}');
        expect(await after.overviewIsStale(locale: 'nl'), isFalse);
        expect(await after.enabled, isFalse);
      } finally {
        await second?.close();
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('enabled', () {
    test('on by default, per profile, and off keeps the facts', () async {
      expect(await a.enabled, isTrue);
      await a.remember('Houdt van westerns');

      await a.setEnabled(false);

      expect(await a.enabled, isFalse);
      expect(await b.enabled, isTrue);
      expect(await a.values(), ['Houdt van westerns']);
      expect(await MemoryService(database: db, profileId: 'profile-a').enabled, isFalse);
    });

    test('the switch stays on this device and out of exports', () {
      const key = 'assistant_memory_enabled';
      expect(PreferenceSyncPolicyRegistry.isRegistered(key), isTrue);
      expect(PreferenceSyncPolicyRegistry.isProfileScoped(key), isTrue);
      expect(PreferenceSyncPolicyRegistry.maySync(key), isFalse);
      expect(PreferenceSyncPolicyRegistry.isExportable(key), isFalse);
    });
  });

  group('deleting a profile', () {
    test('wipes its facts, its overview and its switch, and nobody else\'s', () async {
      for (final memory in [a, b]) {
        await memory.remember('Houdt van westerns');
        await memory.saveOverview(
          factsHash: await memory.takenHash(),
          locale: 'nl',
          status: MemoryOverviewStatus.ok,
          body: '{}',
        );
        await memory.setEnabled(false);
      }

      // What deleteProfile() runs for the memory of the profile it removes.
      await db.deleteAssistantMemoryForProfile('profile-a');
      await clearProfileScopedStores(storage, 'profile-a');

      expect(await a.list(), isEmpty);
      expect(await a.overview(), isNull);
      expect(await a.enabled, isTrue, reason: 'the stored switch is gone, so the default is back');
      expect(await b.values(), ['Houdt van westerns']);
      expect(await b.overview(), isNotNull);
      expect(await b.enabled, isFalse);
    });

    test('deleteProfile calls the database wipe, and no other code takes a profile id', () {
      final flow = File('lib/screens/profile/profile_delete_flow.dart').readAsStringSync();
      expect(flow.contains('await database.deleteAssistantMemoryForProfile(profile.id);'), isTrue);

      final callers = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart') || entity.path.endsWith('.g.dart')) continue;
        if (entity.readAsStringSync().contains('deleteAssistantMemoryForProfile')) callers.add(entity.path);
      }
      expect(callers..sort(), [
        'lib/database/assistant_memory_wipe.dart',
        'lib/screens/profile/profile_delete_flow.dart',
      ]);

      // The service is bound to its profile: the constructor is the only
      // place a profile id goes in.
      final service = File('lib/services/memory/memory_service.dart').readAsStringSync();
      expect(RegExp(r'String\??\s+profileId').allMatches(service), hasLength(1));
    });
  });
}
