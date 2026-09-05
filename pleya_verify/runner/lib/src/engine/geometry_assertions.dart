/// Turns an `assert:` step's geometry fields into [GeometryVerdict]s.
///
/// `lib/src/geometry.dart` has held the predicates since Fase 7, but nothing
/// called them: `assert` only ever answered "is this id present". A scenario
/// could not state the thing the plan's [C-]cases are actually about — that
/// the hero sits inside the viewport, that a filter chip is big enough to
/// hit, that two layers do not overlap.
///
/// Grammar, on top of the existing `{id: …}` presence check:
///
/// ```yaml
/// - assert: {id: discover.hero, insideViewport: true}
/// - assert: {id: discover.hero.play, minimumTapTarget: 44}
/// - assert: {id: discover.hero, notOverlapping: sidebar.rail}
/// - assert: {id: library.grid, below: library.filters}
/// ```
///
/// Unary predicates take `true` (or a number, where one is meaningful);
/// binary ones take the automation id of the other node. Every verdict —
/// pass or fail — carries its measured numbers into the evidence bundle, so
/// a failure explains itself without a debugger.
library;

import '../geometry.dart';
import 'ambiguous_ids.dart';

/// Unary predicates: subject rect only.
const Set<String> unaryGeometryPredicates = {'insideViewport', 'minimumTapTarget'};

/// Binary predicates: subject rect against a second node named by id.
const Set<String> binaryGeometryPredicates = {
  'notOverlapping',
  'notClipped',
  'below',
  'above',
  'leftOf',
  'rightOf',
  'sameRow',
  'sameColumn',
};

/// Every geometry key an `assert:` step may carry.
Set<String> get geometryPredicates => {...unaryGeometryPredicates, ...binaryGeometryPredicates};

/// Raised when a geometry assertion cannot be *evaluated* — a missing rect,
/// an unusable viewport. Distinct from a failing verdict: "the hero is
/// outside the viewport" is a result, "the hero has no bounds" is a broken
/// assertion, and a report must not blur the two.
class GeometryAssertionException implements Exception {
  final String message;

  const GeometryAssertionException(this.message);

  @override
  String toString() => 'GeometryAssertionException: $message';
}

/// One evaluated predicate, ready to record in a step's manifest entry.
class GeometryAssertionResult {
  final String predicate;
  final String subjectId;
  final String? otherId;
  final GeometryVerdict verdict;

  const GeometryAssertionResult({
    required this.predicate,
    required this.subjectId,
    this.otherId,
    required this.verdict,
  });

  Map<String, Object?> toJson() => {
    'predicate': predicate,
    'subject': subjectId,
    if (otherId != null) 'other': otherId,
    ...verdict.toJson(),
  };
}

/// Evaluates every geometry field in [args] against an already-fetched
/// [uiTree] and [viewport]. Pure — it does no I/O, so it is testable without
/// a driver, a simulator or a build.
List<GeometryAssertionResult> evaluateGeometryAssertions(
  Map<String, Object?> args, {
  required Map<String, Object?> uiTree,
  required Map<String, Object?> viewport,
}) {
  final subjectId = args['id'] as String;
  final results = <GeometryAssertionResult>[];

  for (final entry in args.entries) {
    if (!geometryPredicates.contains(entry.key)) continue;
    final subject = _rectFor(subjectId, uiTree);

    if (unaryGeometryPredicates.contains(entry.key)) {
      results.add(
        GeometryAssertionResult(
          predicate: entry.key,
          subjectId: subjectId,
          verdict: _evaluateUnary(entry.key, entry.value, subject, viewport),
        ),
      );
      continue;
    }

    final otherId = entry.value;
    if (otherId is! String) {
      throw GeometryAssertionException("'${entry.key}' needs the automation id of the other node, got: $otherId");
    }
    results.add(
      GeometryAssertionResult(
        predicate: entry.key,
        subjectId: subjectId,
        otherId: otherId,
        verdict: _evaluateBinary(entry.key, subject, _rectFor(otherId, uiTree)),
      ),
    );
  }

  return results;
}

GeometryVerdict _evaluateUnary(String predicate, Object? value, GeoRect subject, Map<String, Object?> viewport) {
  switch (predicate) {
    case 'insideViewport':
      return insideViewport(subject, _viewportRect(viewport));
    case 'minimumTapTarget':
      // A number sets the threshold; `true` takes geometry.dart's default,
      // which is Apple HIG's 44pt.
      return value is num ? minimumTapTarget(subject, minSize: value.toDouble()) : minimumTapTarget(subject);
    default:
      throw GeometryAssertionException('unary geometry predicate not implemented: $predicate');
  }
}

GeometryVerdict _evaluateBinary(String predicate, GeoRect subject, GeoRect other) {
  switch (predicate) {
    case 'notOverlapping':
      return notOverlapping(subject, other);
    case 'notClipped':
      return notClipped(subject, other);
    case 'below':
      return below(subject, other);
    case 'above':
      return above(subject, other);
    case 'leftOf':
      return leftOf(subject, other);
    case 'rightOf':
      return rightOf(subject, other);
    case 'sameRow':
      return sameRow(subject, other);
    case 'sameColumn':
      return sameColumn(subject, other);
    default:
      throw GeometryAssertionException('binary geometry predicate not implemented: $predicate');
  }
}

/// The viewport as a rect. `/v1/viewport` reports a size, not a box, and its
/// origin is the top-left of the window — so `(0, 0, width, height)`.
///
/// `available: false` is the app saying it has no `WidgetsBinding` yet. That
/// is not a geometry failure, it is an un-evaluatable assertion, and it must
/// read as one.
GeoRect _viewportRect(Map<String, Object?> viewport) {
  if (viewport['available'] != true) {
    throw const GeometryAssertionException(
      '/v1/viewport reports available: false — the app has no live view to measure against yet '
      '(wait_until a screen is ready before asserting geometry)',
    );
  }
  final width = viewport['width'];
  final height = viewport['height'];
  if (width is! num || height is! num) {
    throw GeometryAssertionException('/v1/viewport has no usable width/height: $viewport');
  }
  return GeoRect(left: 0, top: 0, width: width.toDouble(), height: height.toDouble());
}

/// Looks a node's `bounds` up in a `/v1/ui_tree` payload, declared nodes
/// first and discovered focusables second.
///
/// A node with no `bounds` is reported distinctly from a node that is not
/// there at all: the first means it is registered but unmounted (its
/// `contextGetter` returned null), the second that the id never appeared —
/// two different bugs that a single "not found" would merge.
GeoRect _rectFor(String id, Map<String, Object?> uiTree) {
  // Before the lookup, not after: the walk below returns the first match, so
  // on a duplicated id it would answer with a rect that is only one of the
  // candidates. See [ambiguousIdMessage].
  if (ambiguousIdMessage(id, uiTree) case final message?) throw GeometryAssertionException(message);
  for (final key in ['declared', 'discovered']) {
    final nodes = uiTree[key];
    if (nodes is! List) continue;
    for (final raw in nodes) {
      if (raw is! Map) continue;
      if (raw['id'] != id) continue;
      final bounds = raw['bounds'];
      if (bounds is Map<String, Object?>) return GeoRect.fromJson(bounds);
      throw GeometryAssertionException(
        "'$id' is registered but has no bounds — it is not currently mounted, so there is nothing to measure",
      );
    }
  }
  throw GeometryAssertionException("'$id' is not in the UI tree, so its geometry cannot be asserted");
}
