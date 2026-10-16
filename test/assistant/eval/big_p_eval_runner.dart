import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_entitlement.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_run.dart';

import 'package:pleya/profiles/household_kids_store.dart';

import 'big_p_eval_cases.dart';
import 'big_p_eval_checks.dart';
import 'big_p_eval_fixtures.dart';

// Runs one eval case through the real AssistantRun, turn by turn, with the
// earlier turns as conversation, exactly as the controller replays them.
// The model is whatever the runner hands in: a scripted fake in CI, a real
// provider in the live runner.

class _Entitled extends AssistantEntitlement {
  const _Entitled();
  @override
  Future<AssistantEntitlementState> check() async => AssistantEntitlementState.entitled;
}

/// Counts model calls and the tokens a provider reports in `usage`.
class EvalMeter {
  int calls = 0;
  int tokens = 0;

  /// The tool answers in the latest request body: what the model was told.
  List<({String tool, String content})> tools = const [];

  /// Reads the tool answers out of a chat request body.
  void observe(String body) {
    try {
      final messages = (jsonDecode(body) as Map)['messages'] as List;
      final names = <String, String>{};
      final found = <({String tool, String content})>[];
      for (final m in messages.cast<Map>()) {
        if (m['role'] == 'assistant') {
          for (final call in (m['tool_calls'] as List? ?? const []).cast<Map>()) {
            names['${call['id']}'] = '${(call['function'] as Map)['name']}';
          }
        } else if (m['role'] == 'tool') {
          found.add((tool: names['${m['tool_call_id']}'] ?? '?', content: '${m['content']}'));
        }
      }
      tools = found;
    } catch (_) {
      // Not a chat body: keep what was seen.
    }
  }
}

/// The household's children for ages in whole years: each born that many
/// years and six months ago, so the age holds for the next five months.
List<HouseholdKid> evalHouseholdKids(List<int> ages) {
  final now = DateTime.now();
  return [
    for (final (i, age) in ages.indexed)
      () {
        final months = now.year * 12 + now.month - 1 - (age * 12 + 6);
        final month = (months % 12 + 1).toString().padLeft(2, '0');
        return HouseholdKid(id: 'k$i', name: 'Kind${i + 1}', birthMonth: '${months ~/ 12}-$month');
      }(),
  ];
}

/// Runs [c]; [modelFor] gives the model client of a turn and [meter] the
/// counter its HTTP client feeds.
Future<EvalOutcome> runEvalCase(
  EvalCase c, {
  required AssistantModelClient Function(int turn) modelFor,
  required EvalMeter meter,
  String region = 'NL',
}) async {
  final outcome = EvalOutcome();
  final world = await c.world?.call();
  final ctx = evalContext(
    kids: c.kids,
    kidsAges: c.kidsAges,
    householdKids: evalHouseholdKids(c.householdKids),
    region: region,
    personal: c.personal,
    world: world,
    onSaveRow: outcome.savedRows.add,
  );
  final history = <AssistantTurn>[];
  for (final (i, turn) in c.turns.indexed) {
    final tools = <String>[];
    var errors = 0;
    meter.tools = const [];
    final callsBefore = meter.calls;
    final tokensBefore = meter.tokens;
    final watch = Stopwatch()..start();
    final run = AssistantRun(
      model: modelFor(i),
      context: ctx,
      confirm: (_) async {
        outcome.confirms++;
        return null;
      },
      entitlement: const _Entitled(),
      conversation: List.of(history),
      userTyped: true,
      onStep: (step) {
        if (step.phase == AssistantStepPhase.started) tools.add(step.tool);
        if (step.phase == AssistantStepPhase.failed) errors++;
      },
    );
    final result = await run.ask(turn.prompt);
    watch.stop();
    outcome.turns.add(
      EvalTurnOutcome(prompt: turn.prompt, result: result)
        ..tools.addAll(tools)
        ..toolErrors = errors
        ..modelCalls = meter.calls - callsBefore
        ..tokens = meter.tokens - tokensBefore
        ..toolResults = meter.tools
        ..latencyMs = watch.elapsedMilliseconds,
    );
    history.add(AssistantTurn(question: turn.prompt, answer: result.text, kids: c.kids));
  }
  return outcome;
}

/// Every hard violation of [c] in [o].
List<String> evalViolations(EvalCase c, EvalOutcome o) => [for (final h in c.hard) ...h.check(o)];

/// A rough language guess from common words, for the soft score.
String evalLanguage(String text) {
  final words = text.toLowerCase().split(RegExp(r'[^a-zà-ÿ]+'));
  const nl = {'de', 'het', 'een', 'en', 'je', 'niet', 'voor', 'van', 'is', 'ik', 'dat', 'of'};
  const en = {'the', 'a', 'and', 'you', 'not', 'for', 'of', 'is', 'i', 'that', 'or', 'to'};
  final n = words.where(nl.contains).length;
  final e = words.where(en.contains).length;
  return n == 0 && e == 0 ? 'unknown' : (n >= e ? 'nl' : 'en');
}

/// One JSON object per run of [c]: hard violations and the soft scores.
Map<String, Object?> evalRecord(EvalCase c, EvalOutcome o, {required String model, required int attempt}) {
  final violations = evalViolations(c, o);
  return {
    'case': c.id,
    'model': model,
    'attempt': attempt,
    'expect_fail': c.expectFail,
    'hard_ok': violations.isEmpty,
    'violations': violations,
    'turns': [
      for (final t in o.turns)
        {
          'prompt': t.prompt,
          'end': t.result.end.name,
          'first_tool': t.tools.firstOrNull,
          'first_tool_ok': c.soft.firstTools.isEmpty || c.soft.firstTools.contains(t.tools.firstOrNull),
          'tools': t.tools,
          'cards': [for (final card in evalCards(t.result)) card.title],
          'unbacked_cards': evalUnbackedCards(t.result),
          'suggestions_wanted': c.soft.suggestions,
          'asks_question': evalAsksQuestion(t.result.text),
          'named_titles': evalNamed(t.result.text).length,
          'card_count': evalCards(t.result).length,
          'tip_ok': c.soft.tip ? evalTipOk(t.result) : null,
          'language': evalLanguage(t.result.text),
          'language_ok': evalLanguage(t.result.text) == c.soft.language,
          'tool_errors': t.toolErrors,
          'model_calls': t.modelCalls,
          'tokens': t.tokens,
          'latency_ms': t.latencyMs,
          'text': t.result.text,
        },
    ],
  };
}

/// Appends [records] as JSON lines to `build/big_p_eval/<name>.jsonl`
/// (ignored by version control) and returns the file.
File evalWriteJsonl(String name, List<Map<String, Object?>> records) {
  final file = File('build/big_p_eval/$name.jsonl')..parent.createSync(recursive: true);
  file.writeAsStringSync([for (final r in records) '${jsonEncode(r)}\n'].join(), mode: FileMode.append);
  return file;
}

/// A model that plays [script]: each reply is an [EvalCall] or text; past
/// the end it repeats the last text. Feeds [meter].
AssistantModelClient evalScriptedModel(List<Object> script, EvalMeter meter) {
  var n = 0;
  return AssistantModelClient(
    const AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://eval.lan', model: 'm'),
    httpClient: MockClient((request) async {
      meter.calls++;
      meter.observe(request.body);
      final step = n < script.length ? script[n] : script.whereType<String>().lastOrNull ?? '';
      n++;
      final message = switch (step) {
        EvalCall(:final name, :final args) => {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'id': 'call_$n',
              'type': 'function',
              'function': {'name': name, 'arguments': jsonEncode(args)},
            },
          ],
        },
        _ => {'role': 'assistant', 'content': '$step'},
      };
      return http.Response(
        jsonEncode({
          'choices': [
            {'message': message},
          ],
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    }),
  );
}
