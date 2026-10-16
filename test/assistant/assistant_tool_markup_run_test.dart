import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_entitlement.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_labels.dart';

import 'assistant_find_fakes.dart';

// BP-11 (tvOS, 16 Oct 2026): the model wrote its tool call as message text
// and the answer bubble showed the raw markup. Markup is never shown, never
// executed and never kept as a turn: one correction round, then Pleya's line.

const _markup = '<atem:function_calls>\n<atem:invoke name="my_watching.*">\n</atem:invoke>\n</atem:function_calls>';

class _Entitled extends AssistantEntitlement {
  const _Entitled();
  @override
  Future<AssistantEntitlementState> check() async => AssistantEntitlementState.entitled;
}

class _Server extends FakeServer {
  _Server(super.id);
  @override
  Future<HealthStatus> checkHealth() async => HealthStatus.online;
}

AssistantToolContext _ctx() {
  final m = MultiServerManager();
  addTearDown(m.dispose);
  m.debugRegisterClientForTesting(_Server('w'));
  m.setVisibleServerIds(null);
  return AssistantToolContext(servers: m, kidsProfile: () async => false);
}

Map<String, Object?> _reply(Object step, int n) => step is String
    ? {'role': 'assistant', 'content': step}
    : {
        'role': 'assistant',
        'content': '',
        'tool_calls': [
          {
            'id': 'c$n',
            'type': 'function',
            'function': {'name': (step as Map)['name'], 'arguments': jsonEncode(step['args'])},
          },
        ],
      };

({AssistantModelClient model, List<List<Map<String, Object?>>> sent}) _script(List<Object> script) {
  final sent = <List<Map<String, Object?>>>[];
  final model = AssistantModelClient(
    const AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://o.lan', model: 'm'),
    httpClient: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      sent.add((body['messages'] as List).cast());
      return jsonResponse({
        'choices': [
          {'message': _reply(script[sent.length - 1], sent.length)},
        ],
      });
    }),
  );
  return (model: model, sent: sent);
}

Future<AssistantRunResult> _ask(AssistantModelClient model, {int maxSteps = 6}) => AssistantRun(
  model: model,
  context: _ctx(),
  confirm: (_) async => null,
  entitlement: const _Entitled(),
  maxSteps: maxSteps,
).ask('Welke comedy staat niet op mijn bibliotheek?');

const _listServers = {'name': 'list_servers', 'args': <String, Object?>{}};

bool _carriesMarkup(List<Map<String, Object?>> messages) =>
    messages.any((m) => '${m['content']}'.contains('invoke') || '${m['content']}'.contains('function_calls'));

void main() {
  test('markup, then a proper tool call: the tool runs and the markup never reaches the answer', () async {
    final m = _script([_markup, _listServers, 'Je server w is online.']);
    final r = await _ask(m.model);
    expect(m.sent, hasLength(3));
    // The correction is Pleya's, and the markup is not replayed as an answer.
    expect(m.sent[1].last['role'], 'system');
    expect(m.sent[1].last['content'], contains('tools interface'));
    expect(_carriesMarkup(m.sent[1]), isFalse);
    expect(_carriesMarkup(m.sent[2]), isFalse);
    expect(m.sent[2].where((msg) => msg['role'] == 'tool'), hasLength(1), reason: 'list_servers ran');
    expect(r.end, AssistantRunEnd.answered);
    expect(r.error, isNull);
    expect(r.text, 'Je server w is online.');
  });

  test('markup twice: failure code, nothing done, no model text', () async {
    final m = _script([_markup, _markup, 'nooit gevraagd']);
    final r = await _ask(m.model);
    expect(m.sent, hasLength(2), reason: 'one correction round only');
    expect(r.error, 'malformed_tool_call');
    expect(r.text, isEmpty);
    expect(r.actions, isEmpty);
    expect(m.sent.expand((s) => s).where((msg) => msg['role'] == 'tool'), isEmpty, reason: 'nothing executed');
  });

  test('markup on the last step: no correction round left, the failure ends it', () async {
    final m = _script([_markup, 'nooit gevraagd']);
    final r = await _ask(m.model, maxSteps: 1);
    expect(m.sent, hasLength(1));
    expect(r.error, 'malformed_tool_call');
    expect(r.text, isEmpty);
  });

  test('the controller shows Pleya\'s line and keeps no turn for the next question', () async {
    final m = _script([_markup, _markup]);
    final ctx = _ctx();
    final c = AssistantController(
      buildContext: (_) => ctx,
      entitlement: const _Entitled(),
      loadConfig: () async =>
          const AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://o.lan', model: 'm'),
      modelFor: (_) => m.model,
      languageName: () => 'Dutch',
    );
    addTearDown(c.dispose);
    await c.submit('Welke comedy staat niet op mijn bibliotheek?');
    final task = c.tasks.single;
    expect(task.answer, isEmpty);
    expect(assistantTaskAnswer(task), contains(t.assistant.ends.malformedToolCall));
    expect(assistantTaskAnswer(task), isNot(contains('<')));
    expect(c.conversation, isEmpty);
  });

  test('negative control: a plain answer with angle brackets is shown as is', () async {
    final m = _script(['De film <Untitled> staat niet op je server.']);
    final r = await _ask(m.model);
    expect(m.sent, hasLength(1));
    expect(r.error, isNull);
    expect(r.text, 'De film <Untitled> staat niet op je server.');
  });
}
