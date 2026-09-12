import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/utils/managed_http_client.dart';

/// Records when the inner client is actually torn down, the only externally
/// observable signal of when `_tryCloseInner` ran.
class _SpyClient extends http.BaseClient {
  _SpyClient(this._inner);
  final http.Client _inner;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _inner.send(request);

  @override
  void close() {
    closed = true;
    _inner.close();
  }
}

void main() {
  test('a cancel failure during the hard close is logged, not thrown as an unhandled error', () {
    fakeAsync((async) {
      // A response that arrives *after* the hard-close deadline is already
      // armed (a request `_abortActive` could only no-op on, since it had
      // nothing to cancel yet) and whose subscription then fails to cancel —
      // the concurrent-teardown race the class's own docs describe. Nothing
      // ever subscribes to it, so the hard close's own forced cancel
      // (`_scheduleHardClose`) is the only thing that ever touches it.
      final rawController = StreamController<List<int>>(onCancel: () => Future<void>.error(Exception('boom')));
      addTearDown(() => rawController.close());
      final responseCompleter = Completer<http.StreamedResponse>();
      final inner = MockClient.streaming((request, body) => responseCompleter.future);
      final client = ManagedHttpClient(inner, debugLabel: 'test');

      final zoneErrors = <Object>[];
      runZonedGuarded(() {
        unawaited(client.send(http.Request('GET', Uri.parse('https://example.test'))));
        async.flushMicrotasks();

        unawaited(
          client.closeGracefully(
            drainTimeout: const Duration(milliseconds: 1),
            hardCloseDeadline: const Duration(seconds: 30),
          ),
        );
        async.elapse(const Duration(seconds: 1));

        responseCompleter.complete(http.StreamedResponse(rawController.stream, 200));
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 30));
      }, (error, stack) => zoneErrors.add(error));

      expect(zoneErrors, isEmpty);
    });
  });

  test('a second closeGracefully call does not reset an already-armed hard-close deadline', () {
    fakeAsync((async) {
      // A request that never reports back at all (send() itself never
      // resolves) — `_abortActive` then resolves immediately with nothing
      // to cancel, and the request stays active until the hard close.
      final hangingResponse = Completer<http.StreamedResponse>();
      final inner = MockClient.streaming((request, body) => hangingResponse.future);
      final spy = _SpyClient(inner);
      final client = ManagedHttpClient(spy, debugLabel: 'test');

      unawaited(client.send(http.Request('GET', Uri.parse('https://example.test'))));
      async.flushMicrotasks();

      // First close: drains for 1ms, times out, arms a 30s hard-close timer.
      unawaited(
        client.closeGracefully(
          drainTimeout: const Duration(milliseconds: 1),
          hardCloseDeadline: const Duration(seconds: 30),
        ),
      );
      async.elapse(const Duration(seconds: 10));
      expect(spy.closed, isFalse);

      // Second close, e.g. `main.dart`'s shutdown calling `closeGracefully`
      // then `ManagedHttpClient.closeAllGracefully`. It must not push the
      // deadline out to 10s + 30s.
      unawaited(
        client.closeGracefully(
          drainTimeout: const Duration(milliseconds: 1),
          hardCloseDeadline: const Duration(seconds: 30),
        ),
      );
      async.elapse(const Duration(seconds: 21)); // total: 31s since the first call

      expect(spy.closed, isTrue);
    });
  });
}
