import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/download_task_records.dart';

DownloadTask _task(String id) => DownloadTask(
  taskId: id,
  url: 'https://jf.example/Videos/abc/stream?Static=true&api_key=SECRET',
  filename: '$id.mp4',
  group: 'downloads',
);

TaskRecord _record(String id, TaskStatus status) => TaskRecord(_task(id), status, 0, -1, null);

void main() {
  late List<TaskRecord> stored;
  late List<String> deleted;
  late DownloadTaskRecords records;

  setUp(() {
    stored = [];
    deleted = [];
    records = DownloadTaskRecords(
      allRecords: (group) async => stored,
      deleteRecords: (ids) async => deleted.addAll(ids),
    );
  });

  group('purgeFinished', () {
    test('removes every final record and keeps the ones a task still needs', () async {
      stored = [for (final s in TaskStatus.values) _record(s.name, s)];

      final count = await records.purgeFinished('downloads');

      expect(deleted..sort(), ['canceled', 'complete', 'failed', 'notFound']);
      expect(count, 4);
      // A queued, running, waiting or paused task is rescheduled or resumed
      // from its record.
      expect(deleted, isNot(contains('enqueued')));
      expect(deleted, isNot(contains('running')));
      expect(deleted, isNot(contains('waitingToRetry')));
      expect(deleted, isNot(contains('paused')));
    });

    test('does nothing when there is nothing final', () async {
      stored = [_record('a', TaskStatus.running)];

      expect(await records.purgeFinished('downloads'), 0);
      expect(deleted, isEmpty);
    });

    test('a failing store is not fatal', () async {
      final broken = DownloadTaskRecords(
        allRecords: (group) async => throw StateError('storage isolate gone'),
        deleteRecords: (ids) async {},
      );

      expect(await broken.purgeFinished('downloads'), 0);
    });
  });

  group('forgetIfFinal', () {
    test('removes the record of a task that ended', () async {
      for (final s in [TaskStatus.complete, TaskStatus.failed, TaskStatus.notFound, TaskStatus.canceled]) {
        deleted.clear();
        await records.forgetIfFinal(_task('t'), s);
        expect(deleted, ['t'], reason: s.name);
      }
    });

    test('keeps the record of a task that is still going', () async {
      for (final s in [TaskStatus.enqueued, TaskStatus.running, TaskStatus.waitingToRetry, TaskStatus.paused]) {
        await records.forgetIfFinal(_task('t'), s);
      }
      expect(deleted, isEmpty);
    });

    test('a failing delete is not fatal', () async {
      final broken = DownloadTaskRecords(
        allRecords: (group) async => [],
        deleteRecords: (ids) async => throw StateError('storage isolate gone'),
      );

      await broken.forgetIfFinal(_task('t'), TaskStatus.complete);
    });
  });
}
