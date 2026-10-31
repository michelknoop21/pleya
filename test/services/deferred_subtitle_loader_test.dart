import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/deferred_subtitle.dart';
import 'package:pleya/services/deferred_subtitle_loader.dart';
import 'package:pleya/utils/media_server_http_client.dart' show AbortController;

void main() {
  late Directory root;
  late List<File> attached;
  late DeferredSubtitleLoader loader;
  var fileCount = 0;

  File newFile() => File('${root.path}/${fileCount++}.srt')..writeAsStringSync('caption');

  setUp(() {
    root = Directory.systemTemp.createTempSync('pleya-deferred-');
    attached = [];
    loader = DeferredSubtitleLoader(attach: (file, _) async => attached.add(file));
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// Gives the fire-and-forget delete of the loader a turn.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  /// That delete runs on the IO pool, so a fixed pause fails on a busy machine.
  Future<void> expectDeleted(File file) async {
    for (var i = 0; i < 500 && file.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(file.existsSync(), isFalse);
  }

  test('prepares, then attaches the file without a viewer action', () async {
    addTearDown(loader.dispose);
    final gate = Completer<File>();
    final run = loader.start(DeferredSubtitle(load: (_) => gate.future));
    expect(loader.status, DeferredSubtitleStatus.preparing);
    final file = newFile();
    gate.complete(file);
    await run;
    expect(loader.status, DeferredSubtitleStatus.idle);
    expect(attached, [file]);
    expect(file.existsSync(), isTrue);
  });

  test('holds the attach until the player has a file loaded', () async {
    addTearDown(loader.dispose);
    final ready = Completer<void>();
    final file = newFile();
    final run = loader.start(DeferredSubtitle(load: (_) async => file), ready: ready.future);
    await settle();
    expect(attached, isEmpty);
    ready.complete();
    await run;
    expect(attached, [file]);
  });

  test('another track aborts the wait and removes a late file', () async {
    addTearDown(loader.dispose);
    final gate = Completer<File>();
    AbortController? first;
    final run = loader.start(
      DeferredSubtitle(
        load: (abort) {
          first = abort;
          return gate.future;
        },
      ),
    );
    final next = newFile();
    await loader.start(DeferredSubtitle(load: (_) async => next));
    expect(first!.isAborted, isTrue);
    final late = newFile();
    gate.complete(late);
    await run;
    await settle();
    expect(attached, [next]);
    await expectDeleted(late);
  });

  test('turning the track off removes the file', () async {
    addTearDown(loader.dispose);
    final file = newFile();
    await loader.start(DeferredSubtitle(load: (_) async => file));
    await loader.start(null);
    await settle();
    await expectDeleted(file);
    expect(loader.status, DeferredSubtitleStatus.idle);
  });

  test('leaving the player removes the attached file', () async {
    final file = newFile();
    await loader.start(DeferredSubtitle(load: (_) async => file));
    loader.dispose();
    await settle();
    await expectDeleted(file);
  });

  test('leaving the player aborts the wait and removes a late file', () async {
    final gate = Completer<File>();
    AbortController? pending;
    final run = loader.start(
      DeferredSubtitle(
        load: (abort) {
          pending = abort;
          return gate.future;
        },
      ),
    );
    loader.dispose();
    expect(pending!.isAborted, isTrue);
    final late = newFile();
    gate.complete(late);
    await run;
    await settle();
    await expectDeleted(late);
  });

  test('a failure offers a retry that runs the same track again', () async {
    addTearDown(loader.dispose);
    var calls = 0;
    final file = newFile();
    final subtitle = DeferredSubtitle(
      load: (_) async {
        calls++;
        if (calls == 1) throw StateError('502');
        return file;
      },
    );
    var clock = DateTime.utc(2026, 10, 31);
    final later = DeferredSubtitleLoader(attach: (file, _) async => attached.add(file), now: () => clock);
    addTearDown(later.dispose);
    await later.start(subtitle);
    expect(later.status, DeferredSubtitleStatus.failed);
    clock = clock.add(deferredSubtitleFailureMemory);
    later.retry();
    await settle();
    expect(calls, 2);
    expect(later.status, DeferredSubtitleStatus.idle);
    expect(attached, [file]);
  });

  group('retry within the time the server remembers a failure', () {
    test('waits out what is left, and shows the preparation meanwhile', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 10, 31);
        final delayed = DeferredSubtitleLoader(attach: (_, _) async {}, now: () => start.add(async.elapsed));
        var calls = 0;
        final subtitle = DeferredSubtitle(
          load: (_) async {
            calls++;
            throw StateError('502');
          },
        );
        unawaited(delayed.start(subtitle));
        async.flushMicrotasks();
        expect(calls, 1);
        expect(delayed.status, DeferredSubtitleStatus.failed);

        async.elapse(const Duration(seconds: 5));
        delayed.retry();
        async.flushMicrotasks();
        expect(delayed.status, DeferredSubtitleStatus.preparing);
        async.elapse(const Duration(seconds: 9));
        expect(calls, 1, reason: 'the server would answer its remembered 502');
        async.elapse(const Duration(seconds: 1));
        expect(calls, 2);
        delayed.dispose();
      });
    });

    test('does not wait once that time has passed', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 10, 31);
        final delayed = DeferredSubtitleLoader(attach: (_, _) async {}, now: () => start.add(async.elapsed));
        var calls = 0;
        final subtitle = DeferredSubtitle(
          load: (_) async {
            calls++;
            throw StateError('502');
          },
        );
        unawaited(delayed.start(subtitle));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 20));
        delayed.retry();
        async.flushMicrotasks();
        expect(calls, 2);
        delayed.dispose();
      });
    });

    test('another track ends the wait', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 10, 31);
        final delayed = DeferredSubtitleLoader(attach: (_, _) async {}, now: () => start.add(async.elapsed));
        var calls = 0;
        final failing = DeferredSubtitle(
          load: (_) async {
            calls++;
            throw StateError('502');
          },
        );
        unawaited(delayed.start(failing));
        async.flushMicrotasks();
        delayed.retry();
        async.flushMicrotasks();
        unawaited(delayed.start(null));
        async.elapse(const Duration(seconds: 20));
        expect(calls, 1);
        expect(delayed.status, DeferredSubtitleStatus.idle);
        delayed.dispose();
      });
    });
  });

  test('an attach the player refuses fails the track and removes the file', () async {
    final refused = newFile();
    final failing = DeferredSubtitleLoader(attach: (_, _) async => throw StateError('mpv refused'));
    addTearDown(failing.dispose);
    await failing.start(DeferredSubtitle(load: (_) async => refused));
    await settle();
    expect(failing.status, DeferredSubtitleStatus.failed);
    await expectDeleted(refused);
  });

  test('abortPending leaves an attached track alone', () async {
    addTearDown(loader.dispose);
    final file = newFile();
    await loader.start(DeferredSubtitle(load: (_) async => file));
    loader.abortPending();
    await settle();
    expect(file.existsSync(), isTrue);
  });

  test('reattach gives a new backend the same file', () async {
    addTearDown(loader.dispose);
    final file = newFile();
    await loader.start(DeferredSubtitle(load: (_) async => file));
    await loader.reattach();
    expect(attached, [file, file]);
  });
}
