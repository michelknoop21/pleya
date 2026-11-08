/// The player rules of a phone that follows an Apple TV (Pleya Fly Meenemen,
/// A-23e): no watch state, no question when it leaves, and a muted start.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../mpv/mpv.dart';
import '../../utils/app_logger.dart';
import '../../watch_together/providers/watch_together_provider.dart';

/// Whether this player writes watch state (progress, timeline, scrobbles).
/// A phone that follows an Apple TV does not: only the Apple TV writes, so one
/// account never gets two writers with almost the same position (decision
/// Michel, 8 November 2026).
bool playbackReportsAllowed(WatchTogetherProvider? watchTogether) => !(watchTogether?.isFlyFollower ?? false);

/// Starts one watch-state writer of the player, the progress tracker or the
/// scrobblers, unless this phone follows an Apple TV. Every writer starts
/// through here. True when [start] ran.
bool startWatchStateWriter(WatchTogetherProvider? watchTogether, String what, void Function() start) {
  if (!playbackReportsAllowed(watchTogether)) {
    appLogger.d('Meenemen: no $what, this phone follows an Apple TV');
    return false;
  }
  start();
  return true;
}

/// Back on a following phone leaves at once: no Samen kijken question, and
/// leaving before the exit pause keeps that pause off the Apple TV.
bool leavesWithoutConfirm(WatchTogetherProvider watchTogether) => watchTogether.isFlyFollower;

/// Closing the player of a Meenemen session ends this device's part in it: a
/// phone leaves, the Apple TV ends the session and every phone stops with it.
/// A player that replaces itself with the next video keeps the session.
bool leavesFlySessionOnExit(WatchTogetherProvider watchTogether, {required bool replacingWithVideo}) =>
    watchTogether.isFlySession && !replacingWithVideo;

/// A following phone starts without sound (45-i): the room hears the Apple
/// TV. "Geluid aan" brings the usual level back, and so does any other volume
/// change through the player. The volume setting is never written, so the
/// next player opens at the usual level.
class FlyFollowMute {
  final ValueNotifier<bool> muted = ValueNotifier(false);
  StreamSubscription<double>? _volume;
  bool _disposed = false;

  /// Mutes [player] when this phone [following]ly attached; true when it did.
  bool engage(Player player, {required bool following}) {
    if (_disposed || !following || muted.value) return false;
    muted.value = true;
    unawaited(player.setVolume(0));
    // Sound turned up through the player (the remote's volume command, or any
    // other setVolume): the button goes. The stream reports only player
    // volume, so the hardware buttons and Control Center leave it standing.
    _volume = player.streams.volume.listen((volume) {
      if (volume > 0) _clear();
    });
    return true;
  }

  /// "Geluid aan": back to [volume].
  Future<void> release(Player? player, double volume) async {
    if (_disposed || !muted.value) return;
    _clear();
    await player?.setVolume(volume);
  }

  void _clear() {
    unawaited(_volume?.cancel());
    _volume = null;
    if (!_disposed) muted.value = false;
  }

  void dispose() {
    _disposed = true;
    unawaited(_volume?.cancel());
    muted.dispose();
  }
}
