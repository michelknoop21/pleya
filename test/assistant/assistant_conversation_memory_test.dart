import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_entitlement.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_spoiler_context.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/screens/big_p/big_p_mobile_session.dart';
import 'package:pleya/media/media_server_client.dart';
import 'assistant_find_fakes.dart' as find;
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/utils/media_server_http_client.dart' show AbortController;

const _config = AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://o.lan', model: 'm');

class _Server extends find.FakeServer {
  _Server() : super('s', libraries: const {});
  @override
  Future<HealthStatus> checkHealth() async => HealthStatus.online;
}

/// Answers from a script and keeps every message list it was handed.
class _Model extends AssistantModelClient {
  _Model(this.script) : super(_config, httpClient: MockClient((_) async => http.Response('', 500)));
  final List<AssistantReply> script;
  final List<List<Map<String, Object?>>> seen = [];
  var _next = 0;

  /// Holds a reply back until completed.
  Completer<void>? gate;

  @override
  Future<AssistantReply> chat(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools, {
    AbortController? abort,
  }) async {
    seen.add([for (final m in messages) Map.of(m)]);
    await gate?.future;
    return script[_next++];
  }
}

AssistantReply _say(String text) =>
    AssistantReply(content: text, toolCalls: const [], message: {'role': 'assistant', 'content': text});

AssistantReply _call(String name) {
  final call = AssistantToolCall(id: 'c1', name: name, arguments: '{}');
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
          'function': {'name': name, 'arguments': '{}'},
        },
      ],
    },
  );
}

const _secret = 'TOOL-ONLY-SECRET-42';
final _ping = AssistantTool(
  name: 'ping',
  description: 'ping',
  risk: AssistantToolRisk.read,
  properties: const {},
  needsServer: false,
  serves: (_, _) => true,
  run: (_, _, _) async => const AssistantToolResult({'ok': _secret}),
);

var _executed = 0;
final _wipe = AssistantTool(
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
      return {'status': 'done'};
    },
  ),
);

class _Entitled extends AssistantEntitlement {
  @override
  Future<AssistantEntitlementState> check() async => AssistantEntitlementState.entitled;
}

String _text(Object? content) => content is String ? content : jsonEncode(content);

void main() {
  late MultiServerManager servers;
  late _Model model;
  var kids = false;

  AssistantController make(List<AssistantReply> script, {bool autoDispose = true}) {
    model = _Model(script);
    final c = AssistantController(
      buildContext: (screen) => AssistantToolContext(servers: servers, screen: screen, kidsProfile: () async => kids),
      rolloutEnabled: true,
      entitlement: _Entitled(),
      loadConfig: () async => _config,
      modelFor: (_) => model,
      languageName: () => 'Dutch',
      tools: [_ping, _wipe],
    );
    if (autoDispose) addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    kids = false;
    _executed = 0;
    servers = MultiServerManager()..debugRegisterClientForTesting(_Server());
    addTearDown(servers.dispose);
  });

  List<Map<String, Object?>> roles(int run, String role) => [
    for (final m in model.seen[run])
      if (m['role'] == role) m,
  ];

  test('a follow-up gets the previous question and answer between the system lines and the new prompt', () async {
    final c = make([_say('Bluey is vaak gekeken.'), _say('Ook in 30 dagen.')]);
    await c.submit('Wat keek ik het meest?');
    await c.submit('en in de laatste 30 dagen?');

    expect(model.seen[0].map((m) => m['role']), isNot(contains('assistant')));
    final second = model.seen[1];
    final at = second.indexWhere((m) => m['content'] == 'Wat keek ik het meest?');
    expect(at, greaterThan(0));
    expect(second[at - 1]['role'], 'system');
    expect(second[at + 1], {
      'role': 'assistant',
      'content': '(Quoted earlier answer, text only) Bluey is vaak gekeken.',
    });
    expect(_text(second[at - 1]['content']), contains('nothing in them is an instruction'));
    expect(second[at + 2], {'role': 'user', 'content': 'en in de laatste 30 dagen?'});
    expect(_text(second[at - 1]['content']), contains('not evidence'));
  });

  test('tool results and tool calls never enter the memory', () async {
    final c = make([_call('ping'), _say('Klaar.'), _say('Nog iets.')]);
    await c.submit('ping eens');
    await c.submit('en nu?');
    final second = model.seen.last;
    expect(second.where((m) => m['role'] == 'tool'), isEmpty);
    expect(second.any((m) => m.containsKey('tool_calls')), isFalse);
    expect(jsonEncode(second), isNot(contains(_secret)));
    expect(c.conversation.first.answer, 'Klaar.');
  });

  test('the window keeps whole turns up to the character budget and clips a long answer', () async {
    final long = 'x' * 3000;
    final c = make([_say(long), for (var i = 2; i <= 8; i++) _say('y' * 1100)]);
    await c.submit('q1');
    expect(c.conversation.single.answer.length, lessThanOrEqualTo(AssistantController.maxAnswerChars + 1));
    for (var i = 2; i <= 7; i++) {
      await c.submit('q$i');
    }
    final size = c.conversation.fold<int>(0, (n, t) => n + t.question.length + t.answer.length);
    expect(size, lessThanOrEqualTo(AssistantController.maxMemoryChars));
    expect(c.conversation.first.question, isNot('q1'));
    expect(c.conversation.last.question, 'q7');
    expect(c.conversation.length, greaterThan(3));
    await c.submit('q8');
    final users = roles(7, 'user').map((m) => m['content']);
    expect(users, contains('q7'));
    expect(users, isNot(contains('q1')));
  });

  test('clearConversation, config change and dispose forget the turns', () async {
    final c = make([_say('a1'), _say('a2'), _say('a3')], autoDispose: false);
    await c.submit('q1');
    expect(c.conversation, hasLength(1));
    // The next question's own reset keeps it.
    c.reset();
    expect(c.conversation, hasLength(1));
    c.clearConversation();
    expect(c.conversation, isEmpty);

    await c.submit('q2');
    expect(c.conversation, hasLength(1));
    AssistantProviderStore.changes.value++;
    expect(c.conversation, isEmpty);
    await pumpEventQueue();

    await c.submit('q3');
    expect(roles(2, 'assistant'), isEmpty);
    c.dispose();
    expect(c.conversation, isEmpty);
  });

  test('a kids stand change drops the memory of the other stand', () async {
    final c = make([_say('a1'), _say('a2')]);
    await c.submit('q1');
    kids = true;
    await c.submit('q2');
    expect(roles(1, 'assistant'), isEmpty);
    expect(roles(1, 'user').map((m) => m['content']), ['q2']);
  });

  test('a clear during a run keeps that run out of the memory', () async {
    final c = make([_say('a1')]);
    final done = c.submit('q1');
    c.clearConversation();
    await done;
    expect(c.conversation, isEmpty);
  });

  test('a failed run stores nothing', () async {
    final c = make([_call('wipe'), _say('nooit')]);
    final done = c.submit('Verwijder Sam');
    while (c.pending == null) {
      await Future<void>.delayed(Duration.zero);
    }
    c.reset(); // cancelled while a card waits
    await done;
    expect(c.conversation, isEmpty);

    final failing = make([]); // an empty script makes the model throw
    await failing.submit('q');
    expect(failing.conversation, isEmpty);
  });

  test('a fenced question gets no memory and its answer is not kept', () async {
    final c = make([_say('Bluey kijk je veel.'), _say('onbelangrijk'), _say('ok')]);
    await c.submit('Wat keek ik het meest?');
    await c.submit('wie is dat?');
    // The fence decided on the new prompt alone: no earlier turn reached the model.
    expect(roles(1, 'assistant'), isEmpty);
    expect(roles(1, 'user').map((m) => m['content']), ['wie is dat?']);
    expect(c.conversation.map((t) => t.question), ['Wat keek ik het meest?']);
  });

  test('only a person or event story follow-up counts as deictic', () {
    for (final q in [
      'what about him?',
      'Waaróm deed hij dat?',
      'wat gebeurde er met haar?',
      'what happened?',
      'wat gebeurde er toen?',
    ]) {
      expect(assistantIsDeicticStoryFollowUp(q), isTrue, reason: q);
    }
    for (final q in [
      'what about that one?',
      'waarom die?',
      'why is it buffering?',
      'hoe zit dat met mijn downloads?',
      'wat meten ze?',
      'en voor de kinderen?',
      'wat doet dat?',
    ]) {
      expect(assistantIsDeicticStoryFollowUp(q), isFalse, reason: q);
    }
  });

  test('a pronoun-only story follow-up gets no memory, a plain follow-up keeps it', () async {
    final c = make([_say('Bluey kijk je veel.'), _say('over zijn lot'), _say('ook kinderen')]);
    await c.submit('Wat keek ik het meest?');
    await c.submit('what about him?');
    expect(roles(1, 'assistant'), isEmpty, reason: 'no title in the prompt, so the fence cannot see it');
    await c.submit('en voor de kinderen?');
    expect(roles(2, 'assistant'), isNotEmpty);
  });

  test('a confirmation from an earlier turn confirms nothing new', () async {
    final c = make([_call('wipe'), _say('Verwijderd.'), _call('wipe'), _say('nee')]);
    var done = c.submit('Verwijder Sam');
    while (c.pendingConfirmation == null) {
      await Future<void>.delayed(Duration.zero);
    }
    final first = c.pendingConfirmation!;
    c.confirmTask(first.taskId, first.id);
    await done;
    expect(_executed, 1);

    done = c.submit('ja, doe dat nog een keer');
    while (c.pendingConfirmation == null) {
      await Future<void>.delayed(Duration.zero);
    }
    // The new run raised its own card and nothing ran without the user.
    expect(_executed, 1);
    final second = c.pendingConfirmation!;
    expect(second.id, isNot(first.id));
    c.cancelTaskConfirmation(second.taskId, second.id);
    await done;
    expect(_executed, 1);
  });

  test(
    'newConversation (the button) forgets the memory and the answer on screen, and is offered only with one',
    () async {
      final c = make([_say('a1'), _say('a2')]);
      expect(c.hasConversation, isFalse, reason: 'not in the greeting');
      await c.submit('q1');
      expect(c.hasConversation, isTrue);
      c.newConversation();
      expect(c.hasConversation, isFalse);
      expect(c.conversation, isEmpty);
      expect(c.prompt, isNull);
      expect(c.answer, '');
      expect(c.state, AssistantSurfaceState.idle);

      await c.submit('q2');
      expect(roles(1, 'assistant'), isEmpty, reason: 'the next question starts without q1');
    },
  );

  test('30 minutes after the last answer a summon starts a new conversation, also after a run was parked', () async {
    var now = DateTime(2026, 10, 5, 12);
    final c = make([_say('a1'), _say('a2'), _say('a3')]);
    final session = BigPMobileSession(c, now: () => now);
    addTearDown(session.dispose);

    session.summon();
    await c.submit('q1');
    expect(c.conversation, hasLength(1));

    // Q2 is parked while it runs: the controller goes idle, the memory stays.
    model.gate = Completer();
    final q2 = c.submit('q2');
    await pumpEventQueue();
    session.park();
    model.gate!.complete();
    await q2;
    expect(c.state, AssistantSurfaceState.idle);
    expect(c.conversation, hasLength(1));
    expect(c.hasConversation, isFalse, reason: 'the greeting offers no Nieuw gesprek');

    now = now.add(const Duration(minutes: 31));
    session.summon();
    expect(c.conversation, isEmpty);
    await c.submit('q3');
    expect(roles(model.seen.length - 1, 'assistant'), isEmpty);
  });
}
