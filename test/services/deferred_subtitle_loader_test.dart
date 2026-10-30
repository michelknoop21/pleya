import 'dart:async';
import 'dart:io';

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
    expect(late.existsSync(), isFalse);
  });

  test('turning the track off removes the file', () async {
    addTearDown(loader.dispose);
    final file = newFile();
    await loader.start(DeferredSubtitle(load: (_) async => file));
    await loader.start(null);
    await settle();
    expect(file.existsSync(), isFalse);
    expect(loader.status, DeferredSubtitleStatus.idle);
  });

  test('leaving the player removes the attached file', () async {
    final file = newFile();
    await loader.start(DeferredSubtitle(load: (_) async => file));
    loader.dispose();
    await settle();
    expect(file.existsSync(), isFalse);
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
    expect(late.existsSync(), isFalse);
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
    await loader.start(subtitle);
    expect(loader.status, DeferredSubtitleStatus.failed);
    loader.retry();
    await settle();
    expect(calls, 2);
    expect(loader.status, DeferredSubtitleStatus.idle);
    expect(attached, [file]);
  });

  test('an attach the player refuses fails the track and removes the file', () async {
    final refused = newFile();
    final failing = DeferredSubtitleLoader(attach: (_, _) async => throw StateError('mpv refused'));
    addTearDown(failing.dispose);
    await failing.start(DeferredSubtitle(load: (_) async => refused));
    await settle();
    expect(failing.status, DeferredSubtitleStatus.failed);
    expect(refused.existsSync(), isFalse);
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
