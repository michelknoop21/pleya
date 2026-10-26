part of 'tv_my_pleya_screen.dart';

/// The remote's map of the page (LEESMIJ-v4, "Focusafspraken").
///
/// ```
///                    top navigation
///                 ▲ UP                ▲ UP
///   Big P ──RIGHT──▶ poster … poster ──RIGHT──▶ Bekijk alles
///         ◀──LEFT───                  (UP from a poster)
///      │ DOWN (first tile)       │ DOWN (nearest tile)
///   Snel naar: tile ── tile ── tile …   (UP: nearest of Big P and posters)
/// ```
///
/// Big P is one focus object; `Vraag Big P` inside the card is only the
/// visible call to action. Left/right in the dock walks the tiles that exist,
/// so a hidden option leaves no focus stop behind, and nothing wraps. UP
/// out of the top row hands the remote to the top navigation.
class _PageFocusMap {
  _PageFocusMap({
    required this.nodes,
    required this.bigPKey,
    required this.posterKeys,
    required this.seeAllKey,
    required this.dockKeys,
    required this.cameFrom,
    required this.onExitUp,
  });

  final FocusMemoryTracker nodes;

  /// Null when Big P is not offered to this profile.
  final String? bigPKey;
  final List<String> posterKeys;

  /// Null without a kijklijst.
  final String? seeAllKey;
  final List<String> dockKeys;

  /// Where a vertical move came from, keyed by where it landed, so the move
  /// straight back returns to the same element instead of the geometrically
  /// nearest one. Owned by the screen's state, because this map is rebuilt
  /// with every frame.
  final Map<String, String> cameFrom;
  final VoidCallback onExitUp;

  /// The first content action: Big P, else the first poster, else `Bekijk
  /// alles`, else the first tile.
  String? get firstKey => bigPKey ?? posterKeys.firstOrNull ?? seeAllKey ?? dockKeys.firstOrNull;

  /// What UP from the dock and DOWN to it choose between.
  List<String> get _topRow => [?bigPKey, ...posterKeys];

  Rect? _rect(String key) {
    final node = nodes.nodeFor(key);
    if (node == null || node.context == null) return null;
    return node.rect;
  }

  String? _nearestByX(List<String> candidates, Rect? from) {
    if (from == null) return candidates.firstOrNull;
    String? best;
    var bestDistance = double.infinity;
    for (final key in candidates) {
      final rect = _rect(key);
      if (rect == null) continue;
      final d = (rect.center.dx - from.center.dx).abs();
      if (d < bestDistance) {
        bestDistance = d;
        best = key;
      }
    }
    return best ?? candidates.firstOrNull;
  }

  /// A vertical move to [candidates]: back to where the remote came from when
  /// that is one of them, otherwise the nearest by x.
  String? _vertical(String key, List<String> candidates) {
    final back = cameFrom[key];
    final target = back != null && candidates.contains(back) ? back : _nearestByX(candidates, _rect(key));
    if (target != null) cameFrom[target] = key;
    return target;
  }

  /// Moves the focus from [key] in [direction]. UP out of the top row leaves
  /// for the top navigation; everything else that has nowhere to go stays.
  void move(String key, TraversalDirection direction) {
    if (_next(key, direction) case final String target) {
      final node = nodes.get(target);
      if (node.canRequestFocus) node.requestFocus();
    }
  }

  String? _next(String key, TraversalDirection direction) {
    if (key == bigPKey) {
      return switch (direction) {
        TraversalDirection.right => posterKeys.firstOrNull ?? seeAllKey,
        TraversalDirection.left => null,
        TraversalDirection.up => _exitUp(),
        // Big P is the page's leftmost card, so DOWN starts the dock at its
        // first tile, or returns to the tile the remote came up from.
        TraversalDirection.down => _down(key),
      };
    }
    final poster = posterKeys.indexOf(key);
    if (poster >= 0) {
      return switch (direction) {
        TraversalDirection.left => poster > 0 ? posterKeys[poster - 1] : bigPKey,
        TraversalDirection.right => poster < posterKeys.length - 1 ? posterKeys[poster + 1] : seeAllKey,
        TraversalDirection.up => seeAllKey == null ? _exitUp() : _vertical(key, [seeAllKey!]),
        TraversalDirection.down => _vertical(key, dockKeys),
      };
    }
    if (key == seeAllKey) {
      return switch (direction) {
        TraversalDirection.up => _exitUp(),
        TraversalDirection.right => null,
        // Back to the poster it was left from, else the first one (the rail
        // scrolls it into view on focus).
        TraversalDirection.left || TraversalDirection.down =>
          posterKeys.isEmpty
              ? (direction == TraversalDirection.left ? bigPKey : _vertical(key, dockKeys))
              : _returnTo(key, posterKeys),
      };
    }
    final tile = dockKeys.indexOf(key);
    if (tile >= 0) {
      return switch (direction) {
        TraversalDirection.left => tile > 0 ? dockKeys[tile - 1] : null,
        TraversalDirection.right => tile < dockKeys.length - 1 ? dockKeys[tile + 1] : null,
        TraversalDirection.up => _topRow.isEmpty ? (seeAllKey ?? _exitUp()) : _vertical(key, _visible(_topRow)),
        TraversalDirection.down => null,
      };
    }
    return null;
  }

  /// UP from the top row: the bar takes it, so there is no target here.
  String? _exitUp() {
    onExitUp();
    return null;
  }

  /// The candidates that are on screen; a poster scrolled out of the rail is
  /// no place to land. Falls back to all of them before the first layout.
  List<String> _visible(List<String> keys) {
    final shown = keys.where((key) => _rect(key) != null).toList();
    return shown.isEmpty ? keys : shown;
  }

  String? _down(String key) {
    final target = _returnTo(key, dockKeys);
    if (target != null) cameFrom[target] = key;
    return target;
  }

  String? _returnTo(String key, List<String> candidates) {
    final back = cameFrom[key];
    return back != null && candidates.contains(back) ? back : candidates.firstOrNull;
  }
}
