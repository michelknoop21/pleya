/// UP/DOWN between stacked TV content rows (CAROUSEL-LEFT1, Roadmap A-06).
/// Each destination restores its own selection at the shared left anchor.
/// Empty rows are skipped; page headers and other controls keep their own routes.
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
    return (_) {
      if (!_handOver(index, delta)) whenExhausted?.call();
    };
  }

  /// Walks away from [index] in [delta] steps until a rail takes the focus.
  ///
  /// Walking rather than stepping once is the "skip an empty rail" half of the
  /// contract: a rail with no groups declines, and the focus carries on to the
  /// next one. A rail that is on screen with tiles in it never declines, so it
  /// can never be skipped.
  bool _handOver(int index, int delta) {
    for (var i = index + delta; i >= 0 && i < _order.length; i += delta) {
      if (stateAt(i)?.focusCurrent() ?? false) return true;
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
