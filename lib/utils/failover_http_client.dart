import 'dart:async';

import 'endpoint_failover_interceptor.dart';
import 'app_logger.dart';
import 'media_server_http_client.dart';
import 'media_server_timeouts.dart';
import '../exceptions/media_server_exceptions.dart';

/// [MediaServerHttpClient] with endpoint failover, shared by both backends
/// (the single implementation of what used to be `PlexClient._getWithFailover`
/// and `_JellyfinFailoverHttpClient`).
///
/// Semantics — decided once, here ([retryTransientMediaServerCall]'s doc
/// cross-references this):
///
/// - **Failover is GET-only.** Mutations (POST/PUT/DELETE) fail fast on both
///   backends: replaying a mutation against a second endpoint when the first
///   was flaky-but-alive risks double-application, and no caller needs it.
/// - **Trigger:** a transient transport failure
///   ([MediaServerHttpException.isTransient]) or a 5xx — whether thrown or
///   returned as a response. 4xx answers never trigger failover.
/// - **One cascade at a time, over the whole list.** The first failure on
///   the active endpoint walks every other endpoint (preferred-first) until
///   one answers; only when all of them failed does the list reset to the
///   preferred endpoint and [onAllEndpointsExhausted] fire. Requests that
///   fail while a cascade runs, or after the endpoint moved under them, wait
///   for it and retry once on the endpoint it settled on: they never start a
///   second cascade or report exhaustion themselves.
/// - **Persistence is two-phase:** the switch is applied with
///   `persist: false` for the retry, and only a successful retry persists the
///   winner (`persist: true`).
/// - **Retry interplay:** [retryTransientMediaServerCall] is for
///   *slow-but-working* endpoints (per-surface timeout budgets); surfaces
///   that wrap it pass `allowEndpointFailover: false` so a slow row doesn't
///   move the whole client off an otherwise working endpoint. Failover is for
///   *dead* endpoints.
class FailoverHttpClient extends MediaServerHttpClient {
  /// [prioritizedEndpoints] may be empty (failover disabled — plain client
  /// behavior). A single-entry list still arms [onAllEndpointsExhausted]:
  /// the lone endpoint failing *is* exhaustion, and the owning manager uses
  /// that to flip server status and reconnect.
  FailoverHttpClient({
    super.client,
    required super.baseUrl,
    required super.defaultHeaders,
    super.connectTimeout,
    super.receiveTimeout,
    super.usePlexApiClient,
    required this.logLabel,
    required List<String> prioritizedEndpoints,
    required this.onEndpointSwitch,
    this.onAllEndpointsExhausted,
    this.cascadeBudget = MediaServerTimeouts.connect,
  }) : _endpointManager = prioritizedEndpoints.isNotEmpty ? EndpointFailoverManager(prioritizedEndpoints) : null;

  /// Backend name for log lines ('Plex' / 'Jellyfin') — keeps failover logs
  /// greppable per backend now that the implementation is shared.
  final String logLabel;
  final EndpointFailoverManager? _endpointManager;

  /// Applies a base-URL change on the owning client. The callback must update
  /// this client's [baseUrl] alongside its own config/connection snapshot
  /// (the two-phase protocol calls it with `persist: false` before the retry
  /// and `persist: true` only after a success — persistence must not be gated
  /// on the URL having changed, since the second call sees it already applied).
  final Future<void> Function(String newBaseUrl, {required bool persist}) onEndpointSwitch;

  /// Fired when a cascade ends without a working endpoint (or the retry
  /// itself fails). The owning manager debounces this into a server-offline
  /// flip + reconnection.
  final void Function()? onAllEndpointsExhausted;

  /// Time a cascade may spend without a winner before it gives up and reports
  /// exhaustion, so the owner's parallel discovery race takes over. Fast
  /// failures (host lookup, refused) still walk the whole list within it; a
  /// blackholed server with ten endpoints no longer holds every request for
  /// nine connect timeouts.
  final Duration cascadeBudget;

  /// Endpoints currently configured, preferred-first (test/diagnostic view).
  List<String> get endpoints => _endpointManager?.endpoints ?? const [];

  /// Replace the endpoint list after a connection refresh, keeping
  /// [currentBaseUrl] active when provided (it must be present in the list).
  void resetEndpoints(List<String> prioritizedEndpoints, {String? currentBaseUrl}) {
    _endpointManager?.reset(prioritizedEndpoints, currentBaseUrl: currentBaseUrl);
  }

  @override
  Future<MediaServerResponse> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    Duration? timeout,
    AbortController? abort,
    bool allowEndpointFailover = true,
  }) async {
    final manager = allowEndpointFailover ? _endpointManager : null;
    final generation = manager?.generation;
    final requestBaseUrl = baseUrl;
    Future<MediaServerResponse> send() =>
        super.get(path, queryParameters: queryParameters, headers: headers, timeout: timeout, abort: abort);

    final MediaServerResponse response;
    try {
      response = await send();
    } on MediaServerHttpException catch (e, st) {
      if (manager == null || !_shouldAttemptFailover(exception: e)) rethrow;
      final recovered = await _recover(manager, generation!, requestBaseUrl, path, send);
      if (recovered == null) Error.throwWithStackTrace(e, st);
      return recovered;
    }
    if (manager == null || !_shouldAttemptFailover(statusCode: response.statusCode)) return response;
    return await _recover(manager, generation!, requestBaseUrl, path, send) ?? response;
  }

  /// Completes when the running cascade has settled on an endpoint (or
  /// exhausted the list). Requests failing meanwhile wait for it instead of
  /// starting their own cascade.
  Future<void>? _activeCascade;

  /// A request that failed on [requestBaseUrl] while stamped with
  /// [requestGeneration]. Only the first failure on the active endpoint runs a
  /// cascade; a request that raced one (it failed while a cascade ran, or the
  /// endpoint moved after it started) gets one retry on whatever endpoint is
  /// active now, and never fires [onAllEndpointsExhausted] itself.
  Future<MediaServerResponse?> _recover(
    EndpointFailoverManager manager,
    int requestGeneration,
    String requestBaseUrl,
    String path,
    Future<MediaServerResponse> Function() send,
  ) async {
    final active = _activeCascade;
    if (active != null || requestGeneration != manager.generation) {
      if (active != null) await active;
      if (baseUrl == requestBaseUrl) return null;
      return send();
    }
    final done = Completer<void>();
    _activeCascade = done.future;
    try {
      return await _cascade(manager, requestBaseUrl, path, send);
    } finally {
      _activeCascade = null;
      done.complete();
    }
  }

  /// Try every other endpoint, preferred-first, until one answers or
  /// [cascadeBudget] runs out.
  ///
  /// The first answer below 500 ends the cascade: a 2xx/3xx persists the
  /// winner, a 4xx is returned as-is (the endpoint is alive, so the server is
  /// not offline). Only when every alternative failed does the list reset to
  /// the preferred endpoint and [onAllEndpointsExhausted] fire; the last
  /// failure is then surfaced (a 5xx response is returned, a transport error
  /// rethrown). Returns `null` when there is no alternative at all.
  Future<MediaServerResponse?> _cascade(
    EndpointFailoverManager manager,
    String failedBaseUrl,
    String path,
    Future<MediaServerResponse> Function() send,
  ) async {
    MediaServerResponse? lastResponse;
    Object? lastError;
    StackTrace? lastStack;
    var from = failedBaseUrl;
    var expectedGeneration = manager.generation;
    bool current() => manager.generation == expectedGeneration;
    final elapsed = Stopwatch()..start();
    for (final next in manager.alternativesTo(failedBaseUrl)) {
      if (!current()) return null;
      // ponytail: checked between attempts, so one attempt started just
      // inside the budget can overrun it by its own timeout.
      if (elapsed.elapsed > cascadeBudget) {
        appLogger.i('$logLabel endpoint cascade out of time', error: {'elapsedMs': elapsed.elapsedMilliseconds});
        break;
      }
      appLogger.i('Switching $logLabel endpoint after GET failure', error: {'from': from, 'to': next, 'path': path});
      from = next;
      manager.switchTo(next);
      expectedGeneration = manager.generation;
      await onEndpointSwitch(next, persist: false);
      if (!current()) return null;
      try {
        final response = await send();
        if (!current()) return null;
        if (response.statusCode >= 500) {
          lastResponse = response;
          lastError = null;
          continue;
        }
        if (response.statusCode < 400) {
          appLogger.i('$logLabel endpoint failover retry succeeded', error: {'newEndpoint': next});
          await onEndpointSwitch(next, persist: true);
          if (!current()) return null;
        }
        return response;
      } on MediaServerHttpException catch (e, st) {
        // Cancelled, or the endpoint answered with a thrown 4xx: not an
        // endpoint failure, so no exhaustion either.
        if (!_shouldAttemptFailover(exception: e)) rethrow;
        if (!current()) return null;
        lastResponse = null;
        lastError = e;
        lastStack = st;
      }
    }
    if (!current()) return null;
    final resetBaseUrl = manager.resetToFirst();
    expectedGeneration = manager.generation;
    if (resetBaseUrl != null) {
      await onEndpointSwitch(resetBaseUrl, persist: false);
      if (!current()) return null;
    }
    onAllEndpointsExhausted?.call();
    if (lastError != null) Error.throwWithStackTrace(lastError, lastStack!);
    return lastResponse;
  }

  bool _shouldAttemptFailover({MediaServerHttpException? exception, int? statusCode}) {
    if (exception != null) {
      if (exception.isTransient) return true;
      statusCode = exception.statusCode;
    }
    return statusCode != null && statusCode >= 500 && statusCode <= 599;
  }
}
