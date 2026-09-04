/// Pure-Dart geometry primitives for scenario assertions — no Flutter
/// import (this package runs on a plain Dart VM, e.g. a driver-less Ubuntu
/// CI job). Bounds come from `/v1/ui_tree`'s `bounds` shape
/// (`{x, y, width, height}`, logical pixels) or `/v1/viewport`.
library;

/// An axis-aligned rectangle in logical pixels — a plain value type, not
/// `dart:ui`'s `Rect` (unavailable outside a Flutter engine host).
class GeoRect {
  final double left;
  final double top;
  final double width;
  final double height;

  const GeoRect({required this.left, required this.top, required this.width, required this.height});

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  factory GeoRect.fromJson(Map<String, Object?> json) => GeoRect(
    left: (json['x'] as num).toDouble(),
    top: (json['y'] as num).toDouble(),
    width: (json['width'] as num).toDouble(),
    height: (json['height'] as num).toDouble(),
  );

  Map<String, Object?> toJson() => {'x': left, 'y': top, 'width': width, 'height': height};

  @override
  String toString() => 'GeoRect($left, $top, ${width}x$height)';
}

/// The result of a geometry check — never a bare bool, so a failing
/// assertion in an evidence bundle explains itself without a debugger.
class GeometryVerdict {
  final bool ok;
  final String message;
  final Map<String, Object?> detail;

  const GeometryVerdict({required this.ok, required this.message, this.detail = const {}});

  factory GeometryVerdict.pass(String message, [Map<String, Object?> detail = const {}]) =>
      GeometryVerdict(ok: true, message: message, detail: detail);

  factory GeometryVerdict.fail(String message, [Map<String, Object?> detail = const {}]) =>
      GeometryVerdict(ok: false, message: message, detail: detail);

  Map<String, Object?> toJson() => {'ok': ok, 'message': message, 'detail': detail};

  @override
  String toString() => '${ok ? 'PASS' : 'FAIL'}: $message';
}

GeometryVerdict _fullyContains(GeoRect outer, GeoRect inner, {required String outerName}) {
  final overflowLeft = outer.left - inner.left;
  final overflowTop = outer.top - inner.top;
  final overflowRight = inner.right - outer.right;
  final overflowBottom = inner.bottom - outer.bottom;

  final overflows = <String, double>{
    if (overflowLeft > 0) 'left': overflowLeft,
    if (overflowTop > 0) 'top': overflowTop,
    if (overflowRight > 0) 'right': overflowRight,
    if (overflowBottom > 0) 'bottom': overflowBottom,
  };

  if (overflows.isEmpty) {
    return GeometryVerdict.pass('$inner is fully inside $outerName $outer');
  }
  return GeometryVerdict.fail('$inner overflows $outerName $outer on ${overflows.keys.join(', ')}', {
    'overflow': overflows,
  });
}

/// [rect] must be fully within [viewport] (`GET /v1/viewport`).
GeometryVerdict insideViewport(GeoRect rect, GeoRect viewport) => _fullyContains(viewport, rect, outerName: 'viewport');

/// [rect] must be fully within [clipBounds] — an ancestor `ClipRect`/
/// `Container`'s bounds, distinct from the viewport (a node can be inside
/// the screen but still clipped by a narrower scroll/overflow ancestor).
GeometryVerdict notClipped(GeoRect rect, GeoRect clipBounds) =>
    _fullyContains(clipBounds, rect, outerName: 'clip bounds');

/// [a] and [b] must not share any positive-area region. Touching edges
/// (zero-area intersection) do not count as overlapping.
GeometryVerdict notOverlapping(GeoRect a, GeoRect b) {
  final overlapLeft = a.left > b.left ? a.left : b.left;
  final overlapTop = a.top > b.top ? a.top : b.top;
  final overlapRight = a.right < b.right ? a.right : b.right;
  final overlapBottom = a.bottom < b.bottom ? a.bottom : b.bottom;

  final overlapWidth = overlapRight - overlapLeft;
  final overlapHeight = overlapBottom - overlapTop;

  if (overlapWidth <= 0 || overlapHeight <= 0) {
    return GeometryVerdict.pass('$a and $b do not overlap');
  }
  return GeometryVerdict.fail('$a and $b overlap by ${overlapWidth}x$overlapHeight', {
    'overlapWidth': overlapWidth,
    'overlapHeight': overlapHeight,
  });
}

/// [a] must be below [b] — [a]'s top edge at or past [b]'s bottom edge.
GeometryVerdict below(GeoRect a, GeoRect b) {
  if (a.top >= b.bottom) return GeometryVerdict.pass('$a is below $b');
  return GeometryVerdict.fail('$a is not below $b (short by ${b.bottom - a.top})', {'shortBy': b.bottom - a.top});
}

/// [a] must be above [b] — [a]'s bottom edge at or before [b]'s top edge.
GeometryVerdict above(GeoRect a, GeoRect b) {
  if (a.bottom <= b.top) return GeometryVerdict.pass('$a is above $b');
  return GeometryVerdict.fail('$a is not above $b (short by ${a.bottom - b.top})', {'shortBy': a.bottom - b.top});
}

/// [a] must be left of [b] — [a]'s right edge at or before [b]'s left edge.
GeometryVerdict leftOf(GeoRect a, GeoRect b) {
  if (a.right <= b.left) return GeometryVerdict.pass('$a is left of $b');
  return GeometryVerdict.fail('$a is not left of $b (short by ${a.right - b.left})', {'shortBy': a.right - b.left});
}

/// [a] must be right of [b] — [a]'s left edge at or past [b]'s right edge.
GeometryVerdict rightOf(GeoRect a, GeoRect b) {
  if (a.left >= b.right) return GeometryVerdict.pass('$a is right of $b');
  return GeometryVerdict.fail('$a is not right of $b (short by ${b.right - a.left})', {'shortBy': b.right - a.left});
}

/// [rect] must be at least [minSize] on both axes — Apple HIG's 44pt
/// minimum tap target by default, overridable for a platform with a
/// different convention.
GeometryVerdict minimumTapTarget(GeoRect rect, {double minSize = 44.0}) {
  if (rect.width >= minSize && rect.height >= minSize) {
    return GeometryVerdict.pass('$rect meets the ${minSize}x$minSize minimum tap target');
  }
  return GeometryVerdict.fail('$rect is smaller than the ${minSize}x$minSize minimum tap target', {
    'width': rect.width,
    'height': rect.height,
    'minSize': minSize,
  });
}

/// [a] and [b] must share a row — their vertical centers within
/// [tolerance] logical pixels of each other.
GeometryVerdict sameRow(GeoRect a, GeoRect b, {double tolerance = 1.0}) {
  final delta = (a.centerY - b.centerY).abs();
  if (delta <= tolerance) return GeometryVerdict.pass('$a and $b share a row (Δy=$delta)');
  return GeometryVerdict.fail('$a and $b do not share a row (Δy=$delta > $tolerance)', {'delta': delta});
}

/// [a] and [b] must share a column — their horizontal centers within
/// [tolerance] logical pixels of each other.
GeometryVerdict sameColumn(GeoRect a, GeoRect b, {double tolerance = 1.0}) {
  final delta = (a.centerX - b.centerX).abs();
  if (delta <= tolerance) return GeometryVerdict.pass('$a and $b share a column (Δx=$delta)');
  return GeometryVerdict.fail('$a and $b do not share a column (Δx=$delta > $tolerance)', {'delta': delta});
}

/// The canonical content edge, as a number rather than an opinion.
///
/// [rect]'s left edge against [viewport]'s, in the viewport's own units. The
/// styling audit of 2 September 2026 measured twelve distinct content edges
/// across nine pages, all of them plausible-looking on a screenshot; this is
/// what makes a page that quietly reintroduces its own margin break a run.
///
/// [expected] is the canonical inset in the same units — `TvTopNavLayout.pageInset`
/// resolved for the device, not a percentage typed into a scenario, because a
/// percentage would have to be retyped for every canvas the app runs on.
/// [tolerance] absorbs rounding and the focus-ring gap a tile spends inside its
/// own box; it is not a licence to be approximately aligned.
///
/// Only meaningful once `/v1/ui_tree` and `/v1/viewport` agree on a coordinate
/// system. They did not until `AutomationRegistry._boundsOf` stopped composing
/// a transformed offset with an untransformed size, so this predicate is
/// deliberately younger than the fix it depends on.
GeometryVerdict leftInset(GeoRect rect, GeoRect viewport, {required double expected, double tolerance = 2.0}) {
  final actual = rect.left - viewport.left;
  final delta = (actual - expected).abs();
  final detail = <String, Object?>{
    'actual': actual,
    'expected': expected,
    'delta': delta,
    'tolerance': tolerance,
    'viewportWidth': viewport.width,
    'actualFraction': viewport.width == 0 ? null : actual / viewport.width,
  };
  return delta <= tolerance
      ? GeometryVerdict.pass('left edge at $actual, within $tolerance of $expected', detail)
      : GeometryVerdict.fail('left edge at $actual, expected $expected (off by $delta)', detail);
}
