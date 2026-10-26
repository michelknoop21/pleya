part of 'tv_my_pleya_screen.dart';

/// Tiles per visual row in the left column. A group with more wraps.
const int _kTilesPerRow = 4;

List<List<TvMyPleyaTile>> _rowsOf(List<TvMyPleyaTile> tiles) => [
  for (var start = 0; start < tiles.length; start += _kTilesPerRow)
    tiles.sublist(start, (start + _kTilesPerRow).clamp(0, tiles.length)),
];

/// The remote's map of the two-column hub.
///
/// ```
///            top navigation
///                 ▲ UP
///   profile ── Profiel wisselen          (server status: no focus stop)
///      │ DOWN                       ▲ UP
///   rail: poster … poster  Bekijk alles ──RIGHT──▶  Big P
///      │ DOWN (nearest column)                       │
///   Mijn content tiles ───────────RIGHT (nearest row)▶ Instellingen
///   Bronnen tiles      ◀──────────LEFT (nearest row)── Logboeken …
/// ```
///
/// Left/right walk a row and leave the left column only from its last
/// element; up/down move one visual row and keep the column by geometry, the
/// way the northstar lines things up rather than by an index that only agrees
/// with it when every row is full. `Bekijk alles` is reached along the rail
/// (Right from the last poster), not by a vertical move, so Down from the
/// profile lands on the first poster as northstar 06 draws it.
class _HubFocusMap {
  _HubFocusMap({
    required this.nodes,
    required this.railKeys,
    required this.tileRows,
    required this.rightKeys,
    required this.cameFrom,
    required this.rememberedRailKey,
  });

  final FocusMemoryTracker nodes;
  final String? Function() rememberedRailKey;

  /// Where a vertical move landed, keyed by the landing, so the move straight
  /// back returns to the same element instead of the geometrically nearest
  /// one (a wide tile under two posters). Owned by the screen's state, because
  /// this map is rebuilt with every frame.
  final Map<String, String> cameFrom;

  /// Posters, then `Bekijk alles`. Empty without a kijklijst.
  final List<String> railKeys;
  final List<List<String>> tileRows;
  final List<String> rightKeys;

  List<List<String>> get _leftRows => [if (railKeys.isNotEmpty) railKeys, ...tileRows];

  String? get _rememberedPoster {
    final key = rememberedRailKey();
    return railKeys.contains(key) ? key : null;
  }

  String? get firstBelowProfile => _rememberedPoster ?? _leftRows.firstOrNull?.firstOrNull ?? rightKeys.firstOrNull;

  Rect? _rect(String key) {
    final node = nodes.nodeFor(key);
    if (node == null || node.context == null) return null;
    return node.rect;
  }

  /// A row's candidates for a vertical move: everything but `Bekijk alles`,
  /// unless it is all the row has (an empty kijklijst).
  List<String> _verticalTargets(List<String> row) {
    final targets = row.where((key) => key != _seeAllKey).toList();
    return targets.isEmpty ? row : targets;
  }

  String? _nearestByX(List<String> candidates, Rect from) =>
      _nearest(candidates, (r) => (r.center.dx - from.center.dx).abs());

  String? _nearestByY(List<String> candidates, Rect from) =>
      _nearest(candidates, (r) => (r.center.dy - from.center.dy).abs());

  String? _nearest(List<String> candidates, double Function(Rect) distance) {
    String? best;
    var bestDistance = double.infinity;
    for (final key in candidates) {
      final rect = _rect(key);
      if (rect == null) continue;
      final d = distance(rect);
      if (d < bestDistance) {
        bestDistance = d;
        best = key;
      }
    }
    return best ?? candidates.firstOrNull;
  }

  /// Where [direction] goes from [key], or null to stay put.
  String? next(String key, TraversalDirection direction) {
    final rows = _leftRows;
    final from = _rect(key);
    final rightIndex = rightKeys.indexOf(key);
    if (rightIndex >= 0) {
      return switch (direction) {
        TraversalDirection.up => rightIndex > 0 ? rightKeys[rightIndex - 1] : _switchProfileKey,
        TraversalDirection.down => rightIndex < rightKeys.length - 1 ? rightKeys[rightIndex + 1] : null,
        TraversalDirection.left => from == null ? rows.firstOrNull?.lastOrNull : _rightmostOfNearestRow(rows, from),
        TraversalDirection.right => null,
      };
    }
    for (var r = 0; r < rows.length; r++) {
      final i = rows[r].indexOf(key);
      if (i < 0) continue;
      final row = rows[r];
      switch (direction) {
        case TraversalDirection.left:
          return i > 0 ? row[i - 1] : null;
        case TraversalDirection.right:
          if (i < row.length - 1) return row[i + 1];
          return from == null ? rightKeys.firstOrNull : _nearestByY(rightKeys, from);
        case TraversalDirection.up:
          if (r == 0) return _switchProfileKey;
          return _vertical(key, _verticalTargets(rows[r - 1]), from);
        case TraversalDirection.down:
          if (r == rows.length - 1) return null;
          return _vertical(key, _verticalTargets(rows[r + 1]), from);
      }
    }
    return null;
  }

  String? _vertical(String key, List<String> candidates, Rect? from) {
    final back = candidates.contains(_rememberedPoster) ? _rememberedPoster : cameFrom[key];
    final target = back != null && candidates.contains(back)
        ? back
        : (from == null ? candidates.firstOrNull : _nearestByX(candidates, from));
    if (target != null) cameFrom[target] = key;
    return target;
  }

  /// Left out of the right column: the left row nearest in height, and in it
  /// the element nearest the column line.
  String? _rightmostOfNearestRow(List<List<String>> rows, Rect from) {
    List<String>? bestRow;
    var bestDistance = double.infinity;
    for (final row in rows) {
      final rects = [for (final key in _verticalTargets(row)) ?_rect(key)];
      if (rects.isEmpty) continue;
      final centre = rects.map((r) => r.center.dy).reduce((a, b) => a + b) / rects.length;
      final d = (centre - from.center.dy).abs();
      if (d < bestDistance) {
        bestDistance = d;
        bestRow = row;
      }
    }
    if (bestRow == null) return rows.firstOrNull?.lastOrNull;
    if (identical(bestRow, railKeys) && _rememberedPoster != null) return _rememberedPoster;
    String? best;
    var bestRight = double.negativeInfinity;
    for (final key in bestRow) {
      final rect = _rect(key);
      // Only what is on screen left of the column line: a poster scrolled out
      // of the rail is no place to land.
      if (rect == null || rect.right > from.left) continue;
      if (rect.right > bestRight) {
        bestRight = rect.right;
        best = key;
      }
    }
    return best ?? bestRow.last;
  }
}
