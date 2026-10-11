import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/services/memory/memory_service.dart';

import 'memory_test_support.dart';

/// A write that arrives after the facts were wiped stores nothing.
void main() {
  late AppDatabase db;
  late MemoryService a;
  late MemoryService b;

  setUp(() async {
    await resetMemoryPrefs();
    db = memoryTestDatabase();
    final clock = TickingClock();
    a = MemoryService(database: db, profileId: 'profile-a', now: clock.call);
    b = MemoryService(database: db, profileId: 'profile-b', now: clock.call);
  });

  tearDown(() => db.close());

  Future<MemoryResult> save(MemoryService memory, String hash) =>
      memory.saveOverview(factsHash: hash, locale: 'nl', status: MemoryOverviewStatus.ok, body: '{}');

  Future<int> overviewRows() async => (await db.select(db.assistantMemoryOverviews).get()).length;

  group('after the profile was deleted', () {
    test('the old service adds nothing', () async {
      await a.remember('Houdt van westerns');
      await db.deleteAssistantMemoryForProfile('profile-a');

      expect((await a.remember('Late schrijfactie')).code, MemoryCode.profileGone);
      expect(await db.select(db.assistantMemories).get(), isEmpty);
    });

    test('an overview that was being written is not stored', () async {
      await a.remember('Houdt van westerns');
      final taken = await a.takenHash();
      await db.deleteAssistantMemoryForProfile('profile-a');

      expect((await save(a, taken)).code, MemoryCode.profileGone);
      expect((await save(a, await a.takenHash())).code, MemoryCode.profileGone);
      expect(await overviewRows(), 0);
    });

    test('an add that is already on its way leaves no row', () async {
      final pending = a.remember('Onderweg');
      await db.deleteAssistantMemoryForProfile('profile-a');
      await pending;

      expect(await db.select(db.assistantMemories).get(), isEmpty);
      expect((await a.remember('Daarna')).code, MemoryCode.profileGone);
    });

    test('another profile and a new service for the same id are not affected', () async {
      await db.deleteAssistantMemoryForProfile('profile-a');

      expect((await b.remember('Kijkt op vrijdag')).code, MemoryCode.ok);
      final again = MemoryService(database: db, profileId: 'profile-a');
      expect((await again.remember('Nieuw begin')).code, MemoryCode.ok);
      expect((await save(again, await again.takenHash())).code, MemoryCode.ok);
    });

    test('the wipe is one transaction: a failing second delete keeps the facts', () async {
      await a.remember('Houdt van westerns');
      expect((await save(a, await a.takenHash())).code, MemoryCode.ok);
      await db.customStatement(
        "CREATE TRIGGER boom BEFORE DELETE ON assistant_memory_overviews BEGIN SELECT RAISE(ABORT, 'disk'); END",
      );

      await expectLater(db.deleteAssistantMemoryForProfile('profile-a'), throwsA(isA<SqliteException>()));

      expect(await db.select(db.assistantMemories).get(), hasLength(1));
      expect(await overviewRows(), 1);
    });
  });

  group('a deletion that fails', () {
    test('leaves the service of the profile working', () async {
      final kept = await a.remember('Houdt van westerns');
      await db.customStatement(
        "CREATE TRIGGER boom BEFORE DELETE ON assistant_memories BEGIN SELECT RAISE(ABORT, 'disk'); END",
      );

      await expectLater(db.deleteAssistantMemoryForProfile('profile-a'), throwsA(isA<SqliteException>()));

      expect(await a.values(), ['Houdt van westerns']);
      expect((await a.remember('Kijkt op vrijdag')).code, MemoryCode.ok);
      expect((await a.update(kept.fact!.id, value: 'Houdt van musicals')).code, MemoryCode.ok);
      expect((await save(a, await a.takenHash())).code, MemoryCode.ok);

      // The next deletion goes through and then the service is done.
      await db.customStatement('DROP TRIGGER boom');
      await db.deleteAssistantMemoryForProfile('profile-a');
      expect((await a.remember('Daarna')).code, MemoryCode.profileGone);
      expect(await db.select(db.assistantMemories).get(), isEmpty);
    });
  });

  group('the facts and their hash come from one read', () {
    test('a fact added after the read refuses the save and stores nothing', () async {
      await a.remember('Houdt van westerns');
      final input = (await a.overviewInput(locale: 'nl'))!;
      expect([for (final fact in input.facts) fact.value], ['Houdt van westerns']);
      expect(input.locale, 'nl');

      await a.remember('Kijkt op vrijdag');

      expect((await save(a, input.factsHash)).code, MemoryCode.staleHash);
      expect(await overviewRows(), 0);
      expect(await a.overviewIsStale(locale: 'nl'), isTrue);

      final again = (await a.overviewInput(locale: 'nl'))!;
      expect(again.facts, hasLength(2));
      expect((await save(a, again.factsHash)).code, MemoryCode.ok);
      expect(await a.overviewIsStale(locale: 'nl'), isFalse);
    });

    test('a changed and a removed fact refuse it too', () async {
      final first = await a.remember('Houdt van westerns');
      final second = await a.remember('Kijkt op vrijdag');

      var input = (await a.overviewInput(locale: 'nl'))!;
      await a.update(first.fact!.id, category: MemoryCategory.other);
      expect((await save(a, input.factsHash)).code, MemoryCode.staleHash);

      input = (await a.overviewInput(locale: 'nl'))!;
      await a.delete(second.fact!.id);
      expect((await save(a, input.factsHash)).code, MemoryCode.staleHash);
      expect(await overviewRows(), 0);
    });

    test('clearAll after the read refuses the save', () async {
      await a.remember('Houdt van westerns');
      final input = (await a.overviewInput(locale: 'nl'))!;

      expect((await a.clearAll()).code, MemoryCode.ok);

      expect((await save(a, input.factsHash)).code, MemoryCode.staleHash);
      expect(await overviewRows(), 0);
    });

    test('a hash for one locale does not save an overview in another', () async {
      await a.remember('Houdt van westerns');
      final input = (await a.overviewInput(locale: 'nl'))!;

      final saved = await a.saveOverview(
        factsHash: input.factsHash,
        locale: 'en',
        status: MemoryOverviewStatus.ok,
        body: '{}',
      );

      expect(saved.code, MemoryCode.staleHash);
      expect(await overviewRows(), 0);
    });

    test('a read that fails gives no input, and then nothing can be saved', () async {
      await a.remember('Houdt van westerns');
      final before = (await a.overviewInput(locale: 'nl'))!;
      await db.customStatement('ALTER TABLE assistant_memories RENAME TO elsewhere');

      expect(await a.overviewInput(locale: 'nl'), isNull);
      expect(await a.takenHash(), isEmpty);
      expect((await save(a, before.factsHash)).code, MemoryCode.storageFailed);
      expect((await save(a, '')).code, MemoryCode.storageFailed);

      // The table is back: the old hash still stands for the same facts, and
      // a hash nobody handed out is still refused.
      await db.customStatement('ALTER TABLE elsewhere RENAME TO assistant_memories');
      expect((await save(a, '')).code, MemoryCode.staleHash);
      expect(await overviewRows(), 0);
      expect((await save(a, before.factsHash)).code, MemoryCode.ok);
    });

    test('without a profile there is no input', () async {
      expect(await MemoryService(database: db, profileId: '').overviewInput(locale: 'nl'), isNull);
    });
  });

  group('after clearAll', () {
    test('an overview written from the wiped facts is refused and the service keeps working', () async {
      await a.remember('Houdt van westerns');
      final taken = await a.takenHash();

      expect((await a.clearAll()).code, MemoryCode.ok);
      expect((await save(a, taken)).code, MemoryCode.staleHash);
      expect(await overviewRows(), 0);

      expect((await a.remember('Kijkt op vrijdag')).code, MemoryCode.ok);
      expect((await save(a, taken)).code, MemoryCode.staleHash, reason: 'a new fact does not revive the old hash');
      expect((await save(a, await a.takenHash())).code, MemoryCode.ok);
      expect(await overviewRows(), 1);
    });

    test('a wipe from another service of the same profile refuses it too', () async {
      await a.remember('Houdt van westerns');
      final taken = await a.takenHash();

      await MemoryService(database: db, profileId: 'profile-a').clearAll();

      expect((await save(a, taken)).code, MemoryCode.staleHash);
      expect(await overviewRows(), 0);
      expect((await a.remember('Kijkt op vrijdag')).code, MemoryCode.ok);
    });

    test('a wipe of another profile changes nothing here', () async {
      await a.remember('Houdt van westerns');
      final taken = await a.takenHash();
      await b.clearAll();

      expect((await save(a, taken)).code, MemoryCode.ok);
    });
  });

  test('a hash that did not come from this service is refused', () async {
    await a.remember('Houdt van westerns');
    final current = await a.takenHash();

    expect((await save(a, 'zelfbedacht')).code, MemoryCode.staleHash);
    expect((await save(a, '')).code, MemoryCode.staleHash);
    final other = MemoryService(database: db, profileId: 'profile-a');
    expect((await save(other, current)).code, MemoryCode.staleHash);
    expect(await overviewRows(), 0);
  });
}
