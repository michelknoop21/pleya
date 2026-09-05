/// The focus-walk oracle: given one hop of the remote (a source node, a
/// landing, and everything else that was on screen at the moment of the
/// press), decide whether the landing is the one a viewer would expect — and
/// if not, name the candidates that were passed over.
///
/// Pure and Flutter-free, like [geometry.dart], so the whole rule set is
/// testable from a JSON vector file without a simulator.
///
/// **Not a replica of `DirectionalFocusTraversalPolicy`.** A replica would
/// report every deliberate deviation this app makes — DOWN from the hero
/// lands on the tile the rail remembers, RIGHT on the language page lands on
/// series row 0 — as a defect, and it would drift with the SDK the moment
/// Flutter retunes its own heuristics. What this keeps of the policy is the
/// part that decides *nothing false*: the two conditions under which a
/// candidate could have been chosen at all. A node that fails either of them
/// was never a plausible landing, so passing it over is not a finding.
library;

import 'geometry.dart';

/// One focusable in a frame, as a walk sees it.
///
/// [node] is the app's per-`FocusNode` process number (`AutomationRegistry`'s
/// `node` field). It is the only identity that survives a press: rects move
/// under the press being judged (a rail scrolls the moment focus enters it),
/// and labels are `'FocusableWrapper'` for most of the app. [id] is present
/// only for declared nodes, and is what a scenario's `allow`/`expect` names.
class WalkNode {
  final int? node;
  final String? id;
  final String? label;
  final GeoRect rect;

  const WalkNode({required this.rect, this.node, this.id, this.label});

  /// What a failure message calls this node. Never just a rect: an author
  /// reading a red walk needs to recognize the thing on screen.
  String get describe {
    final name = id ?? label ?? (node == null ? 'unnamed' : 'node $node');
    return '$name at ${rect.left.toStringAsFixed(0)},${rect.top.toStringAsFixed(0)} '
        '${rect.width.toStringAsFixed(0)}x${rect.height.toStringAsFixed(0)}';
  }

  Map<String, Object?> toJson() => {
    if (node != null) 'node': node,
    if (id != null) 'id': id,
    if (label != null) 'label': label,
    'bounds': rect.toJson(),
  };

  @override
  String toString() => describe;
}

/// The four directions a walk can run in — the remote's own axes, no
/// diagonals.
enum WalkDirection {
  up,
  down,
  left,
  right;

  static WalkDirection? parse(String value) {
    for (final d in WalkDirection.values) {
      if (d.name == value) return d;
    }
    return null;
  }

  bool get isHorizontal => this == left || this == right;

  /// +1 when the direction runs with the axis (right, down), -1 against it.
  double get sign => (this == right || this == down) ? 1 : -1;
}

enum HopVerdictKind {
  /// The landing is plausible and nothing was passed over.
  ok,

  /// Something between the source and the landing could have been chosen
  /// and was not.
  skipped,

  /// The landing is not in the direction pressed — a step backwards, or a
  /// wrap around to the other edge.
  notForward,

  /// The landing does not exist in the frame the judgement is made in, so
  /// there is nothing to measure the hop against. Usually a node built by
  /// the scroll the press itself caused.
  inconclusive,
}

/// One hop's verdict. Carries the passed-over candidates rather than a
/// boolean, because that list is the finding.
class HopVerdict {
  final HopVerdictKind kind;
  final List<WalkNode> passedOver;
  final String message;

  const HopVerdict({required this.kind, required this.message, this.passedOver = const []});

  bool get ok => kind == HopVerdictKind.ok;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'message': message,
    if (passedOver.isNotEmpty) 'passedOver': [for (final n in passedOver) n.toJson()],
  };

  @override
  String toString() => '${kind.name}: $message';
}

/// How far a candidate may stick out past the landing's near edge and still
/// count as sitting *between* source and landing.
///
/// Without it, a candidate whose edge lines up with the landing's to within a
/// rounding error flips between "between" and "beside" from frame to frame. 8
/// logical pixels is under half the smallest gap this app puts between two
/// focusables and well over the rounding it produces.
const double kOverhangTolerance = 8.0;

/// How much of the perpendicular extent a candidate must share with the
/// *source* to be in its band.
///
/// The band is taken from the source, not the landing: Flutter's directional
/// policy scores candidates against the box focus is leaving, and a rule
/// measured off the landing would call every node in the destination column a
/// plausible alternative to the destination itself.
const double kBandOverlapFraction = 0.5;

/// Whether [to] is in the direction pressed at all.
///
/// Centres, not edges: two nav items can overlap by a pixel of focus ring and
/// still be an honest step to the right, while a wrap-around lands a whole
/// screen back and is never within a pixel.
bool isForward(GeoRect from, GeoRect to, WalkDirection direction) {
  final s = direction.sign;
  final fromC = direction.isHorizontal ? from.centerX : from.centerY;
  final toC = direction.isHorizontal ? to.centerX : to.centerY;
  return s * (toC - fromC) > 1.0;
}

/// The candidates a hop from [from] to [to] passed over, in the frame the
/// press was issued in.
///
/// A candidate counts when all of it holds:
///
/// 1. its centre is past the source's far edge (it is genuinely ahead);
/// 2. its far edge is before the landing's near edge, give or take
///    [kOverhangTolerance] (it is genuinely *between* the two);
/// 3. it shares at least [kBandOverlapFraction] of the perpendicular extent
///    with the source (the remote could have reached it in a straight line);
/// 4. its centre is inside [viewport] (offscreen nodes are not choices a
///    viewer can make);
/// 5. it is neither endpoint, has area, and contains neither endpoint —
///    which is how an ancestor focus scope, whose rect swallows the whole
///    row, is kept out.
List<WalkNode> passedOverCandidates({
  required WalkNode from,
  required WalkNode to,
  required WalkDirection direction,
  required List<WalkNode> candidates,
  required GeoRect viewport,
  Set<String> allow = const {},
}) {
  final s = direction.sign;
  final horizontal = direction.isHorizontal;

  double primaryCentre(GeoRect r) => horizontal ? r.centerX : r.centerY;
  double farEdge(GeoRect r) => horizontal ? (s > 0 ? r.right : r.left) : (s > 0 ? r.bottom : r.top);
  double nearEdge(GeoRect r) => horizontal ? (s > 0 ? r.left : r.right) : (s > 0 ? r.top : r.bottom);
  double perpLow(GeoRect r) => horizontal ? r.top : r.left;
  double perpHigh(GeoRect r) => horizontal ? r.bottom : r.right;

  final sourceFar = farEdge(from.rect);
  final targetNear = nearEdge(to.rect);

  final result = <WalkNode>[];
  for (final c in candidates) {
    if (_isEndpoint(c, from) || _isEndpoint(c, to)) continue;
    if (c.rect.width <= 0 || c.rect.height <= 0) continue;
    if (c.id != null && allow.contains(c.id)) continue;
    if (_contains(c.rect, from.rect) || _contains(c.rect, to.rect)) continue;

    if (s * (primaryCentre(c.rect) - sourceFar) <= 0) continue;
    if (s * (farEdge(c.rect) - (targetNear + s * kOverhangTolerance)) >= 0) continue;

    final overlap = _min(perpHigh(c.rect), perpHigh(from.rect)) - _max(perpLow(c.rect), perpLow(from.rect));
    if (overlap <= 0) continue;
    final smallest = _min(perpHigh(c.rect) - perpLow(c.rect), perpHigh(from.rect) - perpLow(from.rect));
    if (smallest <= 0 || overlap / smallest < kBandOverlapFraction) continue;

    if (c.rect.centerX < viewport.left ||
        c.rect.centerX > viewport.right ||
        c.rect.centerY < viewport.top ||
        c.rect.centerY > viewport.bottom) {
      continue;
    }

    result.add(c);
  }
  return result;
}

/// Judges one hop. [to] is null when the landing could not be found in the
/// frame the judgement is made in — see [HopVerdictKind.inconclusive].
HopVerdict judgeHop({
  required WalkNode from,
  required WalkNode? to,
  required WalkDirection direction,
  required List<WalkNode> candidates,
  required GeoRect viewport,
  Set<String> allow = const {},
  bool expected = false,
}) {
  if (to == null) {
    return HopVerdict(
      kind: HopVerdictKind.inconclusive,
      message:
          'the landing after ${direction.name.toUpperCase()} from ${from.describe} is not in the frame the press was '
          'issued in, so there is nothing to judge it against (usually a node the scroll built)',
    );
  }
  if (!expected && !isForward(from.rect, to.rect, direction)) {
    return HopVerdict(
      kind: HopVerdictKind.notForward,
      message:
          '${direction.name.toUpperCase()} from ${from.describe} landed on ${to.describe}, which is not in the '
          'direction pressed (a step back, or a wrap to the other edge)',
    );
  }

  final passed = passedOverCandidates(
    from: from,
    to: to,
    direction: direction,
    candidates: candidates,
    viewport: viewport,
    allow: allow,
  );
  if (passed.isEmpty) {
    return HopVerdict(
      kind: HopVerdictKind.ok,
      message: '${direction.name.toUpperCase()} from ${from.describe} to ${to.describe}',
    );
  }
  return HopVerdict(
    kind: HopVerdictKind.skipped,
    passedOver: passed,
    message:
        '${direction.name.toUpperCase()} from ${from.describe} landed on ${to.describe}, passing over '
        '${passed.length} focusable${passed.length == 1 ? '' : 's'}: ${passed.map((n) => n.describe).join('; ')}',
  );
}

/// Every focusable in a `/v1/ui_tree` payload a walk may judge against.
///
/// Declared and discovered are the same `FocusNode`s seen twice — declared
/// adds an id, discovered adds everything with no id at all — so they are
/// merged on the node number and the declared copy wins. Nodes that cannot
/// take focus are dropped here rather than in [passedOverCandidates]: they
/// were never choices, so calling them "passed over" would be the oracle's
/// own false positive.
List<WalkNode> walkCandidatesFrom(Map<String, Object?> uiTree) {
  final byNode = <int, WalkNode>{};
  final anonymous = <WalkNode>[];

  void add(Map<String, Object?> raw, {required bool declared}) {
    if (raw['canRequestFocus'] == false) return;
    final bounds = raw['bounds'];
    if (bounds is! Map) return;
    final rect = GeoRect.fromJson(bounds.cast<String, Object?>());
    final node = raw['node'] is int ? raw['node'] as int : null;
    final walkNode = WalkNode(
      rect: rect,
      node: node,
      id: declared ? raw['id'] as String? : null,
      label: raw['label'] as String?,
    );
    if (node == null) {
      anonymous.add(walkNode);
      return;
    }
    final existing = byNode[node];
    if (existing == null || (existing.id == null && walkNode.id != null)) byNode[node] = walkNode;
  }

  for (final raw in _list(uiTree['declared'])) {
    add(raw, declared: true);
  }
  for (final raw in _list(uiTree['discovered'])) {
    add(raw, declared: false);
  }
  return [...byNode.values, ...anonymous];
}

/// Which node in [candidates] the `/v1/focus` payload [focus] refers to.
///
/// By node number when both sides have one — the only match that survives a
/// press. The rect fallback is for a frame captured before `node` shipped, or
/// a node with no `FocusNode` of its own; it is exact, not nearest, because a
/// nearest-match would happily pair a scrolled rail with the wrong tile,
/// which is the failure this whole identity exists to prevent.
WalkNode? locateFocus(Map<String, Object?>? focus, List<WalkNode> candidates) {
  if (focus == null) return null;
  final node = focus['node'];
  if (node is int) {
    for (final c in candidates) {
      if (c.node == node) return c;
    }
  }
  final bounds = focus['bounds'];
  if (bounds is! Map) return null;
  final rect = GeoRect.fromJson(bounds.cast<String, Object?>());
  for (final c in candidates) {
    if (_sameRect(c.rect, rect)) return c;
  }
  // Focused, measurable, but not in the tree we were handed: still a usable
  // source for the next hop, just without an id.
  return WalkNode(rect: rect, node: node is int ? node : null, label: focus['label'] as String?);
}

bool _isEndpoint(WalkNode candidate, WalkNode endpoint) {
  if (candidate.node != null && endpoint.node != null) return candidate.node == endpoint.node;
  if (candidate.id != null && candidate.id == endpoint.id) return true;
  return _sameRect(candidate.rect, endpoint.rect);
}

bool _sameRect(GeoRect a, GeoRect b) =>
    (a.left - b.left).abs() < 0.5 &&
    (a.top - b.top).abs() < 0.5 &&
    (a.width - b.width).abs() < 0.5 &&
    (a.height - b.height).abs() < 0.5;

/// [outer] fully contains [inner], and is strictly bigger — an ancestor
/// focus scope wrapping a row, not the row itself.
bool _contains(GeoRect outer, GeoRect inner) {
  if (_sameRect(outer, inner)) return false;
  return outer.left <= inner.left + 0.5 &&
      outer.top <= inner.top + 0.5 &&
      outer.right >= inner.right - 0.5 &&
      outer.bottom >= inner.bottom - 0.5;
}

List<Map<String, Object?>> _list(Object? raw) => raw is List
    ? [
        for (final e in raw)
          if (e is Map) e.cast<String, Object?>(),
      ]
    : const [];

double _min(double a, double b) => a < b ? a : b;
double _max(double a, double b) => a > b ? a : b;
