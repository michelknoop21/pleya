/// Turns an `assert:` step's `state:`/`focused:` fields into
/// [NodeAssertionResult]s — presence and the geometry predicates live in
/// `geometry_assertions.dart`; these two read the rest of what
/// `GET /v1/ui_tree` already reports for a declared node, no new production
/// code required for a node that already publishes one:
///
/// ```yaml
/// - assert: {id: nav.discover, state: {collapsed: true}}
/// - assert: {id: library.filter.sort, focused: true}
/// ```
///
/// `state` checks each key against the node's own `AutomationNode.state`
/// callback — `side_navigation_rail.dart`'s nav items already publish
/// `{'selected': ..., 'collapsed': ...}`, `library_browse_tab.dart`'s grid
/// publishes `{'child_count': ...}`, and so on. A node with no `state`
/// callback is reported distinctly from a mismatched value — the same
/// "not evaluable" vs. "measured and wrong" split `geometry_assertions.dart`
/// uses for a missing rect. `focused` reads the `focused` field every
/// declared node already reports (`AutomationRegistry.snapshot`), so it
/// needs no widget-level opt-in at all.
///
/// Generic by construction: neither predicate is specific to any one
/// screen or widget, so a scenario for a future Unified TV surface gets
/// both for free the moment its widgets publish a `state` callback.
library;

class NodeAssertionException implements Exception {
  final String message;

  const NodeAssertionException(this.message);

  @override
  String toString() => 'NodeAssertionException: $message';
}

/// One evaluated `state`/`focused` predicate, ready to record in a step's
/// manifest entry alongside any [GeometryAssertionResult]s the same step
/// carries.
class NodeAssertionResult {
  final String predicate;
  final String subjectId;
  final String? key;
  final Object? expected;
  final Object? actual;
  final bool ok;
  final String message;

  const NodeAssertionResult({
    required this.predicate,
    required this.subjectId,
    this.key,
    required this.expected,
    required this.actual,
    required this.ok,
    required this.message,
  });

  Map<String, Object?> toJson() => {
    'predicate': predicate,
    'subject': subjectId,
    if (key != null) 'key': key,
    'expected': expected,
    'actual': actual,
    'ok': ok,
    'message': message,
  };
}

/// Every non-geometry key an `assert:` step's `state`/`focused` handling
/// recognizes.
const Set<String> nodeFieldPredicates = {'state', 'focused'};

/// Evaluates an `assert:` step's `state`/`focused` fields against an
/// already-fetched [uiTree]. Pure — no I/O — same shape as
/// `evaluateGeometryAssertions`.
List<NodeAssertionResult> evaluateNodeAssertions(Map<String, Object?> args, {required Map<String, Object?> uiTree}) {
  final subjectId = args['id'] as String;
  final results = <NodeAssertionResult>[];

  if (args['state'] case final Map<String, Object?> expectedState) {
    final node = _nodeFor(subjectId, uiTree);
    final actualState = node['state'];
    if (actualState is! Map) {
      throw NodeAssertionException(
        "'$subjectId' has no state to assert against — it does not publish an AutomationNode.state callback",
      );
    }
    for (final entry in expectedState.entries) {
      final actual = (actualState as Map<Object?, Object?>)[entry.key];
      final ok = actual == entry.value;
      results.add(
        NodeAssertionResult(
          predicate: 'state',
          subjectId: subjectId,
          key: entry.key,
          expected: entry.value,
          actual: actual,
          ok: ok,
          message: ok
              ? "'$subjectId'.state.${entry.key} is $actual"
              : "'$subjectId'.state.${entry.key} is $actual, expected ${entry.value}",
        ),
      );
    }
  }

  if (args['focused'] case final bool expectedFocused) {
    final node = _nodeFor(subjectId, uiTree);
    final actual = node['focused'] == true;
    final ok = actual == expectedFocused;
    results.add(
      NodeAssertionResult(
        predicate: 'focused',
        subjectId: subjectId,
        expected: expectedFocused,
        actual: actual,
        ok: ok,
        message: ok ? "'$subjectId'.focused is $actual" : "'$subjectId'.focused is $actual, expected $expectedFocused",
      ),
    );
  }

  return results;
}

/// Looks a node up by id, declared nodes first and discovered focusables
/// second — the same lookup order `geometry_assertions.dart`'s `_rectFor`
/// uses.
Map<String, Object?> _nodeFor(String id, Map<String, Object?> uiTree) {
  for (final key in ['declared', 'discovered']) {
    final nodes = uiTree[key];
    if (nodes is! List) continue;
    for (final raw in nodes) {
      if (raw is! Map) continue;
      if (raw['id'] != id) continue;
      return raw.cast<String, Object?>();
    }
  }
  throw NodeAssertionException("'$id' is not in the UI tree, so its state cannot be asserted");
}
