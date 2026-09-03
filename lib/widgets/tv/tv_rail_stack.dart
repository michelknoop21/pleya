/// Owns UP and DOWN between the horizontal rails of one stacked TV surface
/// (LAND4 of `docs/tvos-fysieke-correctieronde.md`).
///
/// ## What it is for
///
/// Home, the Films landing, the Series landing and TV Search all draw the same
/// picture: [TvDiscoveryRail]s stacked down the page. The contract for moving
/// between them is one contract — a step to the rail above or below arrives at
/// the same horizontal position, so the stack reads as one plane rather than as
/// a pile of independent rows. This is where that contract lives, once, because
/// a rule per screen is a rule that drifts on its first bug fix.
///
/// ## Why the rails cannot be left to Flutter
///
/// Flutter's directional traversal does try to hold the horizontal band, and on
/// a static grid it succeeds. A rail is not static: it scrolls, and its scroll
/// offset *is* its focus memory. A rail last walked to its tenth tile is still
/// parked there, so the tile sitting under the band is its eleventh, not the
/// third the viewer was on above. Worse, the tiles near the third are not built
/// at all, so no amount of geometry can reach them.
///
/// That makes memory decide traversal, which is the one thing LAND4 forbids:
/// remembering where a rail was left is what returning from a detail page needs,
/// and it must survive; it just has no vote in where a keypress goes.
///
/// ## What it does not own
///
/// The edges. Above the first rail is a page header, a hero carousel or a
/// search field, and below the last rail of TV Search is a vertical list of
/// concrete results — none of them rails. [up] and [down] return null there, and
/// a null vertical handler hands the key back to Flutter's traversal, which
/// reaches those correctly. A caller with a specific target at an edge passes it
/// as [whenExhausted].
library;

import 'package:flutter/widgets.dart';

import 'tv_discovery_rail.dart';

class TvRailStack {
  /// One key per rail id, created on demand and kept for the life of the
  /// screen.
  ///
  /// Keyed on the caller's stable id — a hub id, a search section — never on a
  /// position, for the same reason the rails themselves are: a re-projection
  /// reorders rows, and a key held by index would hand a rail's focus nodes and
  /// scroll offset to a different rail.
  final _keys = <String, GlobalKey<TvDiscoveryRailState>>{};

  List<String> _order = const [];

  GlobalKey<TvDiscoveryRailState> keyFor(String railId) =>
      _keys.putIfAbsent(railId, () => GlobalKey<TvDiscoveryRailState>(debugLabel: 'tvRail_$railId'));

  /// The rails of the build now being laid out, in the order they are drawn.
  ///
  /// Called from `build`, and it has to be: [_keys] is filled by `putIfAbsent`,
  /// so iterating it gives first-ever-insertion order, and a Home-layout
  /// reorder or a re-projection changes what is on screen without changing
  /// that. Walking the keys for "the rail below this one" would have been right
  /// until the viewer reordered their Home, and silently wrong after.
  void layOut(Iterable<String> railIds) {
    _order = List.unmodifiable(railIds);
  }

  int get length => _order.length;

  TvDiscoveryRailState? stateAt(int index) {
    if (index < 0 || index >= _order.length) return null;
    return _keys[_order[index]]?.currentState;
  }

  /// The handler for UP out of the rail at [index].
  ///
  /// Null when there is no rail above and the caller named no fallback, which
  /// leaves the key to Flutter's traversal and whatever the page put there.
  ValueChanged<int>? up(int index, {VoidCallback? whenExhausted}) => _step(index, -1, whenExhausted);

  /// The handler for DOWN out of the rail at [index]. Null at the foot of the
  /// stack, see [up].
  ValueChanged<int>? down(int index, {VoidCallback? whenExhausted}) => _step(index, 1, whenExhausted);

  ValueChanged<int>? _step(int index, int delta, VoidCallback? whenExhausted) {
    final hasNeighbour = delta < 0 ? index > 0 : index < _order.length - 1;
    if (!hasNeighbour && whenExhausted == null) return null;
    return (column) {
      if (!_handOver(index, delta, column)) whenExhausted?.call();
    };
  }

  /// Walks away from [index] in [delta] steps until a rail takes the focus.
  ///
  /// Walking rather than stepping once is the "skip an empty rail" half of the
  /// contract: a rail with no groups declines, and the focus carries on to the
  /// next one. A rail that is on screen with tiles in it never declines, so it
  /// can never be skipped.
  bool _handOver(int index, int delta, int column) {
    for (var i = index + delta; i >= 0 && i < _order.length; i += delta) {
      if (stateAt(i)?.focusColumn(column) ?? false) return true;
    }
    return false;
  }

  /// The first rail that will take the focus on the tile it was left on —
  /// "DOWN out of the page header", and the landing target when a screen has
  /// nothing above its rails.
  bool focusFirstCurrent() {
    for (var i = 0; i < _order.length; i++) {
      if (stateAt(i)?.focusCurrent() ?? false) return true;
    }
    return false;
  }
}
