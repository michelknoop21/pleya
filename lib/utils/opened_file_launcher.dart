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
