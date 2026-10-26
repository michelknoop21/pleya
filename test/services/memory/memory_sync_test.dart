import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/services/memory/memory_service.dart';

import 'memory_test_support.dart';

const _epoch = '11111111-1111-4111-8111-111111111111';
const _otherEpoch = '22222222-2222-4222-8222-222222222222';

class _Server implements MemorySyncTransport {
  MemorySyncSnapshot snapshot = MemorySyncSnapshot(epoch: _epoch, revision: 0, facts: []);
  final Set<String> deleted = {};
  bool online = true;
  int writes = 0;
  Future<void> Function()? beforeFetchReturn;
  Future<void> Function()? afterReplace;

  @override
  Future<MemorySyncSnapshot> fetch() async {
    if (!online) throw const MemorySyncFailure('offline');
    final response = MemorySyncSnapshot.fromJson(snapshot.toJson());
    final hook = beforeFetchReturn;
    beforeFetchReturn = null;
    await hook?.call();
    return response;
  }

  @override
  Future<MemorySyncSnapshot> replace({
    required String epoch,
    required int baseRevision,
    required List<MemoryFact> facts,
  }) async {
    if (!online) throw const MemorySyncFailure('offline');
    if (epoch != snapshot.epoch) throw const MemorySyncFailure('memory.epoch_changed');
    if (baseRevision != snapshot.revision) throw const MemorySyncFailure('memory.conflict');
    validateSyncFacts(facts);
    if (facts.any((f) => deleted.contains(f.id))) throw const MemorySyncFailure('memory.deleted');
    deleted.addAll(snapshot.facts.where((f) => !facts.any((a) => a.id == f.id)).map((f) => f.id));
    writes++;
    snapshot = MemorySyncSnapshot(epoch: epoch, revision: snapshot.revision + 1, facts: facts);
    final response = MemorySyncSnapshot.fromJson(snapshot.toJson());
    final hook = afterReplace;
    afterReplace = null;
    await hook?.call();
    return response;
  }

  @override
  Future<MemorySyncSnapshot> clear({required String epoch, required int baseRevision}) async {
    if (epoch != snapshot.epoch || baseRevision != snapshot.revision) throw const MemorySyncFailure('memory.conflict');
    writes++;
    deleted.clear();
    return snapshot = MemorySyncSnapshot(epoch: _otherEpoch, revision: snapshot.revision + 1, facts: []);
  }
}

class _Device {
  _Device(this.server, this.profile) {
    db = memoryTestDatabase();
    memory = MemoryService(database: db, profileId: profile);
    rebuild();
  }
  final _Server server;
  final String profile;
  late AppDatabase db;
  late MemoryService memory;
  late MemorySyncService sync;
  bool eligible = true;
  bool current = true;

  void rebuild() {
    sync = MemorySyncService(
      memory: memory,
      transportFor: (key) async => key == 'server/user' ? server : null,
      isEligible: () => eligible,
      isCurrent: () => current,
    );
  }

  Future<void> connect({Set<String>? selectedIds}) async =>
      sync.connect(await sync.preview('server/user'), selectedIds: selectedIds);

  Future<void> drain() async {
    for (var i = 0; i < 3; i++) {
      await sync.sync(force: true);
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> close() async {
    sync.dispose();
    await Future<void>.delayed(Duration.zero);
    memory.dispose();
    await db.close();
  }
}

void main() {
  late _Server server;
  late _Device a;
  late _Device b;
  setUp(() async {
    await resetMemoryPrefs();
    server = _Server();
    a = _Device(server, 'a');
    b = _Device(server, 'b');
  });
  tearDown(() async {
    await a.close();
    await b.close();
  });

  test('two clients share add/edit/delete; enabled stays device-local', () async {
    final added = await a.memory.remember('Houdt van oude westerns');
    await a.connect();
    await b.memory.setEnabled(false);
    await b.connect();
    expect(await b.memory.values(), ['Houdt van oude westerns']);
    expect(await b.memory.enabled, isFalse);
    await a.memory.update(added.fact!.id, value: 'Houdt van nieuwe westerns');
    await a.drain();
    await b.drain();
    expect(await b.memory.values(), ['Houdt van nieuwe westerns']);
    await b.memory.delete(added.fact!.id);
    await b.drain();
    await a.drain();
    expect(await a.memory.list(), isEmpty);
    expect(server.deleted, contains(added.fact!.id));
  });

  test('only selected facts upload; household and skipped facts survive download', () async {
    final shared = await a.memory.remember('Kijkt graag westerns');
    await a.memory.remember('Familie kijkt op zaterdag', category: MemoryCategory.household);
    await a.memory.remember('Niet delen met de server');
    await a.connect(selectedIds: {shared.fact!.id});
    expect(server.snapshot.facts.map((f) => f.value), ['Kijkt graag westerns']);
    await b.connect();
    await b.memory.remember('Houdt van detectives');
    await b.drain();
    await a.drain();
    expect(
      await a.memory.values(),
      containsAll([
        'Kijkt graag westerns',
        'Familie kijkt op zaterdag',
        'Niet delen met de server',
        'Houdt van detectives',
      ]),
    );
    expect(server.snapshot.facts, hasLength(2));
  });

  test('two explicitly linked profiles in one database keep the same server UUID isolated', () async {
    final added = await a.memory.remember('Gedeelde serverherinnering');
    await a.connect();
    final otherMemory = MemoryService(database: a.db, profileId: 'same-db-profile');
    final otherSync = MemorySyncService(
      memory: otherMemory,
      transportFor: (_) async => server,
      isEligible: () => true,
      isCurrent: () => true,
    );
    try {
      await otherSync.connect(await otherSync.preview('server/user'));
      expect((await otherMemory.list()).single.id, added.fact!.id);
      expect(await a.db.select(a.db.assistantMemories).get(), hasLength(2));
      await a.sync.disconnect();
      await a.memory.update(added.fact!.id, value: 'Alleen dit lokale profiel');
      expect((await otherMemory.list()).single.value, 'Gedeelde serverherinnering');
    } finally {
      otherSync.dispose();
      otherMemory.dispose();
    }
  });

  test('stale preview never uploads text changed after the preview', () async {
    final fact = await a.memory.remember('Nog lokaal');
    final preview = await a.sync.preview('server/user');
    await a.memory.update(fact.fact!.id, value: 'Na de toestemming gewijzigd');
    await expectLater(a.sync.connect(preview), throwsA(isA<MemorySyncFailure>()));
    expect(server.snapshot.facts, isEmpty);
    expect(a.sync.accountKey, isNull);
  });

  test('first link merges existing server content and equal sentences without duplicates', () async {
    await a.memory.remember('Kijkt graag westerns');
    await a.connect();
    await b.memory.remember('Kijkt graag westerns!');
    await b.memory.remember('Houdt van detectives');
    await b.connect();
    expect(server.snapshot.facts, hasLength(2));
    expect(await b.memory.list(), hasLength(2));
  });

  test('offline edits survive a service restart with the same durable binding', () async {
    final fact = await a.memory.remember('Kijkt op vrijdag');
    await a.connect();
    server.online = false;
    await a.memory.update(fact.fact!.id, value: 'Kijkt op zaterdag');
    await a.drain();
    expect(a.sync.status, MemorySyncStatus.error);
    a.sync.dispose();
    a.rebuild();
    await a.sync.load();
    expect(a.sync.accountKey, 'server/user');
    server.online = true;
    await a.drain();
    expect(server.snapshot.facts.single.value, 'Kijkt op zaterdag');
    expect(a.sync.status, MemorySyncStatus.synced);
  });

  test('a local mutation during GET is rebased and not overwritten', () async {
    final fact = await a.memory.remember('Kijkt op vrijdag');
    await a.connect();
    server.beforeFetchReturn = () => a.memory.update(fact.fact!.id, value: 'Kijkt op zaterdag').then((_) {});
    await a.drain();
    expect(await a.memory.values(), ['Kijkt op zaterdag']);
    expect(server.snapshot.facts.single.value, 'Kijkt op zaterdag');
  });

  test('PUT acknowledgment confirms only its sent generation', () async {
    final fact = await a.memory.remember('Kijkt op vrijdag');
    await a.connect();
    server.online = false;
    await a.memory.update(fact.fact!.id, value: 'Kijkt op zaterdag');
    await a.drain();
    server.online = true;
    server.afterReplace = () => a.memory.update(fact.fact!.id, value: 'Kijkt op zondag').then((_) {});
    await a.drain();
    expect(await a.memory.values(), ['Kijkt op zondag']);
    expect(server.snapshot.facts.single.value, 'Kijkt op zondag');
    expect(a.sync.conflicts, isEmpty);
  });

  test('crash after accepted PUT preserves a later edit using the durable receipt', () async {
    final fact = await a.memory.remember('Kijkt op vrijdag');
    await a.connect();
    server.online = false;
    await a.memory.update(fact.fact!.id, value: 'Kijkt op zaterdag');
    await a.drain();
    server.online = true;
    server.afterReplace = () async {
      server.online = false;
      await a.memory.update(fact.fact!.id, value: 'Kijkt op zondag');
      throw const MemorySyncFailure('lost_response');
    };
    await a.drain();
    a.sync.dispose();
    a.rebuild();
    server.online = true;
    await a.drain();
    expect(server.snapshot.facts.single.value, 'Kijkt op zondag');
    expect(a.sync.conflicts, isEmpty);
  });

  test('simultaneous edits become explicit conflicts and retain both versions', () async {
    final fact = await a.memory.remember('Kijkt op vrijdag');
    await a.connect();
    await b.connect();
    b.eligible = false;
    await b.memory.update(fact.fact!.id, value: 'Kijkt op zondag');
    await a.memory.update(fact.fact!.id, value: 'Kijkt op zaterdag');
    await a.drain();
    b.eligible = true;
    await b.drain();
    expect(b.sync.status, MemorySyncStatus.conflict);
    expect(b.sync.conflicts.single.local!.value, 'Kijkt op zondag');
    expect(b.sync.conflicts.single.server!.value, 'Kijkt op zaterdag');
    await b.sync.resolveConflict(fact.fact!.id, MemorySyncChoice.both);
    await b.drain();
    expect(server.snapshot.facts.map((f) => f.value), containsAll(['Kijkt op zondag', 'Kijkt op zaterdag']));
  });

  test('remote delete removes a conflicting local edit from active Big P context', () async {
    final fact = await a.memory.remember('Kijkt op vrijdag');
    await a.connect();
    await b.connect();
    b.eligible = false;
    await b.memory.update(fact.fact!.id, value: 'Kijkt op zondag');
    await a.memory.delete(fact.fact!.id);
    await a.drain();
    b.eligible = true;
    await b.drain();
    expect(await b.memory.list(), isEmpty);
    expect(b.sync.conflicts.single.local!.value, 'Kijkt op zondag');
    await b.sync.resolveConflict(fact.fact!.id, MemorySyncChoice.local);
    await b.drain();
    expect(server.snapshot.facts.single.id, isNot(fact.fact!.id));
    expect(server.snapshot.facts.single.value, 'Kijkt op zondag');
  });

  test('clear epoch stops offline creations and keeps them inactive until confirmation', () async {
    await a.memory.remember('Kijkt op vrijdag');
    await a.connect();
    await b.connect();
    b.eligible = false;
    await b.memory.remember('Offline nieuw feit');
    await a.memory.clearAll();
    await a.drain();
    expect(server.snapshot.epoch, _otherEpoch);
    b.eligible = true;
    await b.drain();
    expect(server.snapshot.facts, isEmpty);
    expect(await b.memory.list(), isEmpty);
    expect(b.sync.status, MemorySyncStatus.quarantine);
    expect(b.sync.conflicts.single.local!.value, 'Offline nieuw feit');
    await b.sync.acceptRemoteReset();
    await b.drain();
    expect(b.sync.conflicts, isEmpty);
    expect(server.snapshot.facts, isEmpty);
  });

  test('clearAll discards conflict drafts and clears the server', () async {
    final fact = await a.memory.remember('Kijkt op vrijdag');
    await a.connect();
    await b.connect();
    b.eligible = false;
    await b.memory.update(fact.fact!.id, value: 'Kijkt op zaterdag');
    await a.memory.update(fact.fact!.id, value: 'Kijkt op zondag');
    await a.drain();
    b.eligible = true;
    await b.drain();
    expect(b.sync.conflicts, isNotEmpty);
    await b.memory.clearAll();
    await b.drain();
    expect(server.snapshot.facts, isEmpty);
    expect(b.sync.conflicts, isEmpty);
    expect(b.sync.quarantine, isNull);
    expect(await b.memory.list(), isEmpty);
    final raw = await b.db.select(b.db.assistantMemorySyncStates).getSingle();
    expect(raw.payload, isNot(contains('Kijkt op')));
  });
  test('clearAll purges quarantine and never reactivates old drafts', () async {
    await a.memory.remember('Kijkt op vrijdag');
    await a.connect();
    a.eligible = false;
    await a.memory.remember('Prive concept');
    server.snapshot = MemorySyncSnapshot(epoch: _otherEpoch, revision: 0, facts: server.snapshot.facts);
    a.eligible = true;
    await a.drain();
    expect(a.sync.quarantine, isNotNull);
    expect(a.sync.conflicts, isNotEmpty);
    await a.memory.clearAll();
    await a.drain();
    expect(server.snapshot.facts, isEmpty);
    expect(a.sync.quarantine, isNull);
    expect(a.sync.conflicts, isEmpty);
    expect(await a.memory.list(), isEmpty);
    await a.sync.acceptRemoteReset();
    expect(await a.memory.list(), isEmpty);
  });
  test('a clear against changed server data needs explicit renewed confirmation', () async {
    final fact = await a.memory.remember('Kijkt op vrijdag');
    await a.connect();
    await b.connect();
    a.eligible = false;
    await a.memory.clearAll();
    await b.memory.update(fact.fact!.id, value: 'Kijkt op zondag');
    await b.drain();
    a.eligible = true;
    await a.drain();
    expect(a.sync.hasPendingClear, isTrue);
    expect(a.sync.quarantine, isNotNull);
    expect(server.snapshot.facts.single.value, 'Kijkt op zondag');
    expect(await a.memory.list(), isEmpty);
    await a.sync.acceptRemoteReset();
    await a.drain();
    expect(server.snapshot.facts, isEmpty);
    expect(a.sync.hasPendingClear, isFalse);
  });
  test('renewed server clear preserves facts created after the original local wipe', () async {
    final fact = await a.memory.remember('Kijkt op vrijdag');
    await a.connect();
    await b.connect();
    a.eligible = false;
    await a.memory.clearAll();
    await a.memory.remember('Nieuw na het wissen');
    await b.memory.update(fact.fact!.id, value: 'Kijkt op zondag');
    await b.drain();
    a.eligible = true;
    await a.drain();
    expect(a.sync.quarantine, isNotNull);
    await a.sync.acceptRemoteReset();
    await a.drain();
    expect(await a.memory.values(), ['Nieuw na het wissen']);
    expect(server.snapshot.facts.map((f) => f.value), ['Nieuw na het wissen']);
  });

  test('a newer clear supersedes an in-flight PUT acknowledgment', () async {
    final fact = await a.memory.remember('Kijkt op vrijdag');
    await a.connect();
    await a.memory.update(fact.fact!.id, value: 'Kijkt op zaterdag');
    server.afterReplace = () async {
      await a.memory.clearAll();
    };
    await a.drain();
    expect(server.snapshot.facts, isEmpty);
    expect(await a.memory.list(), isEmpty);
    expect(a.sync.conflicts, isEmpty);
  });
  test('an old deleted response cannot stage facts of a newly connected account', () async {
    a.sync.dispose();
    final other = _Server();
    a.sync = MemorySyncService(
      memory: a.memory,
      transportFor: (key) async => key == 'server/user' ? server : other,
      isEligible: () => a.eligible,
      isCurrent: () => a.current,
    );
    final fact = await a.memory.remember('Kijkt op vrijdag');
    await a.connect();
    final started = Completer<void>();
    final released = Completer<void>();
    await a.memory.update(fact.fact!.id, value: 'Kijkt op zaterdag');
    server.afterReplace = () async {
      started.complete();
      await released.future;
      throw const MemorySyncFailure('memory.deleted');
    };
    final oldRun = a.sync.sync(force: true);
    await started.future;
    await a.sync.disconnect();
    final preview = await a.sync.preview('other/user');
    final connecting = a.sync.connect(preview, selectedIds: {});
    for (var i = 0; i < 100 && a.sync.accountKey != 'other/user'; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(a.sync.accountKey, 'other/user');
    await a.memory.remember('Nieuw persoonlijk feit');
    released.complete();
    await oldRun;
    await connecting;
    await a.drain();
    expect(a.sync.conflicts, isEmpty);
    expect(await a.memory.values(), contains('Nieuw persoonlijk feit'));
    expect(other.snapshot.facts.map((f) => f.value), contains('Nieuw persoonlijk feit'));
  });

  test('restored epoch quarantines old facts even with a lower revision', () async {
    final fact = await a.memory.remember('Gewist feit');
    await a.connect();
    final backup = server.snapshot;
    await a.memory.delete(fact.fact!.id);
    await a.drain();
    server.snapshot = MemorySyncSnapshot(epoch: _otherEpoch, revision: backup.revision, facts: backup.facts);
    await a.drain();
    expect(await a.memory.list(), isEmpty);
    expect(a.sync.status, MemorySyncStatus.quarantine);
    await a.sync.acceptRemoteReset();
    await a.drain();
    expect(await a.memory.values(), ['Gewist feit']);
    expect(a.sync.status, MemorySyncStatus.synced);
  });

  test('profile switch while fetch is running refuses stale apply', () async {
    await a.memory.remember('Nieuw feit');
    await a.connect();
    await b.connect();
    await a.memory.remember('Nog een nieuw feit');
    await a.drain();
    server.beforeFetchReturn = () async {
      b.current = false;
    };
    await b.drain();
    expect(await b.memory.list(), hasLength(1));
  });

  test('disconnect preserves local facts and does not send them to another account', () async {
    await a.memory.remember('Nog lokaal bewaren');
    await a.connect();
    await a.sync.disconnect();
    await a.memory.remember('Na ontkoppelen');
    await a.drain();
    expect(await a.memory.list(), hasLength(2));
    expect(server.snapshot.facts, hasLength(1));
    a.sync.dispose();
    a.rebuild();
    await a.sync.load();
    expect(a.sync.accountKey, isNull);
  });

  test('a fact edit rolls back if its durable pending-generation write fails', () async {
    final fact = await a.memory.remember('Voor de fout');
    await a.connect();
    await a.db.customStatement(
      "CREATE TRIGGER refuse_sync BEFORE UPDATE ON assistant_memory_sync_states "
      "BEGIN SELECT RAISE(ABORT, 'forced storage failure'); END",
    );
    final result = await a.memory.update(fact.fact!.id, value: 'Mag niet half opslaan');
    expect(result.code, MemoryCode.storageFailed);
    expect(await a.memory.values(), ['Voor de fout']);
    expect(server.snapshot.facts.single.value, 'Voor de fout');
  });

  test('a deleted id from a disconnected client needs explicit restoration with a new id', () async {
    final fact = await a.memory.remember('Nog lokaal op het andere toestel');
    await a.connect();
    await b.connect();
    await b.sync.disconnect();
    await a.memory.delete(fact.fact!.id);
    await a.drain();
    await b.connect();
    expect(b.sync.status, MemorySyncStatus.conflict);
    expect(await b.memory.list(), isEmpty);
    expect(server.snapshot.facts, isEmpty);
    await b.sync.resolveConflict(fact.fact!.id, MemorySyncChoice.local);
    await b.drain();
    expect(server.snapshot.facts.single.id, isNot(fact.fact!.id));
  });

  test('unchanged polling keeps the written overview and does not notify memory consumers', () async {
    await a.memory.remember('Voor het overzicht');
    await a.connect();
    final input = await a.memory.overviewInput(locale: 'nl');
    await a.memory.saveOverview(factsHash: input!.factsHash, locale: 'nl', status: MemoryOverviewStatus.ok, body: '{}');
    var notifications = 0;
    a.memory.addListener(() => notifications++);
    await a.drain();
    expect(await a.memory.overview(), isNotNull);
    expect(notifications, 0);
  });

  test('snapshot parser rejects unknown values and malformed or duplicate facts', () async {
    await a.memory.remember('Kijkt op vrijdag');
    await a.connect();
    for (final field in ['category', 'source', 'id', 'created_at']) {
      final json = server.snapshot.toJson();
      (json['facts'] as List).single[field] = 'unknown';
      expect(() => MemorySyncSnapshot.fromJson(json), throwsA(isA<MemorySyncFailure>()));
    }
    final duplicate = server.snapshot.toJson();
    (duplicate['facts'] as List).add((duplicate['facts'] as List).single);
    expect(() => MemorySyncSnapshot.fromJson(duplicate), throwsA(isA<MemorySyncFailure>()));
  });
}
