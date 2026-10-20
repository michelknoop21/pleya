/// A-06b: the contract between a page that scrolls its chrome away and the TV
/// shell that owns the top navigation.
///
/// The shell publishes [TvTopNavScrollAwayScope] around a nested route opened
/// with `TvTopNavPresentation.scrollAway`; the page writes whether the remote is
/// past its first row, and the shell slides the bar away on that flag. A page
/// that finds no scope (a standalone mount, a persistent route, desktop) keeps
/// its heading where it always was.
library;

import 'package:flutter/widgets.dart';

import '../../theme/mono_tokens.dart';

/// The one motion the bar and the page heading share, so they leave and return
/// as one piece.
///
/// easeOutCubic both ways: it starts at speed and settles softly, which is
/// what reads as calm on a ten-foot screen. Returning is quicker than leaving
/// (Michel, 20 October 2026): the viewer pressed UP to get the heading back and
/// should not wait for it, while leaving can take its time because nothing is
/// being asked for. Reduce motion (system setting or Pleya's own TV switch)
/// makes both instant through [reduceMotion]. Same values as the iPhone
/// catalogue heading (A-06), so the two platforms move alike.
abstract final class TvTopNavScrollAwayMotion {
  static const Duration hide = Duration(milliseconds: 260);
  static const Duration show = Duration(milliseconds: 200);
  static const Curve curve = Curves.easeOutCubic;

  static Duration durationFor(BuildContext context, {required bool showing}) =>
      reduceMotion(context, showing ? show : hide);
}

/// Hands a scroll-away route's [pageScrolled] flag to the page it hosts.
class TvTopNavScrollAwayScope extends InheritedWidget {
  const TvTopNavScrollAwayScope({super.key, required this.pageScrolled, required super.child});

  /// True while the remote is past the page's first row. The page writes it,
  /// from focus callbacks and post-frame syncs only, never during a build.
  final ValueNotifier<bool> pageScrolled;

  static TvTopNavScrollAwayScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TvTopNavScrollAwayScope>();

  @override
  bool updateShouldNotify(TvTopNavScrollAwayScope oldWidget) => !identical(pageScrolled, oldWidget.pageScrolled);
}
