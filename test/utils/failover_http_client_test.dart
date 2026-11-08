import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/utils/failover_http_client.dart';

/// Pins the shared failover semantics both backends now ride on (see the
/// class doc): GET-only single-step cascades, generation stamping, two-phase
/// persistence, and exhaustion behavior. Backend-level coverage lives in
/// jellyfin_client_failures_test.dart's failover group.
void main() {
  const primary = 'https://primary.example.com';
  const fallback = 'https://fallback.example.com';

  http.Response ok([String id = 'ok']) =>
      http.Response(jsonEncode({'id': id}), 200, headers: {'content-type': 'application/json'});

  ({FailoverHttpClient client, List<({String url, bool persist})> switches, List<String> exhausted, List<Uri> requests})
  build({
    required Future<http.Response> Function(http.Request request, List<Uri> seen) handler,
    List<String> endpoints = const [primary, fallback],
    Duration? cascadeBudget,
  }) {
    final switches = <({String url, bool persist})>[];
    final exhausted = <String>[];
    final requests = <Uri>[];
    late FailoverHttpClient client;
    client = FailoverHttpClient(
      baseUrl: endpoints.isEmpty ? primary : endpoints.first,
      defaultHeaders: const {},
      logLabel: 'Test',
      prioritizedEndpoints: endpoints,
      client: MockClient((request) {
        requests.add(request.url);
        return handler(request, requests);
      }),
      onEndpointSwitch: (newBaseUrl, {required persist}) async {
        switches.add((url: newBaseUrl, persist: persist));
        // Mirror the real adapters: the callback owns applying the switch.
        client.baseUrl = newBaseUrl;
      },
      onAllEndpointsExhausted: () => exhausted.add('x'),
      cascadeBudget: cascadeBudget ?? const Duration(seconds: 10),
    );
    addTearDown(client.close);
    return (client: client, switches: switches, exhausted: exhausted, requests: requests);
  }

  test('transient failure switches once and persists the winner', () async {
    final h = build(
      handler: (request, _) async {
        if (request.url.host == 'primary.example.com') throw TimeoutException('down');
        return ok();
      },
    );

    final response = await h.client.get('/path');

    expect(response.statusCode, 200);
    expect(h.requests.map((u) => u.host), ['primary.example.com', 'fallback.example.com']);
    expect(h.switches, [(url: fallback, persist: false), (url: fallback, persist: true)]);
    expect(h.exhausted, isEmpty);
    expect(h.client.baseUrl, fallback);
  });

  test('5xx response (not thrown) also triggers the cascade', () async {
    final h = build(
      handler: (request, _) async {
        if (request.url.host == 'primary.example.com') return http.Response('boom', 503);
        return ok();
      },
    );

    final response = await h.client.get('/path');

    expect(response.statusCode, 200);
    expect(h.switches.last.persist, isTrue);
  });

  test('4xx answers never fail over', () async {
    final h = build(handler: (request, _) async => http.Response('nope', 404));

    final response = await h.client.get('/path');

    expect(response.statusCode, 404);
    expect(h.requests, hasLength(1));
    expect(h.switches, isEmpty);
    expect(h.exhausted, isEmpty);
  });

  test('allowEndpointFailover: false rethrows without switching', () async {
    final h = build(handler: (request, _) async => throw TimeoutException('down'));

    await expectLater(
      h.client.get('/path', allowEndpointFailover: false),
      throwsA(isA<MediaServerHttpException>().having((e) => e.isTransient, 'isTransient', isTrue)),
    );
    expect(h.requests, hasLength(1));
    expect(h.switches, isEmpty);
    expect(h.exhausted, isEmpty);
  });

  test('exhaustion resets to preferred, fires the callback, rethrows the retry failure', () async {
    final h = build(handler: (request, _) async => throw TimeoutException('all down'));

    await expectLater(h.client.get('/path'), throwsA(isA<MediaServerHttpException>()));

    expect(h.requests.map((u) => u.host), ['primary.example.com', 'fallback.example.com']);
    // Switch to fallback for the retry, then reset back to preferred.
    expect(h.switches, [(url: fallback, persist: false), (url: primary, persist: false)]);
    expect(h.exhausted, hasLength(1));
    expect(h.client.baseUrl, primary);
  });

  test('retry answering 5xx counts as exhaustion and returns the response', () async {
    final h = build(
      handler: (request, _) async =>
          request.url.host == 'primary.example.com' ? http.Response('boom', 500) : http.Response('also boom', 502),
    );

    final response = await h.client.get('/path');

    expect(response.statusCode, 502);
    expect(h.switches, [(url: fallback, persist: false), (url: primary, persist: false)]);
    expect(h.exhausted, hasLength(1));
  });

  test('single endpoint still arms the exhausted callback', () async {
    final h = build(endpoints: const [primary], handler: (request, _) async => throw TimeoutException('down'));

    await expectLater(h.client.get('/path'), throwsA(isA<MediaServerHttpException>()));

    expect(h.requests, hasLength(1));
    expect(h.switches, isEmpty); // resetToFirst is a no-op at index 0
    expect(h.exhausted, hasLength(1));
  });

  test('no endpoints disables failover and the exhausted callback', () async {
    final h = build(endpoints: const [], handler: (request, _) async => throw TimeoutException('down'));

    await expectLater(h.client.get('/path'), throwsA(isA<MediaServerHttpException>()));

    expect(h.switches, isEmpty);
    expect(h.exhausted, isEmpty);
  });

  test('a request raced by a switch retries once on the new endpoint without cascading', () async {
    final firstRequestGate = Completer<void>();
    var primaryHits = 0;
    final h = build(
      handler: (request, _) async {
        if (request.url.host == 'primary.example.com') {
          primaryHits++;
          if (primaryHits == 1) {
            // Request A: hang until request B's cascade has completed.
            await firstRequestGate.future;
          }
          throw TimeoutException('down');
        }
        return ok();
      },
    );

    final requestA = h.client.get('/a');
    final responseB = await h.client.get('/b');
    expect(responseB.statusCode, 200);

    firstRequestGate.complete();
    // A fails after B already switched the active endpoint (generation moved):
    // it retries on the endpoint B settled on instead of cascading again.
    expect((await requestA).statusCode, 200);
    expect(h.requests.map((u) => '${u.host}${u.path}'), [
      'primary.example.com/a',
      'primary.example.com/b',
      'fallback.example.com/b',
      'fallback.example.com/a',
    ]);
    expect(h.switches, [(url: fallback, persist: false), (url: fallback, persist: true)]);
    expect(h.exhausted, isEmpty);
  });

  test('concurrent failures share one cascade and none reports exhaustion', () async {
    final release = Completer<void>();
    final fallbackGate = Completer<void>();
    final h = build(
      handler: (request, _) async {
        if (request.url.host == 'primary.example.com') {
          await release.future;
          throw http.ClientException('Connection closed before full header was received', request.url);
        }
        await fallbackGate.future;
        return ok();
      },
    );

    final a = h.client.get('/a');
    final b = h.client.get('/b');
    release.complete();
    // Let both primary requests fail while the fallback retry is still pending.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    fallbackGate.complete();

    expect((await a).statusCode, 200);
    expect((await b).statusCode, 200);
    expect(h.switches, [(url: fallback, persist: false), (url: fallback, persist: true)]);
    expect(h.exhausted, isEmpty);
    expect(h.client.baseUrl, fallback);
  });

  test('a failure on the last endpoint tries the earlier ones before exhausting', () async {
    // Hardware log: primary closed one connection, the fallback took over,
    // then one fallback request failed and the old one-step cascade (no
    // further fallback) reset to primary and reported every endpoint dead.
    var primaryFailures = 1;
    var fallbackFailures = 0;
    final h = build(
      handler: (request, _) async {
        if (request.url.host == 'primary.example.com' && primaryFailures-- > 0) {
          throw TimeoutException('connection closed');
        }
        if (request.url.host == 'fallback.example.com' && fallbackFailures-- > 0) {
          throw TimeoutException('flaky');
        }
        return ok();
      },
    );

    expect((await h.client.get('/first')).statusCode, 200);
    expect(h.client.baseUrl, fallback);

    fallbackFailures = 1;
    final response = await h.client.get('/second');

    expect(response.statusCode, 200);
    expect(h.exhausted, isEmpty);
    expect(h.client.baseUrl, primary);
    expect(h.switches.last, (url: primary, persist: true));
  });

  test('a dead alternative mid-list does not count as exhaustion while another answers', () async {
    // primary -> fallback works; later the fallback flakes, the IPv6 entry
    // cannot even resolve, but primary answers again.
    const ipv6 = 'https://ipv6.example.com';
    var primaryFailures = 1;
    var fallbackFailures = 0;
    final h = build(
      endpoints: const [primary, fallback, ipv6],
      handler: (request, _) async {
        if (request.url.host == 'ipv6.example.com') throw TimeoutException('Failed host lookup');
        if (request.url.host == 'primary.example.com' && primaryFailures-- > 0) throw TimeoutException('closed');
        if (request.url.host == 'fallback.example.com' && fallbackFailures-- > 0) throw TimeoutException('flaky');
        return ok();
      },
    );

    await h.client.get('/first');
    fallbackFailures = 1;
    final response = await h.client.get('/second');

    expect(response.statusCode, 200);
    expect(h.exhausted, isEmpty);
    expect(h.requests.map((u) => u.host).skip(2), ['fallback.example.com', 'primary.example.com']);
  });

  test('every endpoint failing in one cascade still exhausts once', () async {
    const ipv6 = 'https://ipv6.example.com';
    final h = build(
      endpoints: const [primary, fallback, ipv6],
      handler: (request, _) async => throw TimeoutException('all down'),
    );

    await expectLater(h.client.get('/path'), throwsA(isA<MediaServerHttpException>()));

    expect(h.requests.map((u) => u.host), ['primary.example.com', 'fallback.example.com', 'ipv6.example.com']);
    expect(h.exhausted, hasLength(1));
    expect(h.client.baseUrl, primary);
  });

  test('resetEndpoints replaces the cascade list', () async {
    const tertiary = 'https://tertiary.example.com';
    final h = build(
      handler: (request, _) async {
        if (request.url.host == 'tertiary.example.com') return ok();
        throw TimeoutException('down');
      },
    );

    h.client.resetEndpoints(const [fallback, tertiary], currentBaseUrl: fallback);
    h.client.baseUrl = fallback;

    final response = await h.client.get('/path');

    expect(response.statusCode, 200);
    expect(h.requests.map((u) => u.host), ['fallback.example.com', 'tertiary.example.com']);
    expect(h.switches, [(url: tertiary, persist: false), (url: tertiary, persist: true)]);
  });

  for (final staleStatus in [200, 503]) {
    test('reset during an in-flight cascade discards its stale $staleStatus response', () async {
      const removed = 'https://removed.example.com';
      const fresh = 'https://fresh.example.com';
      const freshAlternative = 'https://fresh-alternative.example.com';
      final entered = Completer<void>();
      final release = Completer<void>();
      final h = build(
        endpoints: const [primary, fallback, removed],
        handler: (request, _) async {
          if (request.url.host == 'primary.example.com') return http.Response('down', 503);
          if (request.url.host == 'fallback.example.com') {
            entered.complete();
            await release.future;
            return http.Response('stale', staleStatus);
          }
          return ok();
        },
      );
      final pending = h.client.get('/path');
      await entered.future;
      h.client.resetEndpoints(const [fresh, freshAlternative], currentBaseUrl: fresh);
      h.client.baseUrl = fresh;
      release.complete();
      expect((await pending).statusCode, 503, reason: 'surface the original failure after configuration changes');
      expect(h.requests.map((u) => u.host), ['primary.example.com', 'fallback.example.com']);
      expect(h.switches, [(url: fallback, persist: false)], reason: 'never switch or persist stale candidates');
      expect(h.exhausted, isEmpty, reason: 'an obsolete cascade cannot mark the new list offline');
      expect(h.client.baseUrl, fresh);
      expect(h.client.endpoints, [fresh, freshAlternative]);
    });
  }

  test('a cascade over slow dead endpoints gives up at its time budget', () async {
    // Blackholed server: each endpoint burns its timeout. Without a budget the
    // cascade walks all of them and every request to the server waits for it.
    final endpoints = [
      for (final name in ['primary', 'a', 'b', 'c', 'd', 'e']) 'https://$name.example.com',
    ];
    final h = build(
      endpoints: endpoints,
      cascadeBudget: const Duration(milliseconds: 100),
      handler: (request, _) async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        throw TimeoutException('blackholed');
      },
    );

    await expectLater(h.client.get('/path'), throwsA(isA<MediaServerHttpException>()));

    // primary fails, then a (~60 ms) and b (~120 ms) are tried; the budget is
    // spent before c, so the cascade stops, resets and reports exhaustion.
    expect(h.requests.map((u) => u.host), ['primary.example.com', 'a.example.com', 'b.example.com']);
    expect(h.exhausted, hasLength(1));
    expect(h.client.baseUrl, endpoints.first);
  });
}
