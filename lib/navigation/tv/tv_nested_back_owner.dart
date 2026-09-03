import 'package:flutter/widgets.dart';

/// Marks the subtree of a TV nested route, where the shell owns the Back key.
///
/// `TvRootShell`'s own doc already states the rule: the back chain is overlay
/// -> nested route -> content -> top navigation -> system, and nothing below
/// the shell may short-circuit it. In practice something did. Flutter
/// dispatches a key to the focused node first and only walks to ancestors
/// while the result is `ignored`, so any descendant that answers `handled`
/// ends the walk before `MainScreen._handleTvShellKey` is ever asked.
///
/// `TvBrowseRail` is such a descendant. It runs `handleBackKeyAction` on its
/// own `onBack`, and `LibrariesScreen` wires that `onBack` to `focusTabBar` —
/// a move of the focus *within* the screen, not a way out of it. So on a real
/// Apple TV, opening Mijn Pleya > Media and pressing Menu moved the ring to
/// the tab strip and left the section open. Pressing it again did the same
/// thing. There was no way back to the hub at all.
///
/// The two meanings of "back" are what collide: dismissing something, and
/// stepping up inside something. The first belongs to whoever owns the
/// surface, the second does not belong on the Back key at all while a surface
/// above it is still waiting to be dismissed. This marker lets the second kind
/// stand down without every widget needing to know what is above it.
class TvNestedBackOwner extends InheritedWidget {
  const TvNestedBackOwner({super.key, required super.child});

  /// Whether an enclosing TV nested route owns the Back key here.
  ///
  /// A read rather than a dependency: the answer changes only when the whole
  /// subtree is built or torn down, so a widget that consults it on a key
  /// press has nothing to rebuild for.
  static bool of(BuildContext context) => context.getInheritedWidgetOfExactType<TvNestedBackOwner>() != null;

  @override
  bool updateShouldNotify(TvNestedBackOwner oldWidget) => false;
}
