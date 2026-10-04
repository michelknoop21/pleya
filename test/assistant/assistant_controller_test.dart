import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/utils/media_server_http_client.dart' show AbortController;
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_entitlement.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/screens/big_p/big_p_mobile_session.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/seerr/seerr_client.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/seerr/seerr_session.dart';

http.Response _json(Object? body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: const {'content-type': 'application/json'});

const _config = AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://o.lan', model: 'm');

class _Entitlement extends AssistantEntitlement {
  _Entitlement([this.state = AssistantEntitlementState.entitled]);
  AssistantEntitlementState state;

  /// Holds a check back until completed.
  Completer<void>? gate;
  @override
  Future<AssistantEntitlementState> check() async {
    await gate?.future;
    return state;
  }
}

/// A model that answers from a script; a reply may be held back by a gate.
class _Model extends AssistantModelClient {
  _Model(this.script) : super(_config, httpClient: MockClient((_) async => http.Response('', 500)));
  final List<AssistantReply> script;
  Completer<void>? gate;
  var calls = 0;

  @override
  Future<AssistantReply> chat(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools, {
    AbortController? abort,
  }) async {
    await gate?.future;
    return calls < script.length ? script[calls++] : _say('klaar');
  }
}

AssistantReply _say(String text) =>
    AssistantReply(content: text, toolCalls: const [], message: {'role': 'assistant', 'content': text});

AssistantReply _call(String name, [Map<String, Object?> args = const {}]) {
  final call = AssistantToolCall(id: 'c1', name: name, arguments: jsonEncode(args));
  return AssistantReply(
    content: '',
    toolCalls: [call],
    message: {
      'role': 'assistant',
      'content': '',
      'tool_calls': [
        {
          'id': 'c1',
          'type': 'function',
          'function': {'name': name, 'arguments': call.arguments},
        },
      ],
    },
  );
}

/// A server that only needs to exist.
class _Server implements MediaServerClient {
  @override
  ServerId get serverId => ServerId('s');

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A serverless read and a serverless action behind a card.
final _ping = AssistantTool(
  name: 'ping',
  description: 'ping',
  risk: AssistantToolRisk.read,
  properties: const {},
  needsServer: false,
  serves: (_, _) => true,
  run: (_, _, _) async => const AssistantToolResult({'ok': true}),
);

var _executed = 0;
final _sensitive = AssistantTool(
  name: 'wipe',
  description: 'wipe',
  risk: AssistantToolRisk.sensitive,
  properties: const {},
  needsServer: false,
  serves: (_, _) => true,
  run: (_, _, _) async => AssistantPendingAction(
    kind: AssistantActionKind.removeUser,
    serverId: ServerId('none'),
    serverName: 'Zolder',
    subject: 'Sam',
    password: AssistantPasswordMode.optional,
    execute: ({password}) async {
      _executed++;
      return {'status': 'done', 'password_seen': password != null};
    },
  ),
);

/// Overseerr with one film, so the real find and request tools run.
SeerrClient _seerr(List<Map<String, dynamic>> posts) => SeerrClient(
  const SeerrSession(
    baseUrl: 'http://seerr.lan:5055',
    authMode: SeerrAuthMode.apiKey,
    apiKey: 'k',
    permissions: SeerrPermission.request,
  ),
  httpClient: MockClient((request) async {
    final path = request.url.path.replaceFirst('/api/v1', '');
    if (request.method == 'POST' && path == '/request') {
      posts.add(jsonDecode(request.body) as Map<String, dynamic>);
      return _json(const {'id': 1}, status: 201);
    }
    return switch (path) {
      '/search' => _json(const {
        'page': 1,
        'totalPages': 1,
        'results': [
          {'id': 603, 'mediaType': 'movie', 'title': 'The Matrix', 'releaseDate': '1999-03-31'},
        ],
      }),
      '/movie/603' => _json(const {'id': 603, 'title': 'The Matrix', 'releaseDate': '1999-03-31'}),
      _ => _json(const {'message': 'not found'}, status: 404),
    };
  }),
);

void main() {
  late MultiServerManager servers;
  SeerrClient? seerr;

  setUp(() {
    servers = MultiServerManager();
    addTearDown(servers.dispose);
    seerr = null;
    _executed = 0;
  });

  AssistantController controller({
    _Model? model,
    bool rollout = true,
    _Entitlement? entitlement,
    AssistantProviderConfig? config = _config,
    List<AssistantTool>? tools,
  }) {
    final c = AssistantController(
      buildContext: (screen) => AssistantToolContext(
        servers: servers,
        screen: screen,
        requests: AssistantRequestServices(client: () => seerr),
      ),
      rolloutEnabled: rollout,
      entitlement: entitlement ?? _Entitlement(),
      loadConfig: () async => config,
      modelFor: (_) => model ?? _Model(const []),
      languageName: () => 'Dutch',
      tools: tools,
    );
    addTearDown(c.dispose);
    return c;
  }

  test('availability matrix', () async {
    final seerrOnly = _seerr([]);
    Future<AssistantAvailability> availability(AssistantController c) async {
      await c.refreshAvailability();
      return c.availability;
    }

    seerr = seerrOnly;
    expect(await availability(controller(rollout: false)), AssistantAvailability.hidden);
    seerr = null;
    // No server and no Seerr: nothing to act on.
    expect(await availability(controller()), AssistantAvailability.hidden);
    seerr = seerrOnly;
    expect(
      await availability(controller(entitlement: _Entitlement(AssistantEntitlementState.notEntitled))),
      AssistantAvailability.locked,
    );
    expect(
      await availability(controller(entitlement: _Entitlement(AssistantEntitlementState.unknown))),
      AssistantAvailability.locked,
    );
    expect(await availability(controller(config: null)), AssistantAvailability.needsSetup);
    expect(await availability(controller(config: _config.copyWith(model: ''))), AssistantAvailability.needsSetup);
    expect(await availability(controller()), AssistantAvailability.ready);
  });

  test('servers that arrive after the first read lift hidden without a summon', () async {
    final serverChanges = ValueNotifier(0);
    AssistantProviderConfig? saved;
    final c = AssistantController(
      buildContext: (screen) => AssistantToolContext(servers: servers, screen: screen),
      rolloutEnabled: true,
      entitlement: _Entitlement(),
      loadConfig: () async => saved,
      serverChanges: serverChanges,
    );
    addTearDown(c.dispose);
    await c.refreshAvailability();
    expect(c.availability, AssistantAvailability.hidden);

    // A change with still no servers reads nothing again.
    var notified = 0;
    c.addListener(() => notified++);
    serverChanges.value++;
    await pumpEventQueue();
    expect(notified, 0);

    servers.debugRegisterClientForTesting(_Server());
    serverChanges.value++;
    await pumpEventQueue();
    expect(c.availability, AssistantAvailability.needsSetup);

    // Later changes with servers present do not read again.
    saved = _config;
    serverChanges.value++;
    await pumpEventQueue();
    expect(c.availability, AssistantAvailability.needsSetup);
  });

  test('a provider saved elsewhere moves availability out of setup', () async {
    seerr = _seerr([]);
    AssistantProviderConfig? saved;
    final c = AssistantController(
      buildContext: (screen) => AssistantToolContext(
        servers: servers,
        screen: screen,
        requests: AssistantRequestServices(client: () => seerr),
      ),
      rolloutEnabled: true,
      entitlement: _Entitlement(),
      loadConfig: () async => saved,
    );
    addTearDown(c.dispose);
    await c.refreshAvailability();
    expect(c.availability, AssistantAvailability.needsSetup);

    saved = _config;
    AssistantProviderStore.changes.value++; // what save() does, from any screen
    await pumpEventQueue();
    expect(c.availability, AssistantAvailability.ready);
  });

  test('an unreadable keychain keeps the last availability instead of asking for setup', () async {
    seerr = _seerr([]);
    Object? failure;
    final c = AssistantController(
      buildContext: (screen) => AssistantToolContext(
        servers: servers,
        screen: screen,
        requests: AssistantRequestServices(client: () => seerr),
      ),
      rolloutEnabled: true,
      entitlement: _Entitlement(),
      loadConfig: () async => failure == null ? _config : throw failure,
    );
    addTearDown(c.dispose);
    await c.refreshAvailability();
    expect(c.availability, AssistantAvailability.ready);

    failure = const AssistantProviderStoreException('OSStatus -25308');
    await c.refreshAvailability();
    expect(c.availability, AssistantAvailability.ready);
  });

  test('a keychain that fails on the first read offers setup, then follows the next good read', () async {
    seerr = _seerr([]);
    Object? failure = const AssistantProviderStoreException('OSStatus -34018');
    final c = AssistantController(
      buildContext: (screen) => AssistantToolContext(
        servers: servers,
        screen: screen,
        requests: AssistantRequestServices(client: () => seerr),
      ),
      rolloutEnabled: true,
      entitlement: _Entitlement(),
      loadConfig: () async => failure == null ? _config : throw failure,
    );
    addTearDown(c.dispose);
    await c.refreshAvailability();
    expect(c.availability, AssistantAvailability.needsSetup);

    // The keychain recovers; the next summon reads again instead of keeping
    // the set-up gate.
    failure = null;
    final session = BigPMobileSession(c);
    addTearDown(session.dispose);
    session.summon();
    await pumpEventQueue();
    expect(c.availability, AssistantAvailability.ready);
  });

  test('submit goes idle, working, result and forwards steps', () async {
    seerr = _seerr([]);
    final model = _Model([_call('ping'), _say('Gedaan.')])..gate = Completer();
    final c = controller(model: model, tools: [_ping]);
    expect(c.state, AssistantSurfaceState.idle);
    c.beginListening(context: const AssistantScreenContext(serverId: 's1'));
    expect(c.state, AssistantSurfaceState.listening);
    expect(c.screenContext?.serverId, 's1');

    final done = c.submit('Ping?');
    expect(c.state, AssistantSurfaceState.working);
    expect(c.prompt, 'Ping?');
    model.gate!.complete();
    await done;

    expect(c.state, AssistantSurfaceState.result);
    expect(c.resultIsError, isFalse);
    expect(c.lastEnd, AssistantRunEnd.answered);
    expect(c.answer, 'Gedaan.');
    // Started and done of one call collapse into one step.
    expect(c.steps.single.tool, 'ping');
    expect(c.steps.single.phase, AssistantStepPhase.done);
  });

  test('an error end is an error result', () async {
    seerr = _seerr([]);
    final c = controller(entitlement: _Entitlement(AssistantEntitlementState.notEntitled));
    await c.submit('x');
    expect(c.state, AssistantSurfaceState.result);
    expect(c.resultIsError, isTrue);
    expect(c.lastEnd, AssistantRunEnd.notEntitled);
    expect(c.availability, AssistantAvailability.locked);
  });

  test('a missing config sends the surface to setup, not to a run', () async {
    final c = controller(config: null);
    await c.submit('x');
    expect(c.state, AssistantSurfaceState.idle);
    expect(c.availability, AssistantAvailability.needsSetup);
  });

  test('pending confirm and cancel round trip', () async {
    seerr = _seerr([]);
    for (final confirm in [true, false]) {
      _executed = 0;
      final c = controller(model: _Model([_call('wipe'), _say('ok')]), tools: [_sensitive]);
      final done = c.submit('Verwijder Sam');
      while (c.pending == null) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(c.pending!.subject, 'Sam');
      expect(c.state, AssistantSurfaceState.working);
      confirm ? c.confirmPending(password: 'pw') : c.cancelPending();
      await done;
      expect(c.pending, isNull);
      expect(_executed, confirm ? 1 : 0);
      expect(c.actions.map((a) => a.subject), confirm ? ['Sam'] : isEmpty);
      expect(c.steps.single.phase, confirm ? AssistantStepPhase.done : AssistantStepPhase.failed);
    }
  });

  test('pickRequestOption builds a card only for a shown option', () async {
    final posts = <Map<String, dynamic>>[];
    seerr = _seerr(posts);
    final c = controller(
      model: _Model([
        _call('find_request_title', {
          'titles': [
            {'title': 'matrix'},
          ],
        }),
        _say('Gevonden.'),
      ]),
    );
    await c.submit('Vraag The Matrix aan');
    final option = (c.displays.single as AssistantRequestOptions).options.single;

    // Never shown: nothing happens.
    const stranger = AssistantRequestOption(
      seerrId: 'movie:999',
      title: 'X',
      kind: 'movie',
      posterUrl: '',
      overview: '',
      status: 'not_requested',
    );
    await c.pickRequestOption(stranger);
    expect(c.pending, isNull);
    expect(c.state, AssistantSurfaceState.result);

    final picked = c.pickRequestOption(option);
    while (c.pending == null) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(c.pending!.kind, AssistantActionKind.requestTitle);
    expect(posts, isEmpty);
    c.confirmPending();
    await picked;
    expect(posts.single['mediaId'], 603);
    expect(c.actions.single.kind, AssistantActionKind.requestTitle);
    expect(c.resultIsError, isFalse);
    expect(c.state, AssistantSurfaceState.result);
  });

  test('a reset while the entitlement is rechecked does not still create the request', () async {
    final posts = <Map<String, dynamic>>[];
    seerr = _seerr(posts);
    final entitlement = _Entitlement();
    final c = controller(
      entitlement: entitlement,
      model: _Model([
        _call('find_request_title', {
          'titles': [
            {'title': 'matrix'},
          ],
        }),
        _say('Gevonden.'),
      ]),
    );
    await c.submit('Vraag The Matrix aan');
    final option = (c.displays.single as AssistantRequestOptions).options.single;

    final picked = c.pickRequestOption(option);
    while (c.pending == null) {
      await Future<void>.delayed(Duration.zero);
    }
    entitlement.gate = Completer();
    c.confirmPending();
    await Future<void>.delayed(Duration.zero);
    c.reset();
    entitlement.gate!.complete();
    await picked;

    expect(posts, isEmpty);
    expect(c.actions, isEmpty);
    expect(c.state, AssistantSurfaceState.idle);
  });

  test('a tool sees the run cancel through its context', () async {
    late AssistantController c;
    final seen = <bool>[];
    final probe = AssistantTool(
      name: 'probe',
      description: 'probe',
      risk: AssistantToolRisk.read,
      properties: const {},
      needsServer: false,
      serves: (_, _) => true,
      run: (ctx, _, _) async {
        seen.add(ctx.cancelled);
        c.reset();
        seen.add(ctx.cancelled);
        return const AssistantToolResult({});
      },
    );
    c = controller(model: _Model([_call('probe'), _say('ok')]), tools: [probe]);
    await c.submit('x');
    expect(seen, [false, true]);
  });

  test('reset clears the conversation and cancels a waiting card', () async {
    seerr = _seerr([]);
    final c = controller(model: _Model([_call('wipe'), _say('ok')]), tools: [_sensitive]);
    final done = c.submit('Verwijder Sam');
    while (c.pending == null) {
      await Future<void>.delayed(Duration.zero);
    }
    c.reset();
    await done;
    expect(_executed, 0);
    expect(c.state, AssistantSurfaceState.idle);
    expect(c.pending, isNull);
    expect(c.prompt, isNull);
    expect(c.steps, isEmpty);
    expect(c.actions, isEmpty);
    expect(c.lastEnd, isNull);
  });

  test('one ask at a time', () async {
    seerr = _seerr([]);
    final model = _Model([_say('een')])..gate = Completer();
    final c = controller(model: model);
    final first = c.submit('een');
    await c.submit('twee');
    expect(c.prompt, 'een');
    model.gate!.complete();
    await first;
    expect(model.calls, 1);
    expect(c.answer, 'een');
  });

  group('model preload and a vanished model', () {
    AssistantController direct({
      required AssistantProviderConfig config,
      required MockClient http,
      DateTime Function()? now,
      List<AssistantProviderConfig>? webAsked,
    }) {
      final c = AssistantController(
        buildContext: (screen) => AssistantToolContext(
          servers: servers,
          screen: screen,
          requests: AssistantRequestServices(client: () => seerr),
        ),
        entitlement: _Entitlement(),
        loadConfig: () async => config,
        modelFor: (config) => AssistantModelClient(config, httpClient: http),
        webFor: (config) {
          webAsked?.add(config);
          return null;
        },
        languageName: () => 'Dutch',
        tools: [_ping],
        now: now,
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('preloads an Ollama server at most once per window, without a prompt', () async {
      final bodies = <Map<String, Object?>>[];
      var clock = DateTime(2026, 10, 2, 12);
      final c = direct(
        config: _config,
        now: () => clock,
        http: MockClient((r) async {
          expect(r.url.path, '/api/generate');
          bodies.add((jsonDecode(r.body) as Map).cast<String, Object?>());
          return _json({'model': 'm', 'done': true});
        }),
      );
      c.beginListening();
      await settle();
      c.cancelListening();
      clock = clock.add(const Duration(minutes: 4));
      c.beginListening();
      await settle();
      expect(bodies, [
        {'model': 'm', 'keep_alive': '10m'},
      ]);
      c.cancelListening();
      clock = clock.add(const Duration(minutes: 2));
      c.beginListening();
      await settle();
      expect(bodies.length, 2);
    });

    test('a failing preload is ignored and listening goes on', () async {
      final c = direct(config: _config, http: MockClient((_) async => http.Response('boom', 500)));
      c.beginListening();
      await settle();
      expect(c.state, AssistantSurfaceState.listening);
    });

    test('no preload for Ollama Cloud or OpenRouter', () async {
      for (final kind in [AssistantProviderKind.ollamaCloud, AssistantProviderKind.openRouter]) {
        var calls = 0;
        final c = direct(
          config: AssistantProviderConfig(kind: kind, baseUrl: 'https://x.test', model: 'm', apiKey: 'k'),
          http: MockClient((_) async {
            calls++;
            return _json({});
          }),
        );
        c.beginListening();
        await settle();
        expect(calls, 0, reason: kind.name);
      }
    });

    test('a model the provider no longer knows ends as modelMissing', () async {
      seerr = _seerr([]);
      final c = direct(
        config: _config,
        http: MockClient(
          (r) async => _json({
            'error': {'message': 'model "m" not found, try pulling it first', 'type': 'api_error'},
          }, status: 404),
        ),
      );
      await c.submit('Hallo?');
      expect(c.lastEnd, AssistantRunEnd.providerError);
      expect(c.modelMissing, isTrue);
      expect(c.resultIsError, isTrue);
      c.reset();
      expect(c.modelMissing, isFalse);
    });

    test('a plain provider error is not modelMissing', () async {
      seerr = _seerr([]);
      final c = direct(config: _config, http: MockClient((_) async => http.Response('nope', 500)));
      await c.submit('Hallo?');
      expect(c.lastEnd, AssistantRunEnd.providerError);
      expect(c.modelMissing, isFalse);
    });

    test('web lookup is only asked for when the config allows it', () async {
      seerr = _seerr([]);
      final asked = <AssistantProviderConfig>[];
      final answer = MockClient(
        (_) async => _json({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'ok'},
            },
          ],
        }),
      );
      const cloud = AssistantProviderConfig(
        kind: AssistantProviderKind.openRouter,
        baseUrl: 'https://x.test',
        model: 'm',
        apiKey: 'k',
      );
      // Local stays local until switched on; cloud allows it until switched off.
      await direct(config: _config, http: answer, webAsked: asked).submit('a');
      await direct(config: _config.copyWith(webSearch: true), http: answer, webAsked: asked).submit('b');
      await direct(config: cloud, http: answer, webAsked: asked).submit('c');
      await direct(config: cloud.copyWith(webSearch: false), http: answer, webAsked: asked).submit('d');
      expect(asked.map((c) => c.kind), [AssistantProviderKind.ollamaServer, AssistantProviderKind.openRouter]);
    });
  });
}
