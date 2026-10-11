import 'package:drift/native.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/services/memory/memory_service.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';

import '../../test_helpers/prefs.dart';

/// Mocked preferences, so `enabled` reads and writes without a platform.
Future<StorageService> resetMemoryPrefs() async {
  resetSharedPreferencesForTest();
  SettingsService.resetForTesting();
  final storage = await StorageService.getInstance();
  await SettingsService.getInstance();
  return storage;
}

AppDatabase memoryTestDatabase() => AppDatabase.forTesting(NativeDatabase.memory());

/// A clock that moves one second per reading, so every write has its own time.
class TickingClock {
  DateTime _at = DateTime.utc(2026, 10, 11, 12);
  bool frozen = false;

  DateTime call() => frozen ? _at : _at = _at.add(const Duration(seconds: 1));
}

extension MemoryTestShortcuts on MemoryService {
  Future<MemoryResult> remember(String value, {MemoryCategory category = MemoryCategory.preference}) =>
      add(value: value, category: category, source: MemorySource.userExplicit);

  /// The hash of a fresh [overviewInput], or empty when there is none.
  Future<String> takenHash({String locale = 'nl'}) async => (await overviewInput(locale: locale))?.factsHash ?? '';

  Future<List<String>> values() async => [for (final fact in await list()) fact.value];
}
