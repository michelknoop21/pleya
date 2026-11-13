import 'dart:convert';

import '../big_p_eval_checks.dart';

// State checks of the Big P evaluation set (BP-12): grade the outcome, not
// the path. A task counts as done when the eval world holds the change, and
// a refused card counts as honoured when the world is as it was.

String _show(EvalWorldState s) => '${s.toJson()}';

bool _same(List<String> a, List<String> b) =>
    a.length == b.length && [for (final (i, x) in a.indexed) x == b[i]].every((e) => e);

bool _equal(EvalWorldState a, EvalWorldState b) =>
    _same(a.homeRows, b.homeRows) &&
    _same(a.requests, b.requests) &&
    _same(a.memory, b.memory) &&
    jsonEncode(a.admin) == jsonEncode(b.admin);

/// After the last turn the world holds exactly what [want] says. A field
/// left null in the expectation is not compared.
class EvalState extends EvalHard {
  const EvalState({this.homeRows, this.homeRowCount, this.requests, this.memory, this.admin});

  /// Fields of the administrator's state that must equal these values, such
  /// as `{'scans': ['films']}` or `{'users': {'Michel': 'all'}}`.
  final Map<String, Object?>? admin;
  final List<String>? homeRows;

  /// How many Home rows exist, when the model is free to name the row.
  final int? homeRowCount;
  final List<String>? requests;

  /// Facts that must be stored, each matched as a case-insensitive substring
  /// of one stored fact; the count must match too.
  final List<String>? memory;
  @override
  String get id => 'state';

  @override
  List<String> check(EvalOutcome o) {
    if (o.states.isEmpty) return ['$id: no world state recorded'];
    final s = o.states.last;
    final found = <String>[];
    if (homeRows != null && !_same(s.homeRows, homeRows!)) {
      found.add('$id: home rows ${s.homeRows}, wanted $homeRows');
    }
    if (homeRowCount != null && s.homeRows.length != homeRowCount) {
      found.add('$id: ${s.homeRows.length} home rows ${s.homeRows}, wanted $homeRowCount');
    }
    if (requests != null && !_same(s.requests, requests!)) {
      found.add('$id: requests ${s.requests}, wanted $requests');
    }
    if (memory != null) {
      final stored = [for (final m in s.memory) m.toLowerCase()];
      final missing = [
        for (final want in memory!)
          if (!stored.any((m) => m.contains(want.toLowerCase()))) want,
      ];
      if (missing.isNotEmpty || stored.length != memory!.length) {
        found.add('$id: memory ${s.memory}, wanted $memory');
      }
    }
    for (final MapEntry(:key, :value) in (admin ?? const <String, Object?>{}).entries) {
      if (jsonEncode(s.admin[key]) != jsonEncode(value)) {
        found.add('$id: admin $key ${jsonEncode(s.admin[key])}, wanted ${jsonEncode(value)}');
      }
    }
    return found;
  }
}

/// Nothing in the world changed over the whole case: for a refused card, a
/// question, or a task Big P cannot do.
class EvalStateUnchanged extends EvalHard {
  const EvalStateUnchanged();
  @override
  String get id => 'state-unchanged';

  @override
  List<String> check(EvalOutcome o) {
    if (o.states.isEmpty) return ['$id: no world state recorded'];
    return _equal(o.initial, o.states.last)
        ? const []
        : ['$id: world changed from ${_show(o.initial)} to ${_show(o.states.last)}'];
  }
}

/// A confirmation card was answered with yes and the action is in the
/// result: the task was carried out, not only proposed.
class EvalActionDone extends EvalHard {
  const EvalActionDone(this.kind);

  /// `AssistantActionKind` name, such as `createHomeRow`.
  final String kind;
  @override
  String get id => 'action-done-$kind';

  @override
  List<String> check(EvalOutcome o) {
    final done = [for (final t in o.turns) ...t.result.actions.map((a) => a.kind.name)];
    return done.contains(kind) ? const [] : ['$id: actions $done after ${o.confirmed} confirmed cards'];
  }
}
