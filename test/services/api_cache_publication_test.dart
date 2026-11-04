import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' show QueryInterceptor, QueryExecutor, ApplyInterceptor;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/services/api_cache.dart';

class _Cache extends ApiCache {
  _Cache(super.db, {super.encoder});
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

class _SqlHold extends QueryInterceptor {
  final entered = Completer<void>(), release = Completer<void>();
  bool held = false;
  @override
  Future<int> runInsert(QueryExecutor executor, String statement, List<Object?> args) async {
    if (!held &&
        statement.contains('api_cache') &&
        args.whereType<String>().any((arg) => arg.contains('"title":"A"'))) {
      held = true;
      entered.complete();
      await release.future;
    }
    return executor.runInsert(statement, args);
  }
}

void main() {
  test('guarded SQL publication remains ordered across wrappers for one DB/key', () async {
    final hold = _SqlHold();
    final db = AppDatabase.forTesting(NativeDatabase.memory().interceptWith(hold));
    addTearDown(db.close);
    final encodedB = Completer<void>();
    final a = _Cache(db);
    final b = _Cache(
      db,
      encoder: (data) async {
        encodedB.complete();
        return jsonEncode(data);
      },
    );
    final server = ServerId('same-server');
    final first = a.putIfCurrent(server, '/item', {'title': 'A'}, () => true);
    await hold.entered.future;
    final second = b.putIfCurrent(server, '/item', {'title': 'B'}, () => true);
    await encodedB.future;
    final early = await second.then((_) => true).timeout(const Duration(milliseconds: 100), onTimeout: () => false);
    hold.release.complete();
    await Future.wait([first, second]);
    expect(early, isFalse, reason: 'different wrappers must not bypass an in-flight SQL publication');
    expect((await b.get(server, '/item'))!['title'], 'B');
  });

  test('other guarded keys remain parallel while one SQL publication is held', () async {
    final hold = _SqlHold();
    final db = AppDatabase.forTesting(NativeDatabase.memory().interceptWith(hold));
    addTearDown(db.close);
    final cache = _Cache(db);
    final server = ServerId('parallel-server');
    final held = cache.putIfCurrent(server, '/held', {'title': 'A'}, () => true);
    await hold.entered.future;
    final otherPublished = Completer<void>();
    final others = [
      for (var n = 0; n < 32; n++)
        cache.putIfCurrent(server, '/other/$n', {'title': 'other'}, () => true).then((_) {
          if (!otherPublished.isCompleted) otherPublished.complete();
        }),
    ];
    Object? failure;
    try {
      await otherPublished.future.timeout(const Duration(seconds: 2));
    } catch (error) {
      failure = error;
    }
    hold.release.complete();
    await Future.wait([held, ...others]);
    expect(failure, isNull, reason: 'one key must not block the entire cache');
  });

  test('a failed encoder or throwing guard releases its publication order', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final broken = _Cache(db, encoder: (_) async => throw StateError('synthetic encode failure'));
    final cache = _Cache(db);
    final server = ServerId('failed-server');
    await expectLater(broken.putIfCurrent(server, '/same', {}, () => true), throwsStateError);
    await expectLater(
      cache.putIfCurrent(server, '/same', {}, () => throw StateError('synthetic guard failure')),
      throwsStateError,
    );
    await cache.putIfCurrent(server, '/same', {'title': 'survives'}, () => true);
    expect((await cache.get(server, '/same'))!['title'], 'survives');
  });

  test('guard observes context after encoding; ordinary put retains its behavior', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final entered = Completer<void>(), release = Completer<void>();
    var current = true;
    final cache = _Cache(
      db,
      encoder: (data) async {
        entered.complete();
        await release.future;
        return jsonEncode(data);
      },
    );
    final server = ServerId('context-server');
    final pending = cache.putIfCurrent(server, '/cancelled', {'title': 'stale'}, () => current);
    await entered.future;
    current = false;
    release.complete();
    await pending;
    expect(await cache.get(server, '/cancelled'), isNull);
    await _Cache(db).put(server, '/ordinary', {'title': 'legacy behavior'});
    expect((await cache.get(server, '/ordinary'))!['title'], 'legacy behavior');
  });
}
