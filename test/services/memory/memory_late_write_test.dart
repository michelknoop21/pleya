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
      final taken = await a.factsHash(locale: 'nl');
      await db.deleteAssistantMemoryForProfile('profile-a');

      expect((await save(a, taken)).code, MemoryCode.profileGone);
      expect((await save(a, await a.factsHash(locale: 'nl'))).code, MemoryCode.profileGone);
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
      expect((await save(again, await again.factsHash(locale: 'nl'))).code, MemoryCode.ok);
    });

    test('the wipe is one transaction: a failing second delete keeps the facts', () async {
      await a.remember('Houdt van westerns');
      expect((await save(a, await a.factsHash(locale: 'nl'))).code, MemoryCode.ok);
      await db.customStatement(
        "CREATE TRIGGER boom BEFORE DELETE ON assistant_memory_overviews BEGIN SELECT RAISE(ABORT, 'disk'); END",
      );

      await expectLater(db.deleteAssistantMemoryForProfile('profile-a'), throwsA(isA<SqliteException>()));

      expect(await db.select(db.assistantMemories).get(), hasLength(1));
      expect(await overviewRows(), 1);
    });
  });

  group('after clearAll', () {
    test('an overview written from the wiped facts is refused and the service keeps working', () async {
      await a.remember('Houdt van westerns');
      final taken = await a.factsHash(locale: 'nl');

      expect((await a.clearAll()).code, MemoryCode.ok);
      expect((await save(a, taken)).code, MemoryCode.staleHash);
      expect(await overviewRows(), 0);

      expect((await a.remember('Kijkt op vrijdag')).code, MemoryCode.ok);
      expect((await save(a, taken)).code, MemoryCode.staleHash, reason: 'a new fact does not revive the old hash');
      expect((await save(a, await a.factsHash(locale: 'nl'))).code, MemoryCode.ok);
      expect(await overviewRows(), 1);
    });

    test('a wipe from another service of the same profile refuses it too', () async {
      await a.remember('Houdt van westerns');
      final taken = await a.factsHash(locale: 'nl');

      await MemoryService(database: db, profileId: 'profile-a').clearAll();

      expect((await save(a, taken)).code, MemoryCode.staleHash);
      expect(await overviewRows(), 0);
      expect((await a.remember('Kijkt op vrijdag')).code, MemoryCode.ok);
    });

    test('a wipe of another profile changes nothing here', () async {
      await a.remember('Houdt van westerns');
      final taken = await a.factsHash(locale: 'nl');
      await b.clearAll();

      expect((await save(a, taken)).code, MemoryCode.ok);
    });
  });

  test('a hash that did not come from this service is refused', () async {
    await a.remember('Houdt van westerns');
    final current = await a.factsHash(locale: 'nl');

    expect((await save(a, 'zelfbedacht')).code, MemoryCode.staleHash);
    expect((await save(a, '')).code, MemoryCode.staleHash);
    final other = MemoryService(database: db, profileId: 'profile-a');
    expect((await save(other, current)).code, MemoryCode.staleHash);
    expect(await overviewRows(), 0);
  });
}
