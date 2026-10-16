import 'dart:convert';
import 'dart:io';

/// A/B report of two Big P evaluation runs (BP-11a2).
///
/// Reads two JSONL files written by the live runner
/// (`build/big_p_eval/*.jsonl`, one `evalRecord` per run), groups the records
/// by case and model and prints how the candidate differs from the base:
/// passed, improved, regressed, and per failing case the violations, the
/// first tool, the change A to B, the median latency and the tokens.
///
/// A/B between two versions of the code: check out the base in a worktree,
/// run the live test there and here with `BIG_P_EVAL_LABEL` set, then
///
/// ```
/// git worktree add ../bp-base <base-sha>
/// (cd ../bp-base && BIG_P_EVAL_LABEL=base vault-exec OLLAMA_CLOUD_API --env-var OLLAMA_CLOUD_API -- \
///   flutter test --tags live-model --run-skipped test/assistant/eval/big_p_eval_live_test.dart)
/// BIG_P_EVAL_LABEL=candidate vault-exec OLLAMA_CLOUD_API --env-var OLLAMA_CLOUD_API -- \
///   flutter test --tags live-model --run-skipped test/assistant/eval/big_p_eval_live_test.dart
/// dart run tool/big_p_eval_report.dart --base ../bp-base/build/big_p_eval/<file>.jsonl \
///   --candidate build/big_p_eval/<file>.jsonl [--model <name>] [--strict]
/// ```
///
/// A group passes when every attempt held all hard checks, is flaky when only
/// some did, and fails when none did. A case marked `expect_fail` is a known
/// bug: it counts as known, not as failed, and shows up as improved once it
/// holds again. `--strict` exits 1 when there is a regression.

enum EvalGroupStatus { pass, flaky, fail }

/// All attempts of one case on one model.
class EvalGroup {
  EvalGroup(this.caseId, this.model, this.records);
  final String caseId;
  final String model;
  final List<Map<String, Object?>> records;

  String? get expectFail => records.map((r) => r['expect_fail'] as String?).whereType<String>().firstOrNull;
  bool get known => expectFail != null;
  int get attempts => records.length;
  int get passed => records.where((r) => r['hard_ok'] == true).length;

  EvalGroupStatus get status => passed == attempts
      ? EvalGroupStatus.pass
      : passed == 0
      ? EvalGroupStatus.fail
      : EvalGroupStatus.flaky;

  Set<String> get violations => {for (final r in records) ...((r['violations'] as List?) ?? const []).map((v) => '$v')};

  /// The tool most attempts called first, or null when none called one.
  String? get firstTool {
    final counts = <String, int>{};
    for (final r in records) {
      final tool = _turns(r).map((t) => t['first_tool']).whereType<String>().firstOrNull;
      if (tool != null) counts[tool] = (counts[tool] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    return (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
  }

  /// Whether every attempt opened with a tool the case lists as good.
  bool get firstToolOk => records.every((r) => _turns(r).every((t) => t['first_tool_ok'] != false));

  int get medianLatencyMs => _median([for (final r in records) _sum(r, 'latency_ms')]);
  int get medianTokens => _median([for (final r in records) _sum(r, 'tokens')]);

  static List<Map<String, Object?>> _turns(Map<String, Object?> r) =>
      ((r['turns'] as List?) ?? const []).whereType<Map>().map((m) => m.cast<String, Object?>()).toList();

  static int _sum(Map<String, Object?> r, String key) =>
      _turns(r).fold(0, (a, t) => a + ((t[key] as num?)?.toInt() ?? 0));

  static int _median(List<int> values) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort();
    return sorted[sorted.length ~/ 2];
  }
}

typedef EvalGroupKey = ({String caseId, String model});

Map<EvalGroupKey, EvalGroup> evalGroups(List<Map<String, Object?>> records, {String? model}) {
  final by = <EvalGroupKey, List<Map<String, Object?>>>{};
  for (final r in records) {
    final m = '${r['model']}';
    if (model != null && m != model) continue;
    by.putIfAbsent((caseId: '${r['case']}', model: m), () => []).add(r);
  }
  return {for (final e in by.entries) e.key: EvalGroup(e.key.caseId, e.key.model, e.value)};
}

/// One case/model seen in both runs.
class EvalChange {
  EvalChange(this.base, this.candidate);
  final EvalGroup base;
  final EvalGroup candidate;

  /// Higher is better; a known bug that holds again counts as a pass.
  static int _rank(EvalGroup g) => switch (g.status) {
    EvalGroupStatus.pass => 2,
    EvalGroupStatus.flaky => 1,
    EvalGroupStatus.fail => 0,
  };

  int get delta => _rank(candidate) - _rank(base);
  Set<String> get newViolations => candidate.violations.difference(base.violations);
  Set<String> get fixedViolations => base.violations.difference(candidate.violations);
}

class EvalDiff {
  EvalDiff(this.base, this.candidate) {
    for (final key in candidate.keys) {
      final b = base[key];
      if (b == null) {
        onlyCandidate.add(candidate[key]!);
      } else {
        both.add(EvalChange(b, candidate[key]!));
      }
    }
    for (final key in base.keys) {
      if (!candidate.containsKey(key)) onlyBase.add(base[key]!);
    }
    int order(EvalGroup a, EvalGroup b) => '${a.model}/${a.caseId}'.compareTo('${b.model}/${b.caseId}');
    both.sort((a, b) => order(a.candidate, b.candidate));
    onlyBase.sort(order);
    onlyCandidate.sort(order);
  }

  final Map<EvalGroupKey, EvalGroup> base;
  final Map<EvalGroupKey, EvalGroup> candidate;
  final both = <EvalChange>[];
  final onlyBase = <EvalGroup>[];
  final onlyCandidate = <EvalGroup>[];

  List<EvalChange> get improved => [
    for (final c in both)
      if (c.delta > 0) c,
  ];
  List<EvalChange> get regressed => [
    for (final c in both)
      if (c.delta < 0) c,
  ];

  /// Groups of [side] that count towards "passed x/N": cases not marked known.
  static (int, int) score(Iterable<EvalGroup> groups) {
    final counted = groups.where((g) => !g.known).toList();
    return (counted.where((g) => g.status == EvalGroupStatus.pass).length, counted.length);
  }

  String render() {
    final out = StringBuffer();
    final (bp, bn) = score(base.values);
    final (cp, cn) = score(candidate.values);
    out
      ..writeln('Big P eval: base ${_runLabel(base)} -> candidate ${_runLabel(candidate)}')
      ..writeln('geslaagd   base $bp/$bn   candidate $cp/$cn')
      ..writeln('verbeterd  ${improved.length}   regressies ${regressed.length}')
      ..writeln(
        'bekende fouten (expect_fail): base ${base.values.where((g) => g.known).length}'
        ', candidate ${candidate.values.where((g) => g.known).length}',
      );
    if (improved.isNotEmpty) {
      out.writeln('\nVerbeterd:');
      for (final c in improved) {
        out.writeln('  ${_id(c.candidate)}  ${_status(c.base)} -> ${_status(c.candidate)}');
      }
    }
    if (regressed.isNotEmpty) {
      out.writeln('\nRegressies:');
      for (final c in regressed) {
        out.writeln('  ${_id(c.candidate)}  ${_status(c.base)} -> ${_status(c.candidate)}');
        _detail(out, c.candidate, other: c.base);
      }
    }
    final stillFailing = [
      for (final c in both)
        if (c.delta == 0 && c.candidate.status != EvalGroupStatus.pass && !c.candidate.known) c,
    ];
    if (stillFailing.isNotEmpty) {
      out.writeln('\nBlijft mislukt:');
      for (final c in stillFailing) {
        out.writeln('  ${_id(c.candidate)}  ${_status(c.candidate)}');
        _detail(out, c.candidate, other: c.base);
      }
    }
    final known = [
      for (final c in both)
        if (c.candidate.known && c.candidate.status != EvalGroupStatus.pass) c,
    ];
    if (known.isNotEmpty) {
      out.writeln('\nBekend (expect_fail):');
      for (final c in known) {
        out.writeln('  ${_id(c.candidate)}  ${c.candidate.expectFail}');
      }
    }
    if (onlyCandidate.isNotEmpty) {
      out.writeln('\nAlleen in candidate: ${onlyCandidate.map(_id).join(', ')}');
    }
    if (onlyBase.isNotEmpty) {
      out.writeln('Alleen in base: ${onlyBase.map(_id).join(', ')}');
    }
    return out.toString();
  }

  static String _id(EvalGroup g) => '${g.caseId} [${g.model}]';
  static String _status(EvalGroup g) => '${g.status.name} ${g.passed}/${g.attempts}';

  static String _runLabel(Map<EvalGroupKey, EvalGroup> groups) {
    final records = [for (final g in groups.values) ...g.records];
    String? pick(String key) => records.map((r) => r[key]).whereType<String>().where((s) => s.isNotEmpty).firstOrNull;
    final label = pick('label');
    final sha = pick('git_sha');
    return [?label, ?sha].isEmpty ? '(onbekend)' : [?label, ?sha].join('@');
  }

  void _detail(StringBuffer out, EvalGroup g, {required EvalGroup other}) {
    final change = EvalChange(other, g);
    for (final v in g.violations) {
      out.writeln('      ${change.newViolations.contains(v) ? 'nieuw' : 'ook in base'}: $v');
    }
    for (final v in change.fixedViolations) {
      out.writeln('      opgelost: $v');
    }
    out.writeln(
      '      eerste tool ${g.firstTool ?? '-'}${g.firstToolOk ? '' : ' (niet de verwachte)'}'
      ', mediaan ${g.medianLatencyMs} ms, ${g.medianTokens} tokens'
      ' (base ${other.medianLatencyMs} ms, ${other.medianTokens} tokens)',
    );
  }
}

List<Map<String, Object?>> evalReadJsonl(String path) => [
  for (final line in File(path).readAsLinesSync())
    if (line.trim().isNotEmpty) (jsonDecode(line) as Map).cast<String, Object?>(),
];

void main(List<String> args) {
  exitCode = evalReportMain(args);
}

/// The CLI without the process exit, for the test: the exit code it would give.
int evalReportMain(List<String> args) {
  String? base, candidate, model;
  var strict = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--base':
        base = args[++i];
      case '--candidate':
        candidate = args[++i];
      case '--model':
        model = args[++i];
      case '--strict':
        strict = true;
      default:
        stderr.writeln('Onbekende optie ${args[i]}');
        return 64;
    }
  }
  if (base == null || candidate == null) {
    stderr.writeln(
      'Gebruik: dart run tool/big_p_eval_report.dart --base a.jsonl --candidate b.jsonl [--model m] [--strict]',
    );
    return 64;
  }
  final diff = EvalDiff(
    evalGroups(evalReadJsonl(base), model: model),
    evalGroups(evalReadJsonl(candidate), model: model),
  );
  stdout.write(diff.render());
  return strict && diff.regressed.isNotEmpty ? 1 : 0;
}
