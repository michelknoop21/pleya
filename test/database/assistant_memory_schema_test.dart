import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';

const _index = 'idx_assistant_memories_profile_value_key';

AssistantMemoriesCompanion _fact(String id, String profileId, String key) => AssistantMemoriesCompanion.insert(
  id: id,
  profileId: profileId,
  category: 'preference',
  value: key,
  valueKey: key,
  source: 'user_explicit',
  createdAt: 1,
  updatedAt: 1,
);

AssistantMemoryOverviewsCompanion _overview(String profileId) => AssistantMemoryOverviewsCompanion.insert(
  profileId: profileId,
  factsHash: 'h',
  locale: 'nl',
  status: 'ok',
  body: '{}',
  generatedAt: 1,
);

Future<Set<String>> _names(AppDatabase db, String type) async {
  final rows = await db
      .customSelect('SELECT name FROM sqlite_master WHERE type = ?', variables: [Variable(type)])
      .get();
  return rows.map((r) => r.read<String>('name')).toSet();
}

Future<bool> _indexIsUnique(AppDatabase db) async {
  final rows = await db.customSelect('PRAGMA index_list(assistant_memories)').get();
  final row = rows.singleWhere((r) => r.read<String>('name') == _index);
  return row.read<int>('unique') == 1;
}

/// A database file as schema 21 left it: without the memory tables.
Future<void> _seedVersion21(File file, {bool keepTables = false}) async {
  final seeded = AppDatabase.forTesting(NativeDatabase(file));
  await seeded.into(seeded.apiCache).insert(ApiCacheCompanion.insert(cacheKey: 'kept', data: '{}'));
  if (!keepTables) {
    await seeded.customStatement('DROP INDEX $_index');
    await seeded.customStatement('DROP TABLE assistant_memories');
    await seeded.customStatement('DROP TABLE assistant_memory_overviews');
  }
  await seeded.customStatement('PRAGMA user_version = 21');
  await seeded.close();
}

void main() {
  group('fresh install', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('creates both memory tables and the unique index', () async {
      expect(await db.select(db.assistantMemories).get(), isEmpty);
      expect(await db.select(db.assistantMemoryOverviews).get(), isEmpty);
      expect(await _names(db, 'index'), contains(_index));
      expect(await _indexIsUnique(db), isTrue);
    });

    test('the index refuses the same key twice in one profile and allows it in another', () async {
      await db.into(db.assistantMemories).insert(_fact('1', 'a', 'houdt van horror'));
      await expectLater(
        db.into(db.assistantMemories).insert(_fact('2', 'a', 'houdt van horror')),
        throwsA(isA<SqliteException>()),
      );
      await db.into(db.assistantMemories).insert(_fact('3', 'b', 'houdt van horror'));
      expect(await db.select(db.assistantMemories).get(), hasLength(2));
    });

    test('deleteAssistantMemoryForProfile wipes one profile and leaves the other', () async {
      for (final profile in ['a', 'b']) {
        await db.into(db.assistantMemories).insert(_fact('f-$profile', profile, 'x'));
        await db.into(db.assistantMemoryOverviews).insert(_overview(profile));
        await db
            .into(db.assistantMemorySyncStates)
            .insert(AssistantMemorySyncStatesCompanion.insert(profileId: profile, payload: '{}'));
      }

      await db.deleteAssistantMemoryForProfile('a');

      expect((await db.select(db.assistantMemories).get()).map((r) => r.profileId), ['b']);
      expect((await db.select(db.assistantMemoryOverviews).get()).map((r) => r.profileId), ['b']);
      expect((await db.select(db.assistantMemorySyncStates).get()).map((r) => r.profileId), ['b']);
    });
  });

  test('v23 adds sync state without changing v22 facts or overview', () async {
    final directory = await Directory.systemTemp.createTemp('pleya_memory_sync_migration_');
    final file = File('${directory.path}/test.db');
    AppDatabase? opened;
    try {
      final old = AppDatabase.forTesting(NativeDatabase(file));
      await old.customStatement('DROP TABLE IF EXISTS assistant_memories');
      await old.customStatement('''
        CREATE TABLE assistant_memories (
          id TEXT NOT NULL PRIMARY KEY, profile_id TEXT NOT NULL,
          category TEXT NOT NULL, value TEXT NOT NULL, value_key TEXT NOT NULL,
          source TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
        )
      ''');
      await old.into(old.assistantMemories).insert(_fact('preserved', 'p', 'preserved'));
      await old.into(old.assistantMemoryOverviews).insert(_overview('p'));
      await old.customStatement('DROP TABLE assistant_memory_sync_states');
      await old.customStatement('PRAGMA user_version = 22');
      await old.close();
      final db = opened = AppDatabase.forTesting(NativeDatabase(file));
      expect((await db.select(db.assistantMemories).get()).single.value, 'preserved');
      expect(await db.select(db.assistantMemoryOverviews).get(), hasLength(1));
      expect(await db.select(db.assistantMemorySyncStates).get(), isEmpty);
      await db.into(db.assistantMemories).insert(_fact('preserved', 'second-profile', 'second'));
      expect(await db.select(db.assistantMemories).get(), hasLength(2));
      expect((await db.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version'), 23);
    } finally {
      await opened?.close();
      await directory.delete(recursive: true);
    }
  });

  group('migration from 21', () {
    late Directory tempDir;
    late File file;
    AppDatabase? reopened;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pleya_db_v22_migration_test_');
      file = File('${tempDir.path}/pleya_downloads.db');
    });

    tearDown(() async {
      await reopened?.close();
      reopened = null;
      await tempDir.delete(recursive: true);
    });

    test('adds both tables and the unique index, and keeps what was there', () async {
      await _seedVersion21(file);

      final db = reopened = AppDatabase.forTesting(NativeDatabase(file));
      expect(await db.select(db.assistantMemories).get(), isEmpty);
      expect(await db.select(db.assistantMemoryOverviews).get(), isEmpty);
      expect(await _names(db, 'table'), containsAll(['assistant_memories', 'assistant_memory_overviews']));
      expect(await _indexIsUnique(db), isTrue);
      expect((await db.select(db.apiCache).get()).map((r) => r.cacheKey), ['kept']);
      expect((await db.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version'), 23);

      await db.into(db.assistantMemories).insert(_fact('1', 'a', 'k'));
      await expectLater(db.into(db.assistantMemories).insert(_fact('2', 'a', 'k')), throwsA(isA<SqliteException>()));
      await db.into(db.assistantMemoryOverviews).insert(_overview('a'));
    });

    test('a retried migration tolerates tables and an index that already exist', () async {
      await _seedVersion21(file, keepTables: true);

      final db = reopened = AppDatabase.forTesting(NativeDatabase(file));
      expect(await db.select(db.assistantMemories).get(), isEmpty);
      expect(await _indexIsUnique(db), isTrue);
    });
  });
}
