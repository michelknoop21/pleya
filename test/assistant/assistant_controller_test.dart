import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_entitlement.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/media/ids.dart';
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
  @override
  Future<AssistantEntitlementState> check() async => state;
}

/// A model that answers from a script; a reply may be held back by a gate.
class _Model extends AssistantModelClient {
  _Model(this.script) : super(_config, httpClient: MockClient((_) async => http.Response('', 500)));
  final List<AssistantReply> script;
  Completer<void>? gate;
  var calls = 0;

  @override
  Future<AssistantReply> chat(List<Map<String, Object?>> messages, List<Map<String, Object?>> tools) async {
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
}
