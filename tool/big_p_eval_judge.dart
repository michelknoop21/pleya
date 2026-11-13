import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// The quality judge of the Big P evaluation set (BP-12).
///
/// The hard checks of the set hold rules; this tool grades what they cannot:
/// whether an answer is true to what the tools returned, answers the
/// question, reads well, and is honest about what could not be done. One
/// judge call per criterion, each with its own instructions, and each verdict
/// is `pass`, `fail` or `unknown`: a judge that may say "I cannot tell" makes
/// up fewer verdicts.
///
/// ```
/// dart run tool/big_p_eval_judge.dart --in build/big_p_eval/live-<stamp>.jsonl \
///   [--out build/big_p_eval/judged-<stamp>.jsonl] [--judge deepseek-v4.1-flash] \
///   [--model glm-5.3-flash] [--case task-] [--limit 20] [--parallel 4]
/// ```
///
/// Calibration against a person: `--sample 25 --labels labels.jsonl` writes
/// 25 judged runs with an empty `human` verdict per criterion to fill in;
/// `--agreement labels.jsonl` then prints, per criterion, how often judge and
/// person agree, and how many of the person's fails the judge caught.
///
/// The judge model answers through Ollama Cloud (`OLLAMA_CLOUD_API`). It is a
/// different model family than the models under test, so it does not grade
/// its own style.

const evalJudgeDefault = 'deepseek-v4.1-flash';

class EvalCriterion {
  const EvalCriterion(this.id, this.question, this.rules);
  final String id;

  /// The one thing this judge decides.
  final String question;
  final String rules;
}

const evalCriteria = <EvalCriterion>[
  EvalCriterion(
    'grounded',
    'Is every factual claim in the answer backed by the evidence?',
    'Evidence is only: the tool results, the cards shown, the actions Pleya carried out and the world state. '
        'FAIL when the answer states something the evidence does not show: a title, a count, a status, a '
        'server state, a watch history, or that something was done, saved, requested, removed or remembered '
        'while no action is listed or the confirmation card was answered with no. FAIL when the answer names a '
        'title as available that is on no card and in no tool result. General knowledge about a film (its '
        'director, its plot) is not a failure unless it contradicts the evidence. PASS when all claims are backed. '
        'An empty answer with cards is PASS.',
  ),
  EvalCriterion(
    'answers',
    'Does the answer, together with the cards, give the user what they asked for?',
    'Judge the kind (film or series), the number asked for, the audience (me, a child, everyone), the period and '
        'the action asked for. FAIL when it answers a different question, gives a different kind, clearly more or '
        'fewer items than asked, asks a counter-question that the evidence already answers, or stops at a '
        'proposal when the user had already said yes and the card was confirmed. PASS when the user gets what '
        'they asked, or when the evidence shows it cannot be given and the answer says so. A confirmation card '
        'that waits for the user is a correct stop for a change the user has not confirmed yet.',
  ),
  EvalCriterion(
    'tone',
    'Does the answer read as a short, natural reply in the language of the question?',
    'FAIL when the language differs from the question, when it is padded (restating the question, apologies, '
        'offers of more help in every answer, several sentences where one would do), when it repeats as a list '
        'the titles the cards already show, when it shows Markdown marks, JSON, tool names, ids or other internals, '
        'or when it talks about itself as an AI model. PASS for a brief, friendly, direct reply. An empty answer '
        'with cards is PASS.',
  ),
  EvalCriterion(
    'honest',
    'When something could not be done or was missing, does the answer say so plainly and help the user on?',
    'Look in the evidence for a limit: a tool error or refusal, a missing source or right, a server that is '
        'offline, a refused confirmation card, no results, a partial result. FAIL when the answer hides the limit, '
        'presents a partial result as complete, or blames the user. FAIL when it names the limit but gives no '
        'usable next step where one clearly exists. PASS when the limit is named in plain words. PASS also when '
        'the evidence shows no limit at all: then there was nothing to be honest about.',
  ),
];

/// What the judge reads about one run: the conversation, what the tools
/// returned, what the user saw and what Pleya did.
String evalEvidence(Map<String, Object?> record) {
  final b = StringBuffer();
  if (record['kids'] == true) b.writeln("Profile: a children's profile.");
  final before = record['state_before'];
  if (before != null) b.writeln('World before: ${jsonEncode(before)}');
  final turns = (record['turns'] as List? ?? const []).cast<Map>();
  for (final (i, t) in turns.indexed) {
    b.writeln('--- Turn ${i + 1} ---');
    b.writeln('User: ${t['prompt']}');
    final trace = (t['tool_results'] as List?) ?? (t['tool_trace'] as List?) ?? const [];
    if (trace.isEmpty) {
      b.writeln('Tool results: none (no tool was called)');
    } else {
      b.writeln('Tool results, in order:');
      for (final line in trace) {
        b.writeln('  $line');
      }
    }
    final displays = (t['displays'] as List?)?.cast<Map>();
    if (displays != null && displays.isNotEmpty) {
      b.writeln('Cards shown to the user:');
      for (final d in displays) {
        final cards = (d['cards'] as List? ?? const []).cast<Map>();
        b.writeln(
          '  ${d['type']}: ${cards.isEmpty ? jsonEncode(d) : cards.map((c) => '${c['title']}${c['year'] == null ? '' : ' (${c['year']})'} [${c['kind']}]').join('; ')}',
        );
      }
    } else {
      final cards = (t['cards'] as List?) ?? const [];
      b.writeln(cards.isEmpty ? 'Cards shown to the user: none' : 'Cards shown to the user: ${cards.join('; ')}');
    }
    final confirm = [
      for (final c in (record['confirm_cards'] as List? ?? const []).cast<Map>())
        if (c['turn'] == i) c,
    ];
    for (final c in confirm) {
      b.writeln(
        'Confirmation card: ${c['kind']} "${c['subject']}" ${jsonEncode(c['items'])}, the user answered ${c['yes'] == true ? 'YES' : 'NO'}',
      );
    }
    final actions = (t['actions'] as List?) ?? const [];
    b.writeln(
      actions.isEmpty ? 'Actions carried out by Pleya: none' : 'Actions carried out by Pleya: ${jsonEncode(actions)}',
    );
    if (t['state_after'] != null) b.writeln('World after: ${jsonEncode(t['state_after'])}');
    if (t['kids_ages_needed'] == true || t['household_kids_needed'] == true) {
      b.writeln("Pleya showed its own card asking for the children's ages instead of an answer.");
    }
    final shown = '${t['lead_shown'] ?? t['answer_shown'] ?? t['text'] ?? ''}';
    b.writeln('Answer shown to the user: ${shown.trim().isEmpty ? '(empty)' : shown}');
    final full = '${t['answer_shown'] ?? t['text'] ?? ''}';
    if (t['lead_shown'] != null && full.trim() != shown.trim()) {
      b.writeln(
        '(The app hid a list of titles from the answer because the cards show them. The full answer was: $full)',
      );
    }
  }
  return b.toString();
}

String evalJudgePrompt(EvalCriterion c, Map<String, Object?> record) =>
    'You grade one answer of Big P, the assistant inside the media app Pleya. Users ask about films and series '
    'in their own libraries and ask Big P to do things. Grade ONLY this one criterion and nothing else.\n\n'
    'Criterion "${c.id}": ${c.question}\n${c.rules}\n\n'
    'Grade the LAST turn; earlier turns are context. If the evidence is not enough to decide, answer unknown; '
    'do not guess.\n\n'
    'Reply with one JSON object and nothing else: '
    '{"verdict": "pass" | "fail" | "unknown", "reason": "<one sentence, quote the words that decide it>"}\n\n'
    '=== Evidence ===\n${evalEvidence(record)}';

/// The verdict in a judge reply, or `unknown` when it is not one.
({String verdict, String reason}) evalParseVerdict(String reply) {
  final start = reply.indexOf('{');
  final end = reply.lastIndexOf('}');
  if (start >= 0 && end > start) {
    try {
      final m = jsonDecode(reply.substring(start, end + 1)) as Map;
      final v = '${m['verdict']}'.toLowerCase().trim();
      if (v == 'pass' || v == 'fail' || v == 'unknown') return (verdict: v, reason: '${m['reason'] ?? ''}');
    } catch (_) {
      // falls through
    }
  }
  return (verdict: 'unknown', reason: 'unreadable judge reply');
}

typedef EvalAsk = Future<String> Function(String prompt);

/// Judges [record] on every criterion with [ask].
Future<Map<String, Object?>> evalJudgeRecord(Map<String, Object?> record, EvalAsk ask, {required String judge}) async {
  final verdicts = <String, Object?>{};
  for (final c in evalCriteria) {
    ({String verdict, String reason}) v;
    try {
      v = evalParseVerdict(await ask(evalJudgePrompt(c, record)));
    } catch (e) {
      v = (verdict: 'unknown', reason: 'judge error: ${e.runtimeType}');
    }
    verdicts[c.id] = {'verdict': v.verdict, 'reason': v.reason};
  }
  return {
    'case': record['case'],
    'model': record['model'],
    'attempt': record['attempt'],
    'label': record['label'],
    'git_sha': record['git_sha'],
    'hard_ok': record['hard_ok'],
    'judge': judge,
    'verdicts': verdicts,
  };
}

/// Per model and criterion: pass, fail and unknown counts, then the failing
/// runs with the judge's reason.
String evalJudgeSummary(List<Map<String, Object?>> judged) {
  final b = StringBuffer();
  final models = {for (final j in judged) '${j['model']}'}.toList()..sort();
  b.writeln('| model | criterium | goed | fout | onbekend | cases altijd goed |');
  b.writeln('| --- | --- | --- | --- | --- | --- |');
  for (final m in models) {
    final rows = judged.where((j) => j['model'] == m).toList();
    for (final c in evalCriteria) {
      var pass = 0, fail = 0, unknown = 0;
      final perCase = <String, List<String>>{};
      for (final r in rows) {
        final v = '${((r['verdicts'] as Map)[c.id] as Map)['verdict']}';
        (perCase['${r['case']}'] ??= []).add(v);
        if (v == 'pass') {
          pass++;
        } else if (v == 'fail') {
          fail++;
        } else {
          unknown++;
        }
      }
      final always = perCase.values.where((v) => v.every((x) => x == 'pass')).length;
      b.writeln('| $m | ${c.id} | $pass | $fail | $unknown | $always van ${perCase.length} |');
    }
  }
  b.writeln();
  for (final j in judged) {
    final fails = [
      for (final e in (j['verdicts'] as Map).entries)
        if ((e.value as Map)['verdict'] == 'fail') '${e.key}: ${(e.value as Map)['reason']}',
    ];
    if (fails.isNotEmpty) b.writeln('- ${j['model']} ${j['case']} #${j['attempt']}: ${fails.join(' | ')}');
  }
  return b.toString();
}

/// Agreement of judge and person over [labels]: rows of a judged record with
/// a `human` map of criterion to `pass`, `fail` or null (not labelled).
String evalAgreement(List<Map<String, Object?>> labels) {
  final b = StringBuffer();
  b.writeln('| criterium | gelabeld | eens | fouten van de mens gevonden | goedkeuringen van de mens bevestigd |');
  b.writeln('| --- | --- | --- | --- | --- |');
  for (final c in evalCriteria) {
    var n = 0, agree = 0, humanFail = 0, caught = 0, humanPass = 0, kept = 0;
    for (final row in labels) {
      final human = (row['human'] as Map?)?[c.id];
      if (human != 'pass' && human != 'fail') continue;
      final judge = ((row['verdicts'] as Map)[c.id] as Map)['verdict'];
      n++;
      if (judge == human) agree++;
      if (human == 'fail') {
        humanFail++;
        if (judge == 'fail') caught++;
      } else {
        humanPass++;
        if (judge == 'pass') kept++;
      }
    }
    b.writeln('| ${c.id} | $n | $agree | $caught van $humanFail | $kept van $humanPass |');
  }
  return b.toString();
}

List<Map<String, Object?>> _read(String path) => [
  for (final line in File(path).readAsLinesSync())
    if (line.trim().isNotEmpty) (jsonDecode(line) as Map).cast<String, Object?>(),
];

EvalAsk _ollama(String judge, http.Client client) => (prompt) async {
  final key = Platform.environment['OLLAMA_CLOUD_API'] ?? '';
  for (var attempt = 0; ; attempt++) {
    final resp = await client
        .post(
          Uri.parse('https://ollama.com/v1/chat/completions'),
          headers: {'content-type': 'application/json', 'authorization': 'Bearer $key'},
          body: jsonEncode({
            'model': judge,
            'temperature': 0,
            'messages': [
              {'role': 'user', 'content': prompt},
            ],
          }),
        )
        .timeout(const Duration(minutes: 3));
    if (resp.statusCode == 200) {
      final body = jsonDecode(utf8.decode(resp.bodyBytes)) as Map;
      return '${((body['choices'] as List).first as Map)['message']['content']}';
    }
    if (attempt >= 3 || (resp.statusCode != 429 && resp.statusCode < 500)) {
      throw HttpException('judge HTTP ${resp.statusCode}');
    }
    await Future<void>.delayed(Duration(seconds: 2 << attempt));
  }
};

Future<void> main(List<String> args) async {
  exitCode = await evalJudgeMain(args);
}

Future<int> evalJudgeMain(List<String> args, {EvalAsk? ask}) async {
  final opt = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    if (!args[i].startsWith('--') || i + 1 >= args.length) {
      stderr.writeln('Onbekende of onvolledige optie ${args[i]}');
      return 64;
    }
    opt[args[i].substring(2)] = args[++i];
  }
  if (opt['agreement'] case final path?) {
    stdout.write(evalAgreement(_read(path)));
    return 0;
  }
  final input = opt['in'];
  if (input == null) {
    stderr.writeln(
      'Gebruik: dart run tool/big_p_eval_judge.dart --in runs.jsonl [--out judged.jsonl] [--judge model] '
      '[--model m] [--case prefix] [--limit n] [--parallel n] [--sample n --labels labels.jsonl] | --agreement labels.jsonl',
    );
    return 64;
  }
  final judge = opt['judge'] ?? evalJudgeDefault;
  var records = [
    for (final r in _read(input))
      if (r['infra_error'] != true &&
          (opt['model'] == null || r['model'] == opt['model']) &&
          (opt['case'] == null || '${r['case']}'.startsWith(opt['case']!)))
        r,
  ];
  final limit = int.tryParse(opt['limit'] ?? '');
  if (limit != null && records.length > limit) records = records.sublist(0, limit);
  final client = http.Client();
  final asker = ask ?? _ollama(judge, client);
  final parallel = (int.tryParse(opt['parallel'] ?? '') ?? 4).clamp(1, 16);
  final judged = List<Map<String, Object?>?>.filled(records.length, null);
  var next = 0;
  Future<void> worker() async {
    while (true) {
      final i = next++;
      if (i >= records.length) return;
      judged[i] = await evalJudgeRecord(records[i], asker, judge: judge);
      stderr.write('.');
    }
  }

  await Future.wait([for (var w = 0; w < parallel; w++) worker()]);
  stderr.writeln();
  client.close();
  final done = judged.whereType<Map<String, Object?>>().toList();
  final out = opt['out'] ?? input.replaceFirst(RegExp(r'\.jsonl$'), '.judged.jsonl');
  File(out).writeAsStringSync([for (final j in done) '${jsonEncode(j)}\n'].join());
  stdout.write(evalJudgeSummary(done));
  stdout.writeln('\nGeschreven: $out');
  final sample = int.tryParse(opt['sample'] ?? '');
  if (sample != null && opt['labels'] != null) {
    // Spread over verdicts: every fail first, then passes, so a person sees both.
    final fails = [
      for (final (i, j) in done.indexed)
        if ((j['verdicts'] as Map).values.any((v) => (v as Map)['verdict'] != 'pass')) i,
    ];
    final rest = [
      for (var i = 0; i < done.length; i++)
        if (!fails.contains(i)) i,
    ];
    final half = (sample / 2).ceil();
    final pick = [...fails.take(half), ...rest.take(sample - fails.take(half).length)];
    File(opt['labels']!).writeAsStringSync(
      [
        for (final i in pick)
          '${jsonEncode({
            ...done[i],
            'evidence': evalEvidence(records[i]),
            'human': {for (final c in evalCriteria) c.id: null},
          })}\n',
      ].join(),
    );
    stdout.writeln('IJkset: ${opt['labels']} (${pick.length} runs)');
  }
  return 0;
}
