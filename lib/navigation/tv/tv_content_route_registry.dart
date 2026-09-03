import 'package:flutter/widgets.dart';

import 'tv_navigation_coordinator.dart';

/// How a caller anywhere in the tree opens a screen without losing the TV shell.
///
/// **Why a registry and not a `Navigator`.** The screens that push content —
/// `navigateToMediaItem`, a settings tile, a cast chip — sit far below the
/// shell and have no reference to it. `Navigator.of(context)` is how they used
/// to reach out, and on TV that resolves to the one navigator
/// `ProfileSessionScreen` owns, which draws over the whole window and takes the
/// top bar with it. Putting a second `Navigator` inside the shell's content box
/// would capture those same calls implicitly, which is what DEC-069 refused,
/// and for a reason that still holds: `Navigator.pop` would then be ambiguous
/// between step 2 and step 3 of the back chain in hoofdstuk 7.5.
///
/// So the reach stays explicit. `MainScreen` publishes its push here while the
/// TV shell is mounted, and a caller asks for it by name instead of finding it
/// by accident. Off TV, and in any test that did not mount the shell, nothing
/// is attached and every caller keeps the profile navigator it always had.
///
/// PB-1 of `docs/tvos-redesign-implementatiecontract.md` is what made this
/// necessary: the approved detail, collection, person and settings surfaces
/// keep the top navigation, so they can no longer be a full-window push.
typedef TvContentRoutePush = Future<Object?> Function(TvNestedRoute route);

class TvContentRouteRegistry {
  TvContentRoutePush? _push;

  /// True while a TV shell is mounted and willing to host content routes.
  bool get isAvailable => _push != null;

  void attach(TvContentRoutePush push) => _push = push;

  /// Detaching is guarded on identity so a shell that is being replaced cannot
  /// tear down the one that already took over. Two `MainScreen`s overlap for a
  /// frame on a profile switch, and the outgoing `dispose` runs after the
  /// incoming `initState`.
  void detach(TvContentRoutePush push) {
    if (identical(_push, push)) _push = null;
  }

  /// Opens [route] inside the active destination, or returns null when no TV
  /// shell is listening — the caller's signal to push the way it always did.
  Future<Object?>? push(TvNestedRoute route) => _push?.call(route);
}

/// Process-wide, like `profileNavigationRegistry` next to it, and for the same
/// reason: there is exactly one shell, and the callers cannot be handed a
/// reference through a tree they are not part of.
final TvContentRouteRegistry tvContentRouteRegistry = TvContentRouteRegistry();

/// Opens [builder] inside the TV shell when there is one, and returns null when
/// there is not.
///
/// The null is the whole point of the shape: a caller writes the shell path and
/// the ordinary path next to each other, and no caller has to know what a TV
/// shell is beyond "it might be there".
///
/// [id] is the route's stable identity. `pushNested` discards a re-push of the
/// id already on top, so a second Select on the same tile opens one screen and
/// needs one Back, not two.
Future<Object?>? openTvContentRoute({
  required String id,
  required WidgetBuilder builder,
  String? restoreFocusKey,
  GlobalKey? screenKey,
}) {
  if (!tvContentRouteRegistry.isAvailable) return null;
  return tvContentRouteRegistry.push(
    TvNestedRoute(id: id, builder: builder, restoreFocusKey: restoreFocusKey, screenKey: screenKey),
  );
}
