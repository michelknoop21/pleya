import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/services/memory/memory_store.dart';

import 'memory_test_support.dart';

/// The write statements carry the profile themselves. The service reads the
/// row with the profile first, so only a direct call shows a missing filter.
void main() {
  late AppDatabase db;
  late MemoryStore a;
  late MemoryStore b;

  setUp(() async {
    db = memoryTestDatabase();
    a = MemoryStore(db, 'profile-a');
    b = MemoryStore(db, 'profile-b');
    await a.insert(
      id: 'fact-1',
      category: 'preference',
      value: 'Houdt van westerns',
      valueKey: 'houdt van westerns',
      source: 'user_explicit',
      at: 1,
    );
  });

  tearDown(() => db.close());

  Future<int> rewrite(MemoryStore store) =>
      store.update('fact-1', category: 'other', value: 'Overschreven', valueKey: 'overschreven', source: 'x', at: 2);

  test('update with the id of another profile changes no row', () async {
    expect(await rewrite(b), 0);
    expect((await a.byId('fact-1'))!.value, 'Houdt van westerns');

    expect(await rewrite(a), 1);
    expect((await a.byId('fact-1'))!.value, 'Overschreven');
  });

  test('deleteById with the id of another profile removes no row', () async {
    expect(await b.deleteById('fact-1'), 0);
    expect(await a.byId('fact-1'), isNotNull);

    expect(await a.deleteById('fact-1'), 1);
    expect(await a.byId('fact-1'), isNull);
  });
}
