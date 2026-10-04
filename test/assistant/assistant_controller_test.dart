import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
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
import 'package:pleya/media/media_identity.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/unified_catalog/home_custom_row_loader.dart';
import 'assistant_find_fakes.dart' as find;
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
  final List<List<Map<String, Object?>>> offeredTools = [];

  @override
  Future<AssistantReply> chat(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools, {
    AbortController? abort,
  }) async {
    offeredTools.add(tools);
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
SeerrClient _seerr(List<Map<String, dynamic>> posts, {int movieStatus = 1}) => SeerrClient(
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
      '/auth/me' => _json(const {'id': 7, 'permissions': SeerrPermission.request}),
      '/movie/603' => _json({
        'id': 603,
        'title': 'The Matrix',
        'releaseDate': '1999-03-31',
        'mediaInfo': {'status': movieStatus},
      }),
      _ => _json(const {'message': 'not found'}, status: 404),
    };
  }),
);

class _AvailableServer extends find.FakeServer {
  _AvailableServer()
    : super(
        's',
        libraries: {
          'films': [find.fakeItem('m', 'The Matrix', year: 1999)],
        },
      );
  Future<void> Function()? beforeLookup;
  @override
  Future<HealthStatus> checkHealth() async => HealthStatus.online;
  @override
  Future<List<MediaItem>> findAllByIdentity(MediaIdentity identity) async {
    await beforeLookup?.call();
    return super.findAllByIdentity(identity);
  }
}

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
      expect(c.tasks.single.status, confirm ? AssistantTaskStatus.completed : AssistantTaskStatus.cancelled);
      expect(c.lastEnd, AssistantRunEnd.answered);
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

  test('a new question supersedes an in-flight question', () async {
    seerr = _seerr([]);
    final old = _Model([_say('old')])..gate = Completer();
    final fresh = _Model([_say('new')]);
    var created = 0;
    final c = AssistantController(
      buildContext: (_) => AssistantToolContext(servers: servers),
      entitlement: _Entitlement(),
      loadConfig: () async => _config,
      modelFor: (_) => created++ == 0 ? old : fresh,
      tools: [_ping],
    );
    addTearDown(c.dispose);
    final first = c.submit('first');
    await Future<void>.delayed(Duration.zero);
    await c.submit('second');
    expect(c.prompt, 'second');
    expect(c.answer, 'new');
    old.gate!.complete();
    await first;
    expect(c.answer, 'new');
  });

  test('independent commands start before either tool finishes', () async {
    final releases = [Completer<void>(), Completer<void>()];
    final started = <String>[];
    final read = AssistantTool(
      name: 'read',
      description: 'read',
      risk: AssistantToolRisk.read,
      needsServer: false,
      properties: const {},
      serves: (_, _) => true,
      run: (_, _, args) async {
        final index = started.length;
        started.add(args['name'] as String);
        await releases[index].future;
        return AssistantToolResult({'name': args['name']});
      },
    );
    final models = [
      _Model([
        _call('split_tasks', {
          'tasks': [
            {'title': 'One', 'intent': 'search', 'prompt': 'one'},
            {'title': 'Two', 'intent': 'search', 'prompt': 'two'},
          ],
        }),
      ]),
      _Model([
        _call('read', {'name': 'one'}),
        _say('one'),
      ]),
      _Model([
        _call('read', {'name': 'two'}),
        _say('two'),
      ]),
    ];
    var next = 0;
    final c = AssistantController(
      buildContext: (_) => AssistantToolContext(servers: servers),
      entitlement: _Entitlement(),
      loadConfig: () async => _config,
      modelFor: (_) => models[next++],
      tools: [read],
    );
    addTearDown(c.dispose);
    final done = c.submit('one and two');
    await pumpEventQueue();
    expect(started, ['one', 'two']);
    for (final release in releases) {
      release.complete();
    }
    await done;
  });

  test('tool failure survives a successful model answer', () async {
    final failing = AssistantTool(
      name: 'fail',
      description: 'fail',
      risk: AssistantToolRisk.read,
      needsServer: false,
      properties: const {},
      serves: (_, _) => true,
      run: (_, _, _) async => const AssistantToolResult({'error': 'refused'}),
    );
    final c = controller(model: _Model([_call('fail'), _say('done')]), tools: [failing]);
    await c.submit('fail');
    expect(c.resultIsError, isTrue);
  });

  test('mixed mutation and split reply executes no calls', () async {
    var writes = 0;
    final mutate = AssistantTool(
      name: 'mutate',
      description: 'mutate',
      risk: AssistantToolRisk.mutation,
      needsServer: false,
      properties: const {},
      serves: (_, _) => true,
      run: (_, _, _) async {
        writes++;
        return const AssistantToolResult({});
      },
    );
    final split = _call('split_tasks', {
      'tasks': [
        {'title': 'One', 'intent': 'search', 'prompt': 'one'},
        {'title': 'Two', 'intent': 'search', 'prompt': 'two'},
      ],
    });
    final mixed = AssistantReply(
      content: '',
      toolCalls: [..._call('mutate').toolCalls, ...split.toolCalls],
      message: {'role': 'assistant', 'content': ''},
    );
    final c = controller(model: _Model([mixed, _say('ignore')]), tools: [mutate]);
    await c.submit('one and two');
    expect(writes, 0);
    expect(c.resultIsError, isTrue);
  });

  AssistantController splitController(
    List<_Model> children,
    List<AssistantTool> tools, {
    Duration timeout = const Duration(minutes: 2),
    _Entitlement? entitlement,
  }) {
    final models = [
      _Model([
        _call('split_tasks', {
          'tasks': [
            for (var i = 0; i < children.length; i++) {'title': 'Task $i', 'intent': 'test', 'prompt': 'task $i'},
          ],
        }),
      ]),
      ...children,
    ];
    var next = 0;
    final c = AssistantController(
      buildContext: (_) => AssistantToolContext(servers: servers),
      entitlement: entitlement ?? _Entitlement(),
      loadConfig: () async => _config,
      modelFor: (_) => models[next++],
      tools: tools,
      confirmTimeout: timeout,
    );
    addTearDown(c.dispose);
    return c;
  }

  test('declining one task confirmation cancels its label without stopping another task', () async {
    _executed = 0;
    final c = splitController(
      [
        _Model([_call('wipe'), _say('declined')]),
        _Model([_say('other done')]),
      ],
      [_sensitive],
    );
    final done = c.submit('two commands');
    while (c.pendingConfirmation == null) {
      await Future<void>.delayed(Duration.zero);
    }
    final pending = c.pendingConfirmation!;
    c.cancelTaskConfirmation(pending.taskId, pending.id);
    await done;
    expect(c.tasks[0].status, AssistantTaskStatus.cancelled);
    expect(c.tasks[0].error, 'cancelled_by_user');
    expect(c.tasks[0].lastEnd, AssistantRunEnd.answered);
    expect(c.tasks[1].status, AssistantTaskStatus.completed);
    expect(_executed, 0);
  });

  test('a concrete failure takes priority over an earlier declined action', () async {
    final refused = AssistantTool(
      name: 'refused',
      description: 'refused',
      risk: AssistantToolRisk.read,
      properties: const {},
      needsServer: false,
      serves: (_, _) => true,
      run: (_, _, _) async => const AssistantToolResult({'error': 'not_allowed'}),
    );
    final c = controller(model: _Model([_call('wipe'), _call('refused'), _say('ok')]), tools: [_sensitive, refused]);
    final done = c.submit('decline then fail');
    while (c.pendingConfirmation == null) {
      await Future<void>.delayed(Duration.zero);
    }
    final pending = c.pendingConfirmation!;
    c.cancelTaskConfirmation(pending.taskId, pending.id);
    await done;
    expect(c.tasks.single.status, AssistantTaskStatus.failed);
    expect(c.tasks.single.error, 'not_allowed');
    expect(c.tasks.single.steps, hasLength(2));
  });

  test('three tasks retain their own reversed results and isolate a failure', () async {
    final started = [Completer<void>(), Completer<void>(), Completer<void>()];
    final releases = [Completer<void>(), Completer<void>(), Completer<void>()];
    final read = AssistantTool(
      name: 'read',
      description: 'read',
      risk: AssistantToolRisk.read,
      needsServer: false,
      properties: const {},
      serves: (_, _) => true,
      run: (_, _, args) async {
        final i = args['i'] as int;
        started[i].complete();
        await releases[i].future;
        return AssistantToolResult(i == 1 ? {'error': 'refused'} : {'i': i});
      },
    );
    final c = splitController(
      [
        for (var i = 0; i < 3; i++)
          _Model([
            _call('read', {'i': i}),
            _say('answer $i'),
          ]),
      ],
      [read],
    );
    final done = c.submit('three commands');
    await Future.wait(started.map((s) => s.future));
    expect(c.tasks.map((t) => t.status), everyElement(AssistantTaskStatus.running));
    releases[2].complete();
    await pumpEventQueue();
    expect(c.tasks[2].answer, 'answer 2');
    expect(c.tasks[0].answer, '');
    releases[1].complete();
    releases[0].complete();
    await done;
    expect(c.tasks.map((t) => t.answer), ['answer 0', 'answer 1', 'answer 2']);
    expect(c.tasks.map((t) => t.status), [
      AssistantTaskStatus.completed,
      AssistantTaskStatus.failed,
      AssistantTaskStatus.completed,
    ]);
    expect(c.tasks[1].error, 'refused');
    expect(() => c.tasks.clear(), throwsUnsupportedError);
    expect(() => c.tasks.first.steps.clear(), throwsUnsupportedError);
  });

  test('individual cancellation ignores late steps while other task completes', () async {
    final started = [Completer<void>(), Completer<void>()];
    final releases = [Completer<void>(), Completer<void>()];
    final read = AssistantTool(
      name: 'read',
      description: 'read',
      risk: AssistantToolRisk.read,
      needsServer: false,
      properties: const {},
      serves: (_, _) => true,
      run: (_, _, args) async {
        final i = args['i'] as int;
        started[i].complete();
        await releases[i].future;
        return const AssistantToolResult({'ok': true});
      },
    );
    final c = splitController(
      [
        for (var i = 0; i < 2; i++)
          _Model([
            _call('read', {'i': i}),
            _say('answer $i'),
          ]),
      ],
      [read],
    );
    final done = c.submit('two commands');
    await Future.wait(started.map((s) => s.future));
    c.cancelTask(c.tasks.first.id);
    releases[1].complete();
    releases[0].complete();
    await done;
    expect(c.tasks[0].status, AssistantTaskStatus.cancelled);
    expect(c.tasks[0].answer, '');
    expect(c.tasks[0].steps.single.phase, AssistantStepPhase.started);
    expect(c.tasks[1].status, AssistantTaskStatus.completed);
  });

  test('cancel-all drops both pending confirmations without writes', () async {
    final c = splitController(
      [
        _Model([_call('wipe')]),
        _Model([_call('wipe')]),
      ],
      [_sensitive],
    );
    final done = c.submit('two commands');
    await pumpEventQueue();
    expect(c.tasks.map((t) => t.status), everyElement(AssistantTaskStatus.waitingForConfirmation));
    c.cancelAll();
    await done;
    expect(c.tasks.map((t) => t.status), everyElement(AssistantTaskStatus.cancelled));
    expect(c.pending, isNull);
    expect(_executed, 0);
  });

  test('confirmations are FIFO and stale identity cannot confirm next action', () async {
    final c = splitController(
      [
        _Model([_call('wipe')]),
        _Model([_call('wipe')]),
      ],
      [_sensitive],
    );
    final done = c.submit('two commands');
    await pumpEventQueue();
    final first = c.pendingConfirmation!;
    c.confirmTask(c.tasks[1].id, first.id);
    expect(_executed, 0);
    c.confirmTask(first.taskId, first.id);
    expect(c.pendingConfirmation?.taskId, c.tasks[1].id);
    final second = c.pendingConfirmation!;
    c.confirmTask(first.taskId, first.id);
    c.confirmPending(action: first.action);
    await pumpEventQueue();
    expect(_executed, 1);
    expect(c.pendingConfirmation?.id, second.id);
    c.confirmTask(second.taskId, second.id);
    await done;
    expect(_executed, 2);
  });

  test('only the visible confirmation times out', () {
    fakeAsync((clock) {
      final c = splitController(
        [
          _Model([_call('wipe')]),
          _Model([_call('wipe')]),
        ],
        [_sensitive],
        timeout: const Duration(minutes: 1),
      );
      var settled = false;
      c.submit('two commands').then((_) => settled = true);
      clock.flushMicrotasks();
      final first = c.pendingConfirmation!;
      clock.elapse(const Duration(seconds: 45));
      c.cancelTaskConfirmation(first.taskId, first.id);
      clock.flushMicrotasks();
      final second = c.pendingConfirmation!;
      clock.elapse(const Duration(seconds: 20));
      clock.flushMicrotasks();
      expect(c.pendingConfirmation?.id, second.id);
      expect(settled, isFalse);
      clock.elapse(const Duration(seconds: 40));
      clock.flushMicrotasks();
      expect(c.pending, isNull);
      expect(settled, isTrue);
      expect(c.tasks[1].error, 'not_confirmed');
    });
  });

  test('confirmation waits hold no slot for a fourth task', () async {
    final started = Completer<void>();
    final read = AssistantTool(
      name: 'read',
      description: 'read',
      risk: AssistantToolRisk.read,
      needsServer: false,
      properties: const {},
      serves: (_, _) => true,
      run: (_, _, _) async {
        started.complete();
        return const AssistantToolResult({});
      },
    );
    final c = splitController(
      [
        for (var i = 0; i < 3; i++) _Model([_call('wipe')]),
        _Model([_call('read')]),
      ],
      [_sensitive, read],
    );
    final done = c.submit('four commands');
    await started.future;
    await pumpEventQueue();
    expect(c.tasks[3].status, AssistantTaskStatus.completed);
    c.cancelAll();
    await done;
  });

  test('three-operation cap queues a fourth read until one settles', () async {
    final started = <int>[];
    final three = Completer<void>();
    final four = Completer<void>();
    final releases = [for (var i = 0; i < 4; i++) Completer<void>()];
    final read = AssistantTool(
      name: 'read',
      description: 'read',
      risk: AssistantToolRisk.read,
      needsServer: false,
      properties: const {},
      serves: (_, _) => true,
      run: (_, _, args) async {
        final i = args['i'] as int;
        started.add(i);
        if (started.length == 3) three.complete();
        if (started.length == 4) four.complete();
        await releases[i].future;
        return const AssistantToolResult({});
      },
    );
    final c = splitController(
      [
        for (var i = 0; i < 4; i++)
          _Model([
            _call('read', {'i': i}),
          ]),
      ],
      [read],
    );
    final done = c.submit('four commands');
    await three.future;
    expect(started, [0, 1, 2]);
    releases[1].complete();
    await four.future;
    expect(started, [0, 1, 2, 3]);
    for (final i in [0, 2, 3]) {
      releases[i].complete();
    }
    await done;
  });

  test('a successful different target cannot erase an operation error', () async {
    final tool = AssistantTool(
      name: 'read',
      description: 'read',
      risk: AssistantToolRisk.read,
      needsServer: false,
      properties: const {},
      serves: (_, _) => true,
      run: (_, _, args) async => AssistantToolResult(args['id'] == 'bad' ? {'error': 'refused'} : {'ok': true}),
    );
    final c = controller(
      model: _Model([
        _call('read', {'id': 'bad'}),
        _call('read', {'id': 'good'}),
        _say('all done'),
      ]),
      tools: [tool],
    );
    await c.submit('both');
    expect(c.resultIsError, isTrue);
    expect(c.tasks.single.error, 'refused');
  });

  test('a recovered operation error permits successful completion', () async {
    var calls = 0;
    final tool = AssistantTool(
      name: 'read',
      description: 'read',
      risk: AssistantToolRisk.read,
      needsServer: false,
      properties: const {},
      serves: (_, _) => true,
      run: (_, _, _) async => AssistantToolResult(calls++ == 0 ? {'error': 'temporary'} : {'ok': true}),
    );
    final c = controller(model: _Model([_call('read'), _call('read'), _say('done')]), tools: [tool]);
    await c.submit('retry');
    expect(c.resultIsError, isFalse);
    expect(c.tasks.single.status, AssistantTaskStatus.completed);
  });

  test('a nonabortable superseded write serializes the next question', () async {
    final firstStarted = Completer<void>();
    final release = Completer<void>();
    final writes = <String>[];
    final write = AssistantTool(
      name: 'write',
      description: 'write',
      risk: AssistantToolRisk.mutation,
      needsServer: false,
      properties: const {},
      serves: (_, _) => true,
      run: (_, _, args) async {
        final value = args['value'] as String;
        writes.add(value);
        if (value == 'old') {
          firstStarted.complete();
          await release.future;
        }
        return const AssistantToolResult({'done': true});
      },
    );
    final models = [
      _Model([
        _call('write', {'value': 'old'}),
        _say('old'),
      ]),
      _Model([
        _call('write', {'value': 'new'}),
        _say('new'),
      ]),
    ];
    var next = 0;
    final c = AssistantController(
      buildContext: (_) => AssistantToolContext(servers: servers),
      entitlement: _Entitlement(),
      loadConfig: () async => _config,
      modelFor: (_) => models[next++],
      tools: [write],
    );
    addTearDown(c.dispose);
    final old = c.submit('old');
    await firstStarted.future;
    final fresh = c.submit('new');
    await pumpEventQueue();
    expect(writes, ['old']);
    expect(c.prompt, 'new');
    release.complete();
    await Future.wait([old, fresh]);
    expect(writes, ['old', 'new']);
    expect(c.answer, 'new');
    expect(c.tasks.single.status, AssistantTaskStatus.completed);
  });

  for (final revoked in ['role', 'entitlement', 'disconnect']) {
    test('queued mutation rechecks $revoked after acquiring the lock', () async {
      final firstStarted = Completer<void>();
      final release = Completer<void>();
      final entitlement = _Entitlement();
      var available = true;
      var writes = 0;
      final tool = AssistantTool(
        name: 'write',
        description: 'write',
        risk: AssistantToolRisk.sensitive,
        needsServer: false,
        properties: const {},
        serves: (_, _) => available,
        run: (_, _, _) async => AssistantPendingAction(
          kind: AssistantActionKind.removeUser,
          serverId: ServerId('none'),
          serverName: 'Test',
          subject: 'user',
          execute: ({password}) async {
            writes++;
            if (writes == 1) {
              firstStarted.complete();
              await release.future;
            }
            return {'done': true};
          },
        ),
      );
      final c = splitController(
        [
          _Model([_call('write')]),
          _Model([_call('write')]),
        ],
        [tool],
        entitlement: entitlement,
      );
      final done = c.submit('two writes');
      await pumpEventQueue();
      final first = c.pendingConfirmation!;
      c.confirmTask(first.taskId, first.id);
      await firstStarted.future;
      final second = c.pendingConfirmation!;
      c.confirmTask(second.taskId, second.id);
      await pumpEventQueue();
      expect(writes, 1);
      if (revoked == 'entitlement') {
        entitlement.state = AssistantEntitlementState.notEntitled;
      } else {
        available = false;
      }
      release.complete();
      await done;
      expect(writes, 1);
      expect(c.tasks[0].status, AssistantTaskStatus.completed);
      expect(c.tasks[1].status, AssistantTaskStatus.failed);
      expect(c.tasks[1].error, revoked == 'entitlement' ? 'not_entitled' : 'not_allowed');
    });
  }

  test('question model budget stops children while retaining completed tasks', () async {
    final children = [
      for (var i = 0; i < 10; i++) _Model(i < 2 ? [_say('finished $i')] : [for (var j = 0; j < 6; j++) _call('ping')]),
    ];
    final c = splitController(children, [_ping]);
    await c.submit('ten commands');
    expect(children.fold<int>(0, (sum, model) => sum + model.calls), 19);
    expect(c.tasks.take(2).map((t) => t.status), everyElement(AssistantTaskStatus.completed));
    expect(c.tasks.take(2).map((t) => t.answer), ['finished 0', 'finished 1']);
    expect(c.tasks.where((t) => t.error == 'budget_exhausted'), isNotEmpty);
  });

  test('question tool budget is shared atomically across child runs', () async {
    var reads = 0;
    final tool = AssistantTool(
      name: 'read',
      description: 'read',
      risk: AssistantToolRisk.read,
      needsServer: false,
      properties: const {},
      serves: (_, _) => true,
      run: (_, _, _) async {
        reads++;
        return const AssistantToolResult({});
      },
    );
    final reply = AssistantReply(
      content: '',
      toolCalls: [for (var i = 0; i < 4; i++) AssistantToolCall(id: 'c$i', name: 'read', arguments: '{}')],
      message: {'role': 'assistant', 'content': ''},
    );
    final c = splitController(
      [
        for (var i = 0; i < 10; i++) _Model([reply, _say('done')]),
      ],
      [tool],
    );
    await c.submit('ten commands');
    expect(reads, 29); // the root routing call is also reserved
    expect(c.tasks.where((t) => t.error == 'budget_exhausted'), isNotEmpty);
  });

  test('shown ID authority is isolated across child tasks', () async {
    final tool = AssistantTool(
      name: 'ids',
      description: 'ids',
      risk: AssistantToolRisk.read,
      needsServer: false,
      properties: const {},
      serves: (_, _) => true,
      run: (ctx, _, args) async {
        final id = ServerId('test');
        if (args['show'] == true) {
          ctx.showItem(id, 'secret');
          return const AssistantToolResult({});
        }
        ctx.requireShownItem(id, 'secret');
        return const AssistantToolResult({});
      },
    );
    final c = splitController(
      [
        _Model([
          _call('ids', {'show': true}),
          _say('done'),
        ]),
        _Model([
          _call('ids', {'show': false}),
          _say('done'),
        ]),
      ],
      [tool],
    );
    await c.submit('two commands');
    expect(c.tasks[0].status, AssistantTaskStatus.completed);
    expect(c.tasks[1].error, 'unknown_item_id');
  });

  for (final movieStatus in [1, 5]) {
    test(
      'an option pick with Seerr status $movieStatus publishes ordinary titles while another task finishes',
      () async {
        final posts = <Map<String, dynamic>>[];
        seerr = _seerr(posts, movieStatus: movieStatus);
        final server = _AvailableServer();
        servers.debugRegisterClientForTesting(server);
        final independent = Completer<void>();
        final models = [
          _Model([
            _call('split_tasks', {
              'tasks': [
                {'title': 'Request', 'intent': 'request', 'prompt': 'request'},
                {'title': 'Other', 'intent': 'read', 'prompt': 'other'},
              ],
            }),
          ]),
          _Model([
            _call('find_request_title', {
              'titles': [
                {'title': 'matrix'},
              ],
            }),
            _say('found'),
          ]),
          _Model([_say('other')])..gate = independent,
        ];
        var next = 0;
        final catalog = AssistantCatalogServices(
          rowLoader: CatalogHomeCustomRowLoader(
            libraries: () => [find.fakeLib('s', 'films')],
            isServerVisible: servers.isServerVisible,
            hiddenLibraryKeys: () => {},
            clientFor: servers.getClient,
          ),
          profileId: 'p',
          activeProfileId: () => 'p',
        );
        final c = AssistantController(
          buildContext: (_) => AssistantToolContext(
            servers: servers,
            catalog: catalog,
            requests: AssistantRequestServices(client: () => seerr),
          ),
          entitlement: _Entitlement(),
          loadConfig: () async => _config,
          modelFor: (_) => models[next++],
        );
        addTearDown(c.dispose);
        final question = c.submit('two commands');
        await pumpEventQueue();
        final task = c.tasks.first;
        final option = (task.displays.single as AssistantRequestOptions).options.single;
        final started = Completer<void>(), release = Completer<void>();
        server.beforeLookup = () async {
          started.complete();
          await release.future;
        };
        final picked = c.pickTaskRequestOption(task.id, option);
        await started.future;
        independent.complete();
        await question;
        expect(c.tasks[1].status, AssistantTaskStatus.completed);
        expect(c.tasks[0].displays.whereType<AssistantTitleMatches>(), isEmpty);
        release.complete();
        await picked;
        expect(
          c.tasks[0].displays.whereType<AssistantTitleMatches>().single.matches.single.targets.single.item.id,
          'm',
        );
        expect(c.tasks[1].displays.whereType<AssistantTitleMatches>(), isEmpty);
        expect(c.pending, isNull);
        expect(posts, isEmpty);
      },
    );
  }

  for (final boundary in ['cancel', 'new ask', 'profile']) {
    test('late available option result after $boundary cannot publish title cards', () async {
      final posts = <Map<String, dynamic>>[];
      seerr = _seerr(posts);
      final server = _AvailableServer();
      servers.debugRegisterClientForTesting(server);
      var profile = 'p';
      final catalog = AssistantCatalogServices(
        rowLoader: CatalogHomeCustomRowLoader(
          libraries: () => [find.fakeLib('s', 'films')],
          isServerVisible: servers.isServerVisible,
          hiddenLibraryKeys: () => {},
          clientFor: servers.getClient,
        ),
        profileId: 'p',
        activeProfileId: () => profile,
      );
      final models = [
        _Model([
          _call('find_request_title', {
            'titles': [
              {'title': 'matrix'},
            ],
          }),
          _say('found'),
        ]),
        _Model([_say('new question')]),
      ];
      var next = 0;
      final c = AssistantController(
        buildContext: (_) => AssistantToolContext(
          servers: servers,
          catalog: catalog,
          requests: AssistantRequestServices(client: () => seerr),
        ),
        entitlement: _Entitlement(),
        loadConfig: () async => _config,
        modelFor: (_) => models[next++],
      );
      addTearDown(c.dispose);
      await c.submit('find matrix');
      final task = c.tasks.single;
      final option = (task.displays.single as AssistantRequestOptions).options.single;
      final started = Completer<void>(), release = Completer<void>();
      server.beforeLookup = () async {
        started.complete();
        await release.future;
      };
      final picked = c.pickTaskRequestOption(task.id, option);
      await started.future;
      if (boundary == 'cancel') c.cancelTask(task.id);
      if (boundary == 'profile') profile = 'other';
      if (boundary == 'new ask') await c.submit('replacement');
      release.complete();
      await picked;
      await pumpEventQueue();
      expect(c.tasks.expand((task) => task.displays).whereType<AssistantTitleMatches>(), isEmpty);
      expect(posts, isEmpty);
      expect(c.pending, isNull);
    });
  }

  test('same Seerr IDs select the exact originating context while another task works', () async {
    final firstPosts = <Map<String, dynamic>>[];
    final secondPosts = <Map<String, dynamic>>[];
    final clients = [_seerr(firstPosts), _seerr(secondPosts)];
    final gate = Completer<void>();
    final find = _call('find_request_title', {
      'titles': [
        {'title': 'matrix'},
      ],
    });
    final models = [
      _Model([
        _call('split_tasks', {
          'tasks': [
            {'title': 'One', 'intent': 'request', 'prompt': 'one'},
            {'title': 'Two', 'intent': 'request', 'prompt': 'two'},
            {'title': 'Three', 'intent': 'read', 'prompt': 'three'},
          ],
        }),
      ]),
      _Model([find, _say('one')]),
      _Model([find, _say('two')]),
      _Model([_say('three')])..gate = gate,
    ];
    var modelNext = 0, contextNext = 0;
    final c = AssistantController(
      buildContext: (_) => AssistantToolContext(
        servers: servers,
        requests: AssistantRequestServices(client: () => clients[contextNext++ < 2 ? 0 : 1]),
      ),
      entitlement: _Entitlement(),
      loadConfig: () async => _config,
      modelFor: (_) => models[modelNext++],
    );
    addTearDown(c.dispose);
    final done = c.submit('three commands');
    await pumpEventQueue();
    final second = c.tasks[1];
    final option = (second.displays.single as AssistantRequestOptions).options.single;
    final rejected = c.pickTaskRequestOption(c.tasks[0].id, option);
    await pumpEventQueue();
    expect(c.pending, isNull);
    await rejected;
    final picked = c.pickRequestOption(option);
    await pumpEventQueue();
    expect(c.pendingConfirmation!.taskId, second.id);
    c.confirmTask(second.id, c.pendingConfirmation!.id);
    await picked;
    expect(firstPosts, isEmpty);
    expect(secondPosts.single['mediaId'], 603);
    expect(c.tasks[2].status, AssistantTaskStatus.running);
    gate.complete();
    await done;
  });

  test('malformed split gets exactly one read-only repair and executes all repaired tasks', () async {
    final root = _Model([
      _call('split_tasks', {
        'tasks': [
          {'title': 'missing prompt'},
        ],
      }),
      _call('split_tasks', {
        'tasks': [
          {'title': 'One', 'intent': 'search', 'prompt': 'one'},
          {'title': 'Two', 'intent': 'search', 'prompt': 'two'},
        ],
      }),
    ]);
    final models = [
      root,
      _Model([_say('one')]),
      _Model([_say('two')]),
    ];
    var next = 0;
    final c = AssistantController(
      buildContext: (_) => AssistantToolContext(servers: servers),
      entitlement: _Entitlement(),
      loadConfig: () async => _config,
      modelFor: (_) => models[next++],
      tools: [_ping],
    );
    addTearDown(c.dispose);
    await c.submit('two commands');
    expect(root.calls, 2);
    expect(root.offeredTools[1].map((t) => (t['function'] as Map)['name']), ['split_tasks']);
    expect(c.tasks.map((t) => t.answer), ['one', 'two']);
  });

  test('children cannot split or execute a mixed split reply', () async {
    var writes = 0;
    final tool = AssistantTool(
      name: 'write',
      description: 'write',
      risk: AssistantToolRisk.mutation,
      needsServer: false,
      properties: const {},
      serves: (_, _) => true,
      run: (_, _, _) async {
        writes++;
        return const AssistantToolResult({});
      },
    );
    final nested = _call('split_tasks', {
      'tasks': [
        {'title': 'A', 'intent': 'read', 'prompt': 'a'},
        {'title': 'B', 'intent': 'read', 'prompt': 'b'},
      ],
    });
    final child = _Model([
      AssistantReply(
        content: '',
        toolCalls: [..._call('write').toolCalls, ...nested.toolCalls],
        message: {'role': 'assistant', 'content': ''},
      ),
    ]);
    final c = splitController(
      [
        child,
        _Model([_say('done')]),
      ],
      [tool],
    );
    await c.submit('two commands');
    expect(writes, 0);
    expect(child.calls, 1);
    expect(c.tasks[0].error, 'invalid_split');
    expect(c.tasks[1].status, AssistantTaskStatus.completed);
    expect(child.offeredTools.single.map((t) => (t['function'] as Map)['name']), isNot(contains('split_tasks')));
  });

  test('single commands have no added parsing model turn', () async {
    final model = _Model([_say('answer')]);
    final c = controller(model: model, tools: [_ping]);
    await c.submit('one');
    expect(model.calls, 1);
    expect(c.tasks.single.status, AssistantTaskStatus.completed);
    expect(model.offeredTools.single.map((t) => (t['function'] as Map)['name']), contains('split_tasks'));
  });

  test('a superseded confirmation cannot authorize a new question', () async {
    final models = [
      _Model([_call('wipe')]),
      _Model([_call('wipe')]),
    ];
    var next = 0;
    final c = AssistantController(
      buildContext: (_) => AssistantToolContext(servers: servers),
      entitlement: _Entitlement(),
      loadConfig: () async => _config,
      modelFor: (_) => models[next++],
      tools: [_sensitive],
    );
    addTearDown(c.dispose);
    final old = c.submit('old');
    await pumpEventQueue();
    final first = c.pendingConfirmation!;
    final fresh = c.submit('new');
    await pumpEventQueue();
    c.confirmTask(first.taskId, first.id);
    expect(_executed, 0);
    final second = c.pendingConfirmation!;
    c.confirmTask(second.taskId, second.id);
    await Future.wait([old, fresh]);
    expect(_executed, 1);
    expect(c.actions.length, 1);
  });

  test('an immediate mutation rechecks authority after waiting for another write', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var allowed = true;
    final writes = <int>[];
    final write = AssistantTool(
      name: 'write',
      description: 'write',
      risk: AssistantToolRisk.mutation,
      needsServer: false,
      properties: const {},
      serves: (_, _) => allowed,
      run: (_, _, args) async {
        final i = args['i'] as int;
        writes.add(i);
        if (i == 0) {
          started.complete();
          await release.future;
        }
        return const AssistantToolResult({'done': true});
      },
    );
    final c = splitController(
      [
        _Model([
          _call('write', {'i': 0}),
        ]),
        _Model([
          _call('write', {'i': 1}),
        ]),
      ],
      [write],
    );
    final done = c.submit('two writes');
    await started.future;
    await pumpEventQueue();
    expect(writes, [0]);
    allowed = false;
    release.complete();
    await done;
    expect(writes, [0]);
    expect(c.tasks[0].status, AssistantTaskStatus.completed);
    expect(c.tasks[1].error, 'not_allowed');
  });

  test('disconnect after option confirmation while queued refuses the real Seerr request', () async {
    final posts = <Map<String, dynamic>>[];
    seerr = _seerr(posts);
    final started = Completer<void>();
    final release = Completer<void>();
    final hold = AssistantTool(
      name: 'hold',
      description: 'hold',
      risk: AssistantToolRisk.mutation,
      needsServer: false,
      properties: const {},
      serves: (_, _) => true,
      run: (_, _, _) async {
        started.complete();
        await release.future;
        return const AssistantToolResult({});
      },
    );
    final models = [
      _Model([
        _call('split_tasks', {
          'tasks': [
            {'title': 'Hold', 'intent': 'write', 'prompt': 'hold'},
            {'title': 'Find', 'intent': 'request', 'prompt': 'find'},
          ],
        }),
      ]),
      _Model([_call('hold')]),
      _Model([
        _call('find_request_title', {
          'titles': [
            {'title': 'matrix'},
          ],
        }),
        _say('found'),
      ]),
    ];
    var next = 0;
    final c = AssistantController(
      buildContext: (_) => AssistantToolContext(
        servers: servers,
        requests: AssistantRequestServices(client: () => seerr),
      ),
      entitlement: _Entitlement(),
      loadConfig: () async => _config,
      modelFor: (_) => models[next++],
      tools: [hold, ...assistantTools],
    );
    addTearDown(c.dispose);
    final done = c.submit('hold and find');
    await started.future;
    await pumpEventQueue();
    final task = c.tasks[1];
    final option = (task.displays.single as AssistantRequestOptions).options.single;
    final picked = c.pickTaskRequestOption(task.id, option);
    await pumpEventQueue();
    final card = c.pendingConfirmation!;
    c.confirmTask(card.taskId, card.id);
    await pumpEventQueue();
    seerr = null;
    release.complete();
    await Future.wait([done, picked]);
    expect(posts, isEmpty);
    expect(c.tasks[1].status, AssistantTaskStatus.failed);
    expect(c.tasks[1].error, 'not_allowed');
  });

  test('dispose drops a waiting card without notifying or executing it', () async {
    final c = AssistantController(
      buildContext: (_) => AssistantToolContext(servers: servers),
      entitlement: _Entitlement(),
      loadConfig: () async => _config,
      modelFor: (_) => _Model([_call('wipe')]),
      tools: [_sensitive],
    );
    var notifications = 0;
    c.addListener(() => notifications++);
    final done = c.submit('write');
    await pumpEventQueue();
    final beforeDispose = notifications;
    c.dispose();
    await done;
    expect(notifications, beforeDispose);
    expect(_executed, 0);
    expect(c.pending, isNull);
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
