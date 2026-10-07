import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/utils/persistent_log_store.dart';

void main() {
  late Directory directory;
  setUp(() async => directory = await Directory.systemTemp.createTemp('pleya-log-test-'));
  tearDown(() async => directory.delete(recursive: true));

  test('restores logs after a new store instance and ignores a partial last line', () async {
    final store = PersistentLogStore(directory);
    store.add({'message': 'before restart'});
    await store.flush();
    await File('${directory.path}/current.jsonl').writeAsString('{"message":', mode: FileMode.append);
    final restarted = PersistentLogStore(directory);
    expect(await restarted.read(), [
      {'message': 'before restart'},
    ]);
    restarted.add({'message': 'after restart'});
    await restarted.flush();
    expect((await PersistentLogStore(directory).read()).last['message'], 'after restart');
  });

  test('recovers from an interrupted UTF-8 character and continues recording', () async {
    final store = PersistentLogStore(directory);
    store.add({'message': 'saved'});
    await store.flush();
    await File('${directory.path}/current.jsonl').writeAsBytes([0xe2, 0x82], mode: FileMode.append);
    final restarted = PersistentLogStore(directory);
    expect((await restarted.read()).single['message'], 'saved');
    restarted.add({'message': 'recovered'});
    await restarted.flush();
    expect((await PersistentLogStore(directory).read()).last['message'], 'recovered');
  });

  test('rotation bounds disk usage and preserves the newest entries', () async {
    final store = PersistentLogStore(directory, maxFileBytes: 80);
    for (var i = 0; i < 20; i++) {
      store.add({'message': 'entry $i'});
    }
    store.add({'message': 'x' * 100});
    await store.flush();
    final saved = await PersistentLogStore(directory).read();
    expect(saved.last['message'], 'entry 19');
    expect(saved.first['message'], isNot('entry 0'));
    var bytes = 0;
    await for (final file in directory.list()) {
      bytes += await File(file.path).length();
    }
    expect(bytes, lessThanOrEqualTo(160));
  });

  test('clear removes queued and written logs, allowing subsequent writes', () async {
    final store = PersistentLogStore(directory);
    store.add({'message': 'written'});
    final writing = store.flush();
    store.add({'message': 'pending'});
    await store.clear();
    await writing;
    expect(await PersistentLogStore(directory).read(), isEmpty);
    store.add({'message': 'new'});
    await store.flush();
    expect(await PersistentLogStore(directory).read(), [
      {'message': 'new'},
    ]);
  });
}
