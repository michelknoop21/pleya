import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pleya/services/image_cache_service.dart';

/// A transport whose requests never answer, like a socket tvOS dropped while
/// the app was suspended. It only lets go when the request is aborted.
class _DeadTransport extends http.BaseClient {
  int sent = 0;
  int aborted = 0;

  /// Requests from this index on answer normally.
  int answerFrom = 1 << 30;

  /// When set, an answering request sends headers and then a body that stalls.
  bool stallBody = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final index = sent++;
    final trigger = (request as http.Abortable).abortTrigger!;
    if (index >= answerFrom) {
      if (stallBody) {
        final body = StreamController<List<int>>();
        body.add(const [1, 2, 3]);
        unawaited(
          trigger.then((_) {
            aborted++;
            body.addError(http.RequestAbortedException(request.url));
            body.close();
          }),
        );
        return Future.value(http.StreamedResponse(body.stream, 200));
      }
      return Future.value(http.StreamedResponse(Stream.value(const [1, 2, 3]), 200));
    }
    final answer = Completer<http.StreamedResponse>();
    unawaited(
      trigger.then((_) {
        aborted++;
        answer.completeError(http.RequestAbortedException(request.url));
      }),
    );
    return answer.future;
  }
}

void main() {
  final poster = Uri.parse('https://media.example/library/metadata/1/thumb?X-Plex-Token=secret');

  setUp(() {
    artworkHeaderTimeout = const Duration(milliseconds: 40);
    artworkBodyIdleTimeout = const Duration(milliseconds: 40);
  });
  tearDown(() {
    artworkHeaderTimeout = const Duration(seconds: 15);
    artworkBodyIdleTimeout = const Duration(seconds: 20);
  });

  test('a download that never answers gives up, aborts its request and frees its slot', () async {
    final transport = _DeadTransport();
    final client = PlexImageCacheManager.debugHttpClient(transport);

    await expectLater(client.send(http.Request('GET', poster)), throwsA(isA<TimeoutException>()));
    await pumpEventQueue();

    expect(transport.aborted, 1);
    expect(PlexImageCacheManager.debugInFlightDownloads, 0);
  });

  test('dead downloads no longer block every later image', () async {
    final transport = _DeadTransport()..answerFrom = 6;
    // Six is the whole budget: before the timeout these six held their slots
    // for good and the seventh request waited until the app was restarted.
    final dead = [
      for (var i = 0; i < 6; i++)
        PlexImageCacheManager.debugHttpClient(
          transport,
        ).send(http.Request('GET', poster)).then<Object?>((r) => r, onError: (Object e) => e),
    ];
    final seventh = PlexImageCacheManager.debugHttpClient(transport).send(http.Request('GET', poster));

    final response = await seventh.timeout(const Duration(seconds: 2));
    expect(response.statusCode, 200);
    await response.stream.drain<void>();
    expect(await Future.wait(dead), everyElement(isA<TimeoutException>()));
    expect(PlexImageCacheManager.debugInFlightDownloads, 0);
  });

  test('a body that stops arriving is cut off', () async {
    final transport = _DeadTransport()
      ..answerFrom = 0
      ..stallBody = true;
    final response = await PlexImageCacheManager.debugHttpClient(transport).send(http.Request('GET', poster));

    await expectLater(response.stream.drain<void>(), throwsA(isA<TimeoutException>()));
    await pumpEventQueue();

    expect(transport.aborted, 1);
    expect(PlexImageCacheManager.debugInFlightDownloads, 0);
  });

  test('a resume aborts what was in flight during the suspend, and nothing newer', () async {
    artworkHeaderTimeout = const Duration(seconds: 30);
    final transport = _DeadTransport();
    var reloads = 0;
    void onReload() => reloads++;
    ArtworkReloadSignal.instance.addListener(onReload);
    addTearDown(() => ArtworkReloadSignal.instance.removeListener(onReload));

    final before = PlexImageCacheManager.debugHttpClient(transport).send(http.Request('GET', poster));
    final beforeResult = before.then<Object?>((r) => r, onError: (Object e) => e);
    await pumpEventQueue();
    markArtworkDownloadsSuspended();
    final after = PlexImageCacheManager.debugHttpClient(transport).send(http.Request('GET', poster));
    final afterResult = after.then<Object?>((r) => r, onError: (Object e) => e);
    await pumpEventQueue();

    expect(abortArtworkDownloadsFromBeforeSuspend(), 1);
    expect(await beforeResult, isA<http.RequestAbortedException>());
    expect(transport.aborted, 1);
    expect(
      PlexImageCacheManager.debugInFlightDownloads,
      1,
      reason: 'the request started after the suspend is still running',
    );
    expect(reloads, 1);

    // Leave nothing behind for the next test.
    artworkHeaderTimeout = Duration.zero;
    markArtworkDownloadsSuspended();
    abortArtworkDownloadsFromBeforeSuspend();
    expect(await afterResult, isA<http.RequestAbortedException>());
    expect(PlexImageCacheManager.debugInFlightDownloads, 0);
  });

  test('closing after an answer nobody reads lets go of its connection', () async {
    // CE throws on a 404 before it reads the body. On the dart:io client an
    // unread body stays paused and keeps its connection out of the pool.
    var listened = false;
    var cancelled = false;
    final body = StreamController<List<int>>(onListen: () => listened = true, onCancel: () => cancelled = true);
    final client = PlexImageCacheManager.debugHttpClient(
      MockStreamClient((_) async => http.StreamedResponse(body.stream, 404)),
    );

    final response = await client.send(http.Request('GET', poster));
    expect(response.statusCode, 404);
    client.close();
    await pumpEventQueue();

    expect(listened, isTrue);
    expect(cancelled, isTrue);
    expect(PlexImageCacheManager.debugInFlightDownloads, 0);
  });
}

class MockStreamClient extends http.BaseClient {
  MockStreamClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _handler(request);
}
