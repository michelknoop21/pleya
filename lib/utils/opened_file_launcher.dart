import 'package:flutter/widgets.dart';

import '../media/media_item.dart';
import '../services/opened_file.dart';
import 'app_logger.dart';
import 'video_player_navigation.dart';

/// The part of [navigateToVideoPlayer] an opened file uses.
typedef OpenedFileNavigation =
    Future<bool?> Function(
      BuildContext context, {
      required MediaItem metadata,
      bool usePushReplacement,
      bool isOffline,
      bool resolveWatchState,
    });

/// Plays the file at [path] that the system handed to Pleya.
///
/// A player that is on top is replaced, the way the next episode replaces
/// the current one: two players stacked would both keep decoding.
Future<void> playOpenedFile(
  BuildContext context,
  String path, {
  @visibleForTesting OpenedFileNavigation navigate = navigateToVideoPlayer,
}) async {
  appLogger.i('Opened file: starting playback');
  await navigate(
    context,
    metadata: openedFileItem(path),
    resolveWatchState: false,
    // The player's offline start is the one that needs no server client; the
    // online start throws when no client is registered for the item.
    isOffline: true,
    usePushReplacement: isVideoPlayerOnTop(Navigator.of(context)),
  );
}

/// Whether the top route of [navigator] is the video player.
@visibleForTesting
bool isVideoPlayerOnTop(NavigatorState navigator) {
  String? top;
  navigator.popUntil((route) {
    top = route.settings.name;
    return true;
  });
  return top == kVideoPlayerRouteName;
}

/// Whether a route on an outer navigator lies over the one [context] lives in:
/// the profile chooser, a dialog or a page pushed on the root navigator. A
/// player started now would play out of sight, with sound.
bool isCoveredByOuterRoute(BuildContext context) {
  var current = context;
  var covered = false;
  var innermost = true;
  while (true) {
    final route = ModalRoute.of(current);
    // Not Navigator.maybeOf: for a navigator's own context that answers the
    // navigator itself, and the walk would never leave it.
    final navigator = current.findAncestorStateOfType<NavigatorState>();
    if (route == null || navigator == null) return covered;
    // The navigator the player is pushed on may hold anything on top; only
    // the navigators around it hide the player.
    if (!innermost && !route.isCurrent) covered = true;
    innermost = false;
    current = navigator.context;
  }
}
