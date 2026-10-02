import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_entitlement.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/assistant/assistant_web_lookup.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/seerr/seerr_client.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/seerr/seerr_session.dart';
import 'package:pleya/utils/media_server_http_client.dart' show AbortController;

import '../test_helpers/prefs.dart';

const _config = AssistantProviderConfig(
  kind: AssistantProviderKind.openRouter,
  baseUrl: 'http://o.lan',
  model: 'm',
  apiKey: 'k',
);

class _Entitled extends AssistantEntitlement {
  const _Entitled();
  @override
  Future<AssistantEntitlementState> check() async => AssistantEntitlementState.entitled;
}

/// A scripted model. A reply waits on [gates] for its call index; the
/// transport ignores the abort, as a late callback after a race would.
class _Model extends AssistantModelClient {
  _Model(this.script) : super(_config, httpClient: MockClient((_) async => http.Response('', 500)));
  final List<AssistantReply> script;
  final gates = <int, Completer<void>>{};
  var calls = 0;

  @override
  Future<AssistantReply> chat(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools, {
    AbortController? abort,
  }) async {
    final index = calls++;
    await gates[index]?.future;
    return index < script.length ? script[index] : _say('klaar');
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

class _Shown extends AssistantDisplay {
  const _Shown(this.label);
  final String label;
}

/// A serverless tool that shows [label] and records a done action.
var _shows = 0;
AssistantTool _show(String label) => AssistantTool(
  name: 'show',
  description: 'show',
  risk: AssistantToolRisk.read,
  properties: const {},
  needsServer: false,
  serves: (_, _) => true,
  run: (_, _, _) async {
    _shows++;
    return AssistantToolResult(
      const {'ok': true},
      display: _Shown(label),
      record: AssistantActionRecord(kind: AssistantActionKind.scanLibrary, serverName: 'Zolder', subject: label),
    );
  },
);

http.Response _json(Object? body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: const {'content-type': 'application/json'});

/// Overseerr that knows The Matrix, so the real find_title finds it.
SeerrClient _seerr() => SeerrClient(
  const SeerrSession(
    baseUrl: 'http://seerr.lan:5055',
    authMode: SeerrAuthMode.apiKey,
    apiKey: 'k',
    permissions: SeerrPermission.request,
  ),
  httpClient: MockClient((request) async {
    return switch (request.url.path.replaceFirst('/api/v1', '')) {
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

/// A chat endpoint that never answers on its own: it ends only when the
/// request's abort trigger fires, which [aborted] records.
MockClient _hangingChat({Completer<void>? seen, List<Uri>? aborted}) => MockClient.streaming((request, _) async {
  seen?.complete();
  final trigger = request is http.Abortable ? request.abortTrigger : null;
  await (trigger ?? Completer<void>().future);
  aborted?.add(request.url);
  throw http.RequestAbortedException(request.url);
});

Future<void> _until(bool Function() condition) async {
  final clock = Stopwatch()..start();
  while (!condition() && clock.elapsed < const Duration(seconds: 3)) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(condition(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MultiServerManager servers;

  setUp(() {
    resetSharedPreferencesForTest();
    AssistantWebCache.shared.clear();
    servers = MultiServerManager();
    addTearDown(servers.dispose);
    _shows = 0;
  });

  AssistantController controller({
    required AssistantModelClient Function() model,
    List<AssistantTool>? tools,
    SeerrClient? seerr,
  }) {
    final c = AssistantController(
      buildContext: (screen) => AssistantToolContext(
        servers: servers,
        screen: screen,
        requests: AssistantRequestServices(client: () => seerr),
      ),
      rolloutEnabled: true,
      entitlement: const _Entitled(),
      loadConfig: () async => _config,
      modelFor: (_) => model(),
      languageName: () => 'Dutch',
      tools: tools,
    );
    addTearDown(c.dispose);
    return c;
  }

  group('provider timeout', () {
    /// Seconds until [config]'s chat ends in a timeout, checked one second
    /// either side; the request is aborted on the wire at that moment.
    void expectTimeoutAt(AssistantProviderConfig config, int seconds) => fakeAsync((async) {
      final aborted = <Uri>[];
      AssistantModelException? error;
      AssistantModelClient(config, httpClient: _hangingChat(aborted: aborted))
          .chat(const [], const [])
          .then(
            (_) {},
            onError: (Object e) {
              error = e as AssistantModelException;
            },
          );
      async.elapse(Duration(seconds: seconds - 1));
      expect(error, isNull, reason: '${config.kind.name} still waiting at ${seconds - 1} s');
      async.elapse(const Duration(seconds: 2));
      expect(error?.error, AssistantModelError.timeout, reason: '${config.kind.name} timed out by $seconds s');
      expect(aborted, hasLength(1));
    });

    test('differs per provider kind and bounds the chat', () {
      const expected = {
        AssistantProviderKind.openRouter: 20,
        AssistantProviderKind.ollamaCloud: 60,
        AssistantProviderKind.ollamaServer: 90,
      };
      for (final MapEntry(key: kind, value: seconds) in expected.entries) {
        final config = AssistantProviderConfig(kind: kind, baseUrl: 'http://o.lan', model: 'm', apiKey: 'k');
        expect(config.providerTimeout, Duration(seconds: seconds));
        expectTimeoutAt(config, seconds);
      }
    });

    test('a per-config override beats the default, persists, and is dropped for another model', () {
      const config = AssistantProviderConfig(
        kind: AssistantProviderKind.ollamaServer,
        baseUrl: 'http://o.lan',
        model: 'm',
        timeoutOverride: Duration(seconds: 5),
      );
      expect(config.providerTimeout, const Duration(seconds: 5));
      expectTimeoutAt(config, 5);
      expect(AssistantProviderConfig.fromJson(config.toJson())!.providerTimeout, const Duration(seconds: 5));
      expect(config.copyWith(apiKey: 'x').providerTimeout, const Duration(seconds: 5));
      expect(config.copyWith(model: 'other').providerTimeout, const Duration(seconds: 90));
    });
  });

  test('find_title results show before the model reply, still checking, and stay the same set after', () async {
    final model = _Model([
      _call('find_title', {
        'candidates': [
          {'title': 'The Matrix', 'year': 1999, 'kind': 'movie'},
        ],
        'variants': ['matrix', 'matrix film'],
      }),
      _say('Dit is The Matrix.'),
    ]);
    model.gates[1] = Completer();
    final c = controller(model: () => model, seerr: _seerr());

    final done = c.submit('Die film met de rode pil');
    await _until(() => c.displays.isNotEmpty);

    // Search done, model's final turn still on the wire.
    expect(model.calls, 2);
    expect(c.state, AssistantSurfaceState.working);
    expect(c.stillChecking, isTrue);
    expect(c.answer, isEmpty);
    final shown = List.of(c.displays);
    final matches = (shown.single as AssistantTitleMatches).matches;
    expect(matches.first.title, 'The Matrix');
    final order = List.of(matches);

    model.gates[1]!.complete();
    await done;

    expect(c.state, AssistantSurfaceState.result);
    expect(c.stillChecking, isFalse);
    expect(c.answer, 'Dit is The Matrix.');
    expect(c.displays, hasLength(shown.length), reason: 'no duplicate display at the end');
    for (final (i, d) in c.displays.indexed) {
      expect(identical(d, shown[i]), isTrue, reason: 'the same display object, not rebuilt');
    }
    final after = (c.displays.single as AssistantTitleMatches).matches;
    expect(after.length, order.length);
    for (final (i, m) in after.indexed) {
      expect(identical(m, order[i]), isTrue);
    }
  });

  test('a model timeout ends as a provider timeout and keeps the results already shown', () async {
    final model = _Model([_call('show'), _say('nooit')]);
    model.gates[1] = Completer();
    final c = controller(model: () => _TimingOut(model), tools: [_show('Matrix')]);
    final done = c.submit('x');
    await _until(() => c.displays.isNotEmpty);
    model.gates[1]!.complete();
    await done;
    expect(c.lastEnd, AssistantRunEnd.providerError);
    expect(c.lastProviderError, AssistantModelError.timeout);
    expect(c.resultIsError, isTrue);
    expect((c.displays.single as _Shown).label, 'Matrix');
  });

  test('a reset during the model call aborts the HTTP request and writes nothing afterwards', () async {
    final seen = Completer<void>();
    final aborted = <Uri>[];
    final c = controller(
      model: () => AssistantModelClient(
        _config,
        httpClient: _hangingChat(seen: seen, aborted: aborted),
      ),
      tools: [_show('Matrix')],
    );
    final done = c.submit('x');
    await seen.future;
    expect(aborted, isEmpty);

    c.reset();
    await done;
    expect(aborted.single.path, '/v1/chat/completions');
    expect(c.state, AssistantSurfaceState.idle);
    expect(c.lastEnd, isNull);
    expect(c.displays, isEmpty);
    expect(c.actions, isEmpty);
    expect(c.answer, isEmpty);
  });

  test('a superseded ask cannot add displays or actions to the next one', () async {
    final a = _Model([_call('show'), _say('A klaar')]);
    a.gates[0] = Completer();
    final b = _Model([_say('B klaar')]);
    b.gates[0] = Completer();
    final models = [a, b];
    final c = controller(model: () => models.removeAt(0), tools: [_show('A')]);

    final askA = c.submit('A');
    await _until(() => a.calls == 1);
    c.reset();
    final askB = c.submit('B');
    await _until(() => b.calls == 1);

    // A's transport answers late, with a tool call that would show and act.
    a.gates[0]!.complete();
    await askA;
    expect(_shows, 0, reason: "A's tool never runs");
    expect(c.prompt, 'B');
    expect(c.state, AssistantSurfaceState.working);
    expect(c.displays, isEmpty);
    expect(c.actions, isEmpty);
    expect(c.steps, isEmpty);

    b.gates[0]!.complete();
    await askB;
    expect(c.answer, 'B klaar');
    expect(c.displays, isEmpty);
    expect(c.actions, isEmpty);
  });
}

/// [inner]'s first turns, then a provider timeout on the next.
class _TimingOut extends AssistantModelClient {
  _TimingOut(this.inner) : super(_config, httpClient: MockClient((_) async => http.Response('', 500)));
  final _Model inner;

  @override
  Future<AssistantReply> chat(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools, {
    AbortController? abort,
  }) async {
    final reply = await inner.chat(messages, tools, abort: abort);
    if (inner.calls > 1) throw const AssistantModelException(AssistantModelError.timeout);
    return reply;
  }
}
