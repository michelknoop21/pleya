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
    required this.rail,
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

  /// The kijklijst rail, which can scroll a poster into existence before the
  /// focus goes there. Owned by the screen's state, attached by the panel.
  final _RailReveal rail;

  /// The first content action: Big P, else the first poster, else `Bekijk
  /// alles`, else the first tile.
  String? get firstKey => bigPKey ?? posterKeys.firstOrNull ?? seeAllKey ?? dockKeys.firstOrNull;

  /// What UP from the dock and DOWN to it choose between.
  List<String> get _topRow => [?bigPKey, ...posterKeys];

  /// Null for a node that is not on the page now. A poster that scrolled out
  /// of the rail's cache keeps a context whose element is gone, and asking
  /// that for its rect throws (review 557-C1), so a mounted element is the
  /// test, not a context.
  Rect? _rect(String key) {
    final context = nodes.nodeFor(key)?.context;
    if (context == null || !context.mounted) return null;
    return nodes.nodeFor(key)!.rect;
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
  ///
  /// A poster the rail has not built (scrolled far away) cannot take the
  /// focus, so the rail scrolls it in first and the focus follows a frame
  /// later.
  void move(String key, TraversalDirection direction) {
    final target = _next(key, direction);
    if (target == null) return;
    final node = nodes.get(target);
    void focus() {
      if (node.canRequestFocus) node.requestFocus();
    }

    final poster = posterKeys.indexOf(target);
    if (poster >= 0 && _rect(target) == null && rail.show(poster, then: focus)) return;
    focus();
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
        TraversalDirection.right => poster < posterKeys.length - 1 ? posterKeys[poster + 1] : _toSeeAll(key),
        TraversalDirection.up => seeAllKey == null ? _exitUp() : _vertical(key, [seeAllKey!]),
        TraversalDirection.down => _vertical(key, dockKeys),
      };
    }
    if (key == seeAllKey) {
      return switch (direction) {
        TraversalDirection.up => _exitUp(),
        TraversalDirection.right => null,
        // Back to the poster it was left from, else the last one, which is
        // the one beside and below the link ([move] scrolls it in).
        TraversalDirection.left || TraversalDirection.down =>
          posterKeys.isEmpty
              ? (direction == TraversalDirection.left ? bigPKey : _vertical(key, dockKeys))
              : _returnTo(key, posterKeys, fallback: posterKeys.last),
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

  /// RIGHT off the last poster: `Bekijk alles`, which remembers the poster so
  /// LEFT and DOWN return to it rather than to the start of the rail.
  String? _toSeeAll(String poster) {
    final target = seeAllKey;
    if (target != null) cameFrom[target] = poster;
    return target;
  }

  /// The candidates that are on screen; a poster scrolled out of the rail, or
  /// built just outside it, is no place to land. Falls back to all of them
  /// before the first layout.
  List<String> _visible(List<String> keys) {
    final viewport = rail.viewport;
    final shown = keys.where((key) {
      final rect = _rect(key);
      if (rect == null) return false;
      return viewport == null || !posterKeys.contains(key) || rect.overlaps(viewport);
    }).toList();
    return shown.isEmpty ? keys : shown;
  }

  String? _down(String key) {
    final target = _returnTo(key, dockKeys);
    if (target != null) cameFrom[target] = key;
    return target;
  }

  String? _returnTo(String key, List<String> candidates, {String? fallback}) {
    final back = cameFrom[key];
    return back != null && candidates.contains(back) ? back : fallback ?? candidates.firstOrNull;
  }
}

/// The kijklijst rail's half of [_PageFocusMap]: it knows where the rail is
/// on screen and how to scroll a poster that is not built into view.
/// Created once by the screen's state; the panel attaches while it is
/// mounted.
class _RailReveal {
  bool Function(int index, VoidCallback then)? _show;
  Rect? Function()? _viewport;

  void attach({required bool Function(int index, VoidCallback then) show, required Rect? Function() viewport}) {
    _show = show;
    _viewport = viewport;
  }

  void detach(bool Function(int index, VoidCallback then) show) {
    if (_show != show) return;
    _show = null;
    _viewport = null;
  }

  /// The rail's box on screen, or null without a laid-out rail.
  Rect? get viewport => _viewport?.call();

  /// Scrolls poster [index] into the rail and calls [then] once it is built.
  /// False when there is no rail to scroll.
  bool show(int index, {required VoidCallback then}) => _show?.call(index, then) ?? false;
}
