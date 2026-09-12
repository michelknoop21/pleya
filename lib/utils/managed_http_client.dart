import 'dart:async';

import 'package:http/http.dart' as http;

import 'app_logger.dart';

/// [http.Client] wrapper that owns native-client shutdown semantics.
///
/// `package:http` clients define closing with active requests as undefined. For
/// platform clients backed by native callbacks, especially CupertinoClient,
/// closing at the wrong time can leave callbacks racing a torn-down Dart bridge.
/// This wrapper tracks requests until their response stream finishes, aborts
/// active requests during shutdown, and only closes the inner client once the
/// active set has drained.
class ManagedHttpClient extends http.BaseClient {
  ManagedHttpClient(this._inner, {required this.debugLabel}) {
    _instances.add(this);
  }

  static final Set<ManagedHttpClient> _instances = <ManagedHttpClient>{};

  static Future<void> closeAllGracefully({Duration drainTimeout = const Duration(seconds: 5)}) async {
    await Future.wait(
      _instances.toList().map((client) => client.closeGracefully(drainTimeout: drainTimeout)),
      eagerError: false,
    );
  }

  final http.Client _inner;
  final String debugLabel;
  final Set<_TrackedRequest> _active = <_TrackedRequest>{};

  bool _closing = false;
  bool _innerClosed = false;
  Future<void>? _closeFuture;
  Timer? _hardCloseTimer;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closing) {
      throw http.ClientException('HTTP client is closing', request.url);
    }

    final tracked = _TrackedRequest(request.url);
    _active.add(tracked);
    try {
      final abortableRequest = _wrapRequest(request, tracked.abortTrigger);
      final response = await _inner.send(abortableRequest);
      return _wrapResponse(response, tracked);
    } catch (_) {
      _complete(tracked);
      rethrow;
    }
  }

  /// [hardCloseDeadline] bounds how long a request that never reports back may
  /// keep the inner client alive. A deferred close is normally repaired by the
  /// request finishing, but a platform client can hold a request that will
  /// never call back: tvOS drops every socket while the app is suspended, and
  /// the aborts sent on resume land on requests that are already gone. Without
  /// a ceiling those clients, their connection pools and their sockets are
  /// never released, and a failed endpoint race leaks one per candidate.
  Future<void> closeGracefully({
    Duration drainTimeout = const Duration(seconds: 2),
    Duration hardCloseDeadline = const Duration(seconds: 30),
  }) {
    _closing = true;
    if (_innerClosed) return Future<void>.value();

    final existing = _closeFuture;
    if (existing != null) return existing;

    final future = _closeGracefully(drainTimeout, hardCloseDeadline);
    _closeFuture = future;
    unawaited(
      future.then<void>(
        (_) {
          // Not cleared while a hard-close timer is armed: `_closeGracefully`
          // always arms one before returning when it leaves the client open,
          // so clearing here unconditionally let a second `closeGracefully()`
          // call (e.g. `main.dart`'s shutdown path, which calls this and then
          // `closeAllGracefully()`) re-enter `_closeGracefully` and cancel and
          // re-arm the timer, resetting the very deadline it exists to bound.
          if (!_innerClosed && _hardCloseTimer == null && identical(_closeFuture, future)) {
            _closeFuture = null;
          }
        },
        onError: (Object _, StackTrace _) {
          if (!_innerClosed && _hardCloseTimer == null && identical(_closeFuture, future)) {
            _closeFuture = null;
          }
        },
      ),
    );
    return future;
  }

  @override
  void close() {
    unawaited(closeGracefully());
  }

  Future<void> _closeGracefully(Duration drainTimeout, Duration hardCloseDeadline) async {
    await _abortActive();

    var drainTimedOut = false;
    if (_active.isNotEmpty) {
      try {
        await Future.wait(_active.map((request) => request.done), eagerError: false).timeout(drainTimeout);
      } on TimeoutException {
        drainTimedOut = true;
      }
    }

    _tryCloseInner();
    // One line per close instead of two. A drain timeout is always followed by
    // the deferred-close line saying the same thing about the same client, and
    // a server whose endpoints all time out closes a client per candidate — a
    // single unreachable server produced two dozen warnings that way, which
    // buries the one line that says *which* server it was.
    if (!_innerClosed) {
      appLogger.w(
        'HTTP client close deferred until active requests finish',
        error: {'client': debugLabel, 'activeRequests': _active.length, 'drainTimedOut': drainTimedOut},
      );
      _scheduleHardClose(hardCloseDeadline);
    } else if (drainTimedOut) {
      appLogger.d('HTTP client drain timed out, closed anyway', error: {'client': debugLabel});
    }
  }

  Future<void> _abortActive() async {
    await Future.wait(_active.toList().map((request) => request.cancel()), eagerError: false);
  }

  http.BaseRequest _wrapRequest(http.BaseRequest request, Future<void> managedAbortTrigger) {
    final requestAbortTrigger = request is http.Abortable ? request.abortTrigger : null;
    final abortTrigger = requestAbortTrigger == null
        ? managedAbortTrigger
        : Future.any<void>([managedAbortTrigger, requestAbortTrigger]);
    final body = request.finalize();

    final abortable = http.AbortableStreamedRequest(request.method, request.url, abortTrigger: abortTrigger)
      ..headers.addAll(request.headers)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection
      ..contentLength = request.contentLength;

    unawaited(
      body.pipe(abortable.sink).catchError((Object e, StackTrace st) {
        appLogger.d('HTTP request body pipe failed', error: e, stackTrace: st);
      }),
    );
    return abortable;
  }

  http.StreamedResponse _wrapResponse(http.StreamedResponse response, _TrackedRequest tracked) {
    late final StreamController<List<int>> controller;
    StreamSubscription<List<int>>? subscription;
    var subscribed = false;
    var cancelledBeforeListen = false;

    Future<void> cancelResponse() async {
      if (tracked.isDone) return;
      tracked.abort();
      cancelledBeforeListen = !subscribed;
      if (subscribed) {
        await subscription?.cancel();
      } else {
        final cancelSubscription = response.stream.listen(null, onError: (_) {});
        await cancelSubscription.cancel();
      }
      unawaited(controller.close());
      _complete(tracked);
    }

    controller = StreamController<List<int>>(
      sync: true,
      onListen: () {
        if (cancelledBeforeListen) {
          unawaited(controller.close());
          return;
        }
        subscribed = true;
        subscription = response.stream.listen(
          controller.add,
          onError: controller.addError,
          onDone: () {
            _complete(tracked);
            unawaited(controller.close());
          },
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () async {
        tracked.abort();
        await subscription?.cancel();
        _complete(tracked);
      },
    );

    tracked.cancelResponse = cancelResponse;

    if (response case http.BaseResponseWithUrl(:final url)) {
      return _ManagedStreamedResponseWithUrl(
        controller.stream,
        response.statusCode,
        url: url,
        contentLength: response.contentLength,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    }

    return http.StreamedResponse(
      controller.stream,
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  void _complete(_TrackedRequest tracked) {
    if (!_active.remove(tracked)) return;
    tracked.complete();
    if (_closing && _active.isEmpty) {
      _tryCloseInner();
    }
  }

  /// Drop requests that never reported back and close anyway. Dropping them
  /// first keeps [_tryCloseInner]'s "no active requests" rule as the single
  /// gate on closing.
  void _scheduleHardClose(Duration deadline) {
    _hardCloseTimer?.cancel();
    _hardCloseTimer = Timer(deadline, () {
      _hardCloseTimer = null;
      if (_innerClosed) return;
      appLogger.w(
        'HTTP client force-closed after its drain deadline',
        error: {'client': debugLabel, 'abandonedRequests': _active.length},
      );
      final abandoned = _active.toList();
      _active.clear();
      for (final tracked in abandoned) {
        unawaited(
          tracked.cancel().catchError((Object e, StackTrace st) {
            appLogger.d('HTTP request cancel failed during hard close', error: e, stackTrace: st);
          }),
        );
      }
      _tryCloseInner();
    });
  }

  void _tryCloseInner() {
    if (_innerClosed || _active.isNotEmpty) return;
    try {
      _inner.close();
      _innerClosed = true;
      _hardCloseTimer?.cancel();
      _hardCloseTimer = null;
      _instances.remove(this);
    } catch (e, st) {
      appLogger.w('HTTP client close failed', error: e, stackTrace: st);
    }
  }
}

class _ManagedStreamedResponseWithUrl extends http.StreamedResponse implements http.BaseResponseWithUrl {
  _ManagedStreamedResponseWithUrl(
    super.stream,
    super.statusCode, {
    required this.url,
    super.contentLength,
    super.request,
    super.headers,
    super.isRedirect,
    super.persistentConnection,
    super.reasonPhrase,
  });

  @override
  final Uri url;
}

class _TrackedRequest {
  _TrackedRequest(this.url);

  final Uri url;
  final Completer<void> _abortCompleter = Completer<void>();
  final Completer<void> _doneCompleter = Completer<void>();

  Future<void> get abortTrigger => _abortCompleter.future;
  Future<void> get done => _doneCompleter.future;
  bool get isDone => _doneCompleter.isCompleted;

  Future<void> Function()? cancelResponse;

  void abort() {
    if (!_abortCompleter.isCompleted) _abortCompleter.complete();
  }

  Future<void> cancel() async {
    abort();
    await cancelResponse?.call();
  }

  void complete() {
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
  }
}
