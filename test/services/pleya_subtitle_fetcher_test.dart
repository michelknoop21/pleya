import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/pleya_subtitle_fetcher.dart';
import 'package:pleya/utils/media_server_http_client.dart';

MediaServerResponse _answer(int status, {Object? data, String? retryAfter}) =>
    MediaServerResponse(statusCode: status, data: data, headers: {'retry-after': ?retryAfter});

void main() {
  group('pleyaRetryAfter', () {
    for (final (header, seconds) in [
      ('5', 5),
      ('7', 7),
      (' 5 ', 5),
      (null, 5),
      ('', 5),
      ('Wed, 21 Oct 2026 07:28:00 GMT', 5),
      ('-3', 5),
      ('0', 1),
      ('3600', 60),
    ]) {
      test('"$header" waits $seconds s', () => expect(pleyaRetryAfter(header), Duration(seconds: seconds)));
    }
  });

  group('fetchPleyaSubtitleWhenReady', () {
    test('repeats after Retry-After and stops at the file', () {
      fakeAsync((clock) {
        var calls = 0;
        String? text;
        unawaited(
          fetchPleyaSubtitleWhenReady(
            abort: AbortController(),
            get: (_) async {
              calls++;
              return calls < 3 ? _answer(503, retryAfter: '7') : _answer(200, data: 'caption');
            },
          ).then((value) => text = value),
        );
        clock.elapse(const Duration(seconds: 6));
        expect(calls, 1);
        clock.elapse(const Duration(seconds: 1));
        expect(calls, 2);
        clock.elapse(const Duration(seconds: 7));
        expect(calls, 3);
        expect(text, 'caption');
        expect(clock.pendingTimers, isEmpty);
      });
    });

    for (final status in [401, 404, 500, 502]) {
      test('$status ends the wait without a repeat', () async {
        var calls = 0;
        await expectLater(
          fetchPleyaSubtitleWhenReady(
            abort: AbortController(),
            get: (_) async {
              calls++;
              return _answer(status);
            },
          ),
          throwsA(isA<PleyaSubtitleUnavailable>().having((e) => e.statusCode, 'statusCode', status)),
        );
        expect(calls, 1);
      });
    }

    test('gives up after eleven minutes', () {
      fakeAsync((clock) {
        var calls = 0;
        Object? failure;
        unawaited(
          fetchPleyaSubtitleWhenReady(
            abort: AbortController(),
            get: (_) async {
              calls++;
              return _answer(503, retryAfter: '5');
            },
          ).catchError((Object e) {
            failure = e;
            return '';
          }),
        );
        clock.elapse(const Duration(minutes: 11) - const Duration(milliseconds: 1));
        expect(failure, isNull);
        final before = calls;
        expect(before, greaterThan(100));
        clock.elapse(const Duration(milliseconds: 1));
        clock.flushMicrotasks();
        expect(failure, isA<PleyaSubtitleUnavailable>());
        clock.elapse(const Duration(minutes: 1));
        expect(calls, before);
        expect(clock.pendingTimers, isEmpty);
      });
    });

    test('stops at once when the viewer chooses something else', () {
      fakeAsync((clock) {
        var calls = 0;
        final abort = AbortController();
        Object? failure;
        unawaited(
          fetchPleyaSubtitleWhenReady(
            abort: abort,
            get: (_) async {
              calls++;
              return _answer(503);
            },
          ).catchError((Object e) {
            failure = e;
            return '';
          }),
        );
        clock.elapse(const Duration(seconds: 1));
        abort.abort();
        clock.flushMicrotasks();
        expect(failure, isA<PleyaSubtitleUnavailable>());
        clock.elapse(const Duration(minutes: 1));
        expect(calls, 1);
        expect(clock.pendingTimers, isEmpty);
      });
    });
  });

  test('writes the text under its own folder with the track format', () async {
    final root = Directory.systemTemp.createTempSync('pleya-subtitle-');
    addTearDown(() => root.deleteSync(recursive: true));
    final file = await writePleyaSubtitleFile('caption', 'ass', directory: root);
    expect(file.path, startsWith('${root.path}/pleya_subtitles/'));
    expect(file.path, endsWith('.ass'));
    expect(file.readAsStringSync(), 'caption');
  });
}
