/// The shared frame every Mijn Pleya section is built inside.
///
/// **Why this exists.** Ten sections open above a destination's root, and the
/// only thing that put the remote inside one of them was
/// `route.screenKey?.currentState is FocusableTab`. That worked for two of
/// them. For the other eight the route's `screenKey` was a `GlobalKey` handed
/// to nothing, so `currentState` was permanently null and the pattern match
/// simply did not fire; and even with the key attached, six of those screens
/// have no `FocusableTab` to reach — three are `StatelessWidget`s, so there is
/// no `State` for a key to resolve to at all.
///
/// The failure that produced on a real Apple TV, and reproduced in the
/// simulator with HID input, is not subtle: the section opens, no control has
/// the focus, the destination root underneath is `ExcludeFocus`ed so there is
/// nothing else in the scope either, and every subsequent press lands nowhere.
///
/// So focus entry stops depending on the screen's cooperation. This surface
/// asks the screen first, because a screen that knows where its focus belongs
/// knows better than any generic rule; when there is nothing to ask, or asking
/// changed nothing, it focuses the first focusable descendant of the route's
/// own subtree. That works for a `StatelessWidget` exactly as well as for a
/// screen with a full focus contract, which is the point.
///
/// **It reports back.** [focusEntry] returns whether the remote actually
/// ended up inside this route, so the caller can leave a pending content-focus
/// intent armed instead of consuming it on a call that did nothing.
/// `FocusableTab.focusActiveTabIfReady()` returns `void`, which is precisely
/// why the original breakage was invisible.
///
/// **It does not steal focus.** The retry only runs while an entry is pending
/// and stops the moment the subtree holds the focus, the route is gone, or the
/// budget expires — the P2 rule that late content may consume an explicit
/// intent and may never help itself to the remote.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../mixins/refreshable.dart';
import 'tv_navigation_coordinator.dart';
import 'tv_nested_back_owner.dart';

class TvNestedSurface extends StatefulWidget {
  const TvNestedSurface({super.key, required this.route, required this.child});

  final TvNestedRoute route;
  final Widget child;

  @override
  State<TvNestedSurface> createState() => TvNestedSurfaceState();
}

class TvNestedSurfaceState extends State<TvNestedSurface> {
  /// A non-focusable anchor rather than a `FocusScope`: this widget has to be
  /// able to enumerate the route's descendants without changing how traversal
  /// behaves inside screens that already work. A second scope here would give
  /// the two that do have a focus contract different semantics than they have
  /// on desktop, for no gain.
  final FocusNode _anchor = FocusNode(debugLabel: 'tv_nested_surface', canRequestFocus: false, skipTraversal: true);

  /// How long entry keeps trying. A section's first focusable control can
  /// arrive several frames late — `LibrariesScreen` resolves its selected
  /// library from storage in a post-frame callback and only then builds a
  /// grid — so a single attempt on the frame the route mounts is a coin
  /// flip. Bounded, because "keep trying forever" is how a late retry steals
  /// the remote back from a viewer who has already moved on.
  static const Duration _entryBudget = Duration(seconds: 5);
  static const Duration _retryInterval = Duration(milliseconds: 120);

  /// Held so it can be cancelled. A bare `Future.delayed` cannot be, and a
  /// retry that outlives its widget is the shape of bug this codebase already
  /// documents twice: a callback that fires after teardown and puts the focus
  /// somewhere the viewer has since left.
  Timer? _retry;
  bool _entryPending = false;
  DateTime? _entryDeadline;

  @override
  void dispose() {
    cancelPendingEntry();
    _anchor.dispose();
    super.dispose();
  }

  /// True when the remote is somewhere inside this route.
  bool get holdsFocus => _anchor.descendantsAreFocusable && _focusedDescendant != null;

  FocusNode? get _focusedDescendant {
    for (final node in _anchor.descendants) {
      if (node.hasPrimaryFocus) return node;
    }
    return null;
  }

  /// Put the remote inside this route. Returns whether a real target was
  /// asked for the focus.
  ///
  /// Deliberately not "is it focused now": `requestFocus` lands on the next
  /// frame, so nothing can answer that synchronously, and a getter that always
  /// said `false` would be worse than useless to a caller deciding whether to
  /// keep its intent armed. `false` means the subtree had nothing to focus
  /// yet, which is the case a pending intent exists for. A bounded retry runs
  /// either way until the focus is confirmed inside this route or the budget
  /// expires.
  bool focusEntry() {
    if (holdsFocus) return true;
    final asked = _attempt(allowFallback: !_hasScreenContract);
    _entryPending = true;
    _entryDeadline = DateTime.now().add(_entryBudget);
    _scheduleRetry();
    return asked;
  }

  bool get _hasScreenContract => widget.route.screenKey?.currentState is FocusableTab;

  /// [allowFallback] is false on the very first attempt against a screen that
  /// has its own contract, so that contract gets a frame to place the focus
  /// where it wants it before a generic rule puts it on whatever happens to
  /// come first in traversal order. From the first retry onwards the fallback
  /// is allowed, because a contract that placed nothing — `LibrariesScreen`
  /// returns early from `focusActiveTabIfReady` when no library is selected —
  /// must not leave the section unusable.
  bool _attempt({required bool allowFallback}) {
    if (widget.route.screenKey?.currentState case final FocusableTab tab) {
      tab.focusActiveTabIfReady();
      if (!allowFallback) return true;
      if (holdsFocus) return true;
    }
    return _focusFirstFocusable();
  }

  bool _focusFirstFocusable() {
    for (final node in _anchor.traversalDescendants) {
      if (!node.canRequestFocus || node.skipTraversal) continue;
      node.requestFocus();
      return true;
    }
    return false;
  }

  void _scheduleRetry() {
    _retry?.cancel();
    _retry = Timer(_retryInterval, () {
      if (!mounted || !_entryPending) return;
      if (holdsFocus || DateTime.now().isAfter(_entryDeadline!)) {
        cancelPendingEntry();
        return;
      }
      _attempt(allowFallback: true);
      _scheduleRetry();
    });
  }

  /// Stops a pending entry — used when something else deliberately takes the
  /// focus (a Back out of this route, a destination switch) so a retry cannot
  /// pull it back afterwards.
  void cancelPendingEntry() {
    _entryPending = false;
    _retry?.cancel();
    _retry = null;
  }

  @override
  Widget build(BuildContext context) => TvNestedBackOwner(
    child: Focus(focusNode: _anchor, canRequestFocus: false, skipTraversal: true, child: widget.child),
  );
}
