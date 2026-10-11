import 'package:flutter/widgets.dart';

import '../services/opened_file.dart';
import 'app_logger.dart';
import 'video_player_navigation.dart';

/// Plays the file at [path] that the system handed to Pleya.
///
/// A player that is on top is replaced, the way the next episode replaces
/// the current one: two players stacked would both keep decoding.
Future<void> playOpenedFile(BuildContext context, String path) async {
  appLogger.i('Opened file: starting playback');
  await navigateToVideoPlayer(
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
