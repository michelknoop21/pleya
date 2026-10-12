import 'dart:async';

import 'package:flutter/widgets.dart';

import '../media/media_item.dart';
import '../services/opened_file.dart';
import '../services/opened_file_service.dart';
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
      void Function(Future<void> gone)? onPlayerRoute,
    });

/// Plays the file at [path] that the system handed to Pleya.
///
/// A player is replaced, the way the next episode replaces the current one:
/// two players stacked would both keep decoding. Under a dialog or a sheet
/// the player is uncovered first.
Future<void> playOpenedFile(
  BuildContext context,
  String path, {
  @visibleForTesting OpenedFileNavigation navigate = navigateToVideoPlayer,
  @visibleForTesting OpenedFileService? service,
  @visibleForTesting Route<dynamic>? player,
}) async {
  appLogger.i('Opened file: starting playback');
  final files = service ?? OpenedFileService.instance;
  final release = files.markPlaying(path);
  var started = false;
  try {
    // Returns when the player is closed or replaced by the next file.
    await navigate(
      context,
      metadata: openedFileItem(path),
      resolveWatchState: false,
      // The player's offline start is the one that needs no server client; the
      // online start throws when no client is registered for the item.
      isOffline: true,
      usePushReplacement: uncoverPlayer(Navigator.of(context), player: player),
      // The push of a navigator that is torn down never completes; the
      // route's disposal still arrives.
      onPlayerRoute: (gone) {
        started = true;
        unawaited(gone.whenComplete(release));
      },
    );
  } finally {
    // A start that ended because its screen went away has not played the
    // file: it waits for the next screen instead of being deleted unseen.
    if (!started && !context.mounted) files.defer(path);
    release();
  }
}

/// Whether the player is, or has been made, the top route of [navigator]. A
/// dialog or sheet lying over it is closed: it would otherwise be replaced
/// in the player's place and leave a second player under it.
@visibleForTesting
bool uncoverPlayer(NavigatorState navigator, {Route<dynamic>? player}) {
  if (isVideoPlayerOnTop(navigator)) return true;
  final route = player ?? activePlayerRoute;
  // A player on another navigator is none of this one's business.
  if (route == null || !route.isActive || route.navigator != navigator) return false;
  navigator.popUntil((candidate) => identical(candidate, route));
  return true;
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
