import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_entitlement.dart';
import 'package:pleya/assistant/assistant_memory.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/i18n/strings.g.dart';

import 'package:pleya/profiles/household_kids_store.dart';

import 'package:pleya/widgets/big_p/assistant/big_p_labels.dart';

import '../../widgets/big_p/fake_assistant_controller.dart';
import 'big_p_eval_cases.dart';
import 'big_p_eval_checks.dart';
import 'big_p_eval_fixtures.dart';
import 'big_p_eval_world.dart';

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

  /// Status and start of the body of the latest non-200 answer, for the record.
  String? lastError;

  /// The tool answers in the latest request body: what the model was told.
  List<({String tool, String content})> tools = const [];

  /// The same calls with the arguments the model sent and the start of the
  /// answer, one line each, for the record.
  List<String> trace = const [];

  /// The same calls in full for the judge: tool, arguments and the answer up
  /// to 3000 characters.
  List<String> full = const [];

  /// Reads the tool answers out of a chat request body.
  void observe(String body) {
    try {
      final messages = (jsonDecode(body) as Map)['messages'] as List;
      final names = <String, String>{};
      final argsOf = <String, String>{};
      final found = <({String tool, String content})>[];
      for (final m in messages.cast<Map>()) {
        if (m['role'] == 'assistant') {
          for (final call in (m['tool_calls'] as List? ?? const []).cast<Map>()) {
            names['${call['id']}'] = '${(call['function'] as Map)['name']}';
            argsOf['${call['id']}'] = '${(call['function'] as Map)['arguments']}';
          }
        } else if (m['role'] == 'tool') {
          found.add((tool: names['${m['tool_call_id']}'] ?? '?', content: '${m['content']}'));
        }
      }
      tools = found;
      full = [
        for (final m in messages.cast<Map>())
          if (m['role'] == 'tool')
            () {
              final id = '${m['tool_call_id']}';
              final body = '${m['content']}';
              return '${names[id] ?? '?'} ${argsOf[id] ?? ''} -> ${body.length > 3000 ? '${body.substring(0, 3000)}…' : body}';
            }(),
      ];
      trace = [
        for (final m in messages.cast<Map>())
          if (m['role'] == 'tool')
            () {
              final id = '${m['tool_call_id']}';
              final body = '${m['content']}';
              return '${names[id] ?? '?'} ${argsOf[id] ?? ''} -> ${body.length > 300 ? body.substring(0, 300) : body}';
            }(),
      ];
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
  // Pleya's own lines (memory, an offline server) come out in the language
  // of the set, as they do on a Dutch device.
  await LocaleSettings.setLocale(AppLocale.nl);
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
  outcome.initial = await evalWorldState(world, outcome);
  for (final (i, turn) in c.turns.indexed) {
    final tools = <String>[];
    var errors = 0;
    meter.tools = const [];
    meter.trace = const [];
    meter.full = const [];
    final callsBefore = meter.calls;
    final tokensBefore = meter.tokens;
    final watch = Stopwatch()..start();
    final run = AssistantRun(
      model: modelFor(i),
      context: ctx,
      confirm: (action) async {
        outcome.confirms++;
        final yes = turn.confirm == EvalConfirm.yes;
        if (yes) outcome.confirmed++;
        outcome.cards.add((
          turn: i,
          kind: action.kind.name,
          subject: action.subject,
          items: List.of(action.items),
          yes: yes,
        ));
        return yes ? const AssistantConfirmation() : null;
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
        ..trace = meter.trace
        ..full = meter.full
        ..latencyMs = watch.elapsedMilliseconds,
    );
    // Memory changes wait on a Pleya card after the answer (the controller
    // settles them); the user's answer of this turn decides them here.
    for (final proposal in result.memoryProposals) {
      outcome.confirms++;
      final yes = turn.confirm == EvalConfirm.yes;
      outcome.cards.add((
        turn: i,
        kind: 'memory_${proposal.kind.name}',
        subject: proposal.target?.value ?? proposal.value ?? '',
        items: const [],
        yes: yes,
      ));
      if (yes) {
        outcome.confirmed++;
        final applied = await applyMemoryProposal(proposal);
        outcome.memoryOutcomes.add(applied.code);
      }
    }
    history.add(AssistantTurn(question: turn.prompt, answer: result.text, kids: c.kids));
    outcome.states.add(await evalWorldState(world, outcome));
  }
  return outcome;
}

/// The eval world as plain data: saved Home rows, Seerr requests sent and
/// the asking profile's memory.
Future<EvalWorldState> evalWorldState(EvalWorld? world, EvalOutcome outcome) async {
  final memory = world?.memory == null
      ? null
      : (world!.memoryOfSecond ? world.memory!.sanne.service : world.memory!.michel.service);
  return EvalWorldState(
    homeRows: List.of(outcome.savedRows),
    requests: [
      for (final post in world?.seerr?.posts ?? const <({String path, Map<String, Object?> body})>[])
        if (post.path == '/request') '${post.body['mediaType']}:${post.body['mediaId']}',
    ],
    cancelledRequests: [
      for (final path in world?.seerr?.deletes ?? const <String>[])
        if (path.startsWith('/request/')) path.substring('/request/'.length),
    ],
    memory: memory == null ? const [] : [for (final f in await memory.list()) f.value],
    // A deep copy: the state object keeps changing over the turns.
    admin: world?.admin == null ? const {} : (jsonDecode(jsonEncode(world!.admin!.toJson())) as Map).cast(),
  );
}

/// One display as plain data, enough to rebuild what the user sees.
Map<String, Object?> evalDisplay(AssistantDisplay d) => switch (d) {
  AssistantMediaGrid(:final entries) => {
    'type': 'grid',
    'cards': [
      for (final e in entries) {'title': e.item.title ?? '', 'year': e.item.year, 'kind': e.item.kind.name},
    ],
  },
  AssistantTitleMatches(:final matches) => {
    'type': 'matches',
    'cards': [
      for (final m in matches)
        {
          'title': m.title,
          'year': m.year,
          'kind': m.kind,
          'actionable': m.targets.isNotEmpty || m.request != null,
          'requestable': m.request != null,
        },
    ],
  },
  AssistantRequestOptions(:final options) => {
    'type': 'request_options',
    'cards': [
      for (final o in options) {'title': o.title, 'year': o.year, 'kind': o.kind, 'status': o.status},
    ],
  },
  AssistantClarification(:final question, :final options) => {
    'type': 'clarification',
    'question': question,
    'options': options,
  },
  _ => {'type': d.runtimeType.toString()},
};

/// The answer as the controller hands it to the panel for a plain result:
/// a stored or refused memory line first, then the model's text.
String evalShown(AssistantRunResult r) {
  if (r.kidsAgesNeeded || r.householdKidsNeeded || r.ageFilterNotice) return '';
  try {
    return assistantMemoryAnswer(r, r.text);
  } catch (_) {
    return r.text; // translations not loaded in this runner
  }
}

/// The line above the cards as the panel draws it for [r]: the real label
/// code over a controller that holds this result.
String evalLead(AssistantRunResult r) {
  final shown = evalShown(r);
  if (shown.isEmpty) return '';
  final c = FakeAssistantController()
    ..answer = shown
    ..displays = List.of(r.displays)
    ..actions = List.of(r.actions)
    ..lastEnd = r.end
    ..resultIsError = r.end != AssistantRunEnd.answered;
  try {
    return r.displays.isEmpty ? assistantHeadline(c) : assistantCardsLead(c);
  } catch (_) {
    return shown;
  } finally {
    c.dispose();
  }
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

// vault-exec hands its child a cleaned environment, so BIG_P_EVAL_* may not
// arrive as environment variables; `flutter test --dart-define=BIG_P_EVAL_LABEL=x`
// does. The environment wins when both are set.
const _defineSha = String.fromEnvironment('BIG_P_EVAL_SHA');
const _defineLabel = String.fromEnvironment('BIG_P_EVAL_LABEL');

/// The run label for the A/B report, or null.
String? evalLabel() {
  final env = Platform.environment['BIG_P_EVAL_LABEL'];
  final value = env != null && env.isNotEmpty ? env : _defineLabel;
  return value.isEmpty ? null : value;
}

String? _evalSha;

/// The checkout the run came from, so two runs can be told apart in the A/B
/// report: `BIG_P_EVAL_SHA`, else the short HEAD sha, `+dirty` with local
/// changes, `unknown` outside git.
String evalGitSha() => _evalSha ??= () {
  final env = Platform.environment['BIG_P_EVAL_SHA'];
  if (env != null && env.isNotEmpty) return env;
  if (_defineSha.isNotEmpty) return _defineSha;
  try {
    final head = Process.runSync('git', ['rev-parse', '--short', 'HEAD']);
    if (head.exitCode != 0) return 'unknown';
    final dirty = Process.runSync('git', ['status', '--porcelain', '--untracked-files=no']);
    return '${(head.stdout as String).trim()}${(dirty.stdout as String).trim().isEmpty ? '' : '+dirty'}';
  } catch (_) {
    return 'unknown';
  }
}();

/// One JSON object per run of [c]: hard violations and the soft scores.
Map<String, Object?> evalRecord(EvalCase c, EvalOutcome o, {required String model, required int attempt}) {
  final violations = evalViolations(c, o);
  return {
    'case': c.id,
    'git_sha': evalGitSha(),
    'label': evalLabel(),
    // A run that ended in a provider error says nothing about Pleya or the
    // model's answers; the A/B report leaves it out.
    'infra_error': o.turns.any((t) => t.result.providerError != null),
    'model': model,
    'attempt': attempt,
    'expect_fail': c.expectFail,
    'hard_ok': violations.isEmpty,
    'violations': violations,
    'source': c.source,
    'kids': c.kids,
    'confirm_cards': [
      for (final card in o.cards)
        {'turn': card.turn, 'kind': card.kind, 'subject': card.subject, 'items': card.items, 'yes': card.yes},
    ],
    'state_before': o.initial.toJson(),
    'memory_outcomes': o.memoryOutcomes,
    'turns': [
      for (final t in o.turns)
        {
          'prompt': t.prompt,
          'end': t.result.end.name,
          'provider_error': t.result.providerError?.name,
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
          'tool_trace': t.trace,
          'model_calls': t.modelCalls,
          'tokens': t.tokens,
          'latency_ms': t.latencyMs,
          'text': t.result.text,
          // What the panel shows: the controller's own lines for the memory,
          // then the model's text (assistant_controller_task.dart).
          'answer_shown': evalShown(t.result),
          // What stands above the cards on screen: the answer without the
          // titles the cards already show (assistantCardsLead).
          'lead_shown': evalLead(t.result),
          'tool_results': t.full,
          'displays': [for (final d in t.result.displays) evalDisplay(d)],
          'actions': [
            for (final a in t.result.actions) {'kind': a.kind.name, 'server': a.serverName, 'subject': a.subject},
          ],
          'confirm': c.turns[o.turns.indexOf(t)].confirm.name,
          'split_tasks': t.result.splitTasks.length,
          'kids_ages_needed': t.result.kidsAgesNeeded,
          'household_kids_needed': t.result.householdKidsNeeded,
          'age_filter_notice': t.result.ageFilterNotice,
          'memory_proposals': t.result.memoryProposals.length,
          'memory_stored': [for (final f in t.result.memoryStored) f.value],
          'state_after': o.states.length > o.turns.indexOf(t) ? o.states[o.turns.indexOf(t)].toJson() : null,
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
