import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../mpv/mpv.dart';
import '../../watch_together/providers/watch_together_provider.dart';

/// Whether this player writes watch state (progress, timeline, scrobbles).
/// A phone that follows an Apple TV does not: only the Apple TV writes, so one
/// account never gets two writers with almost the same position (Pleya Fly
/// Meenemen, A-23e, decision Michel 8 November 2026).
bool playbackReportsAllowed(WatchTogetherProvider? watchTogether) => !(watchTogether?.isFlyFollower ?? false);

/// A phone that follows an Apple TV starts without sound (Pleya Fly Meenemen,
/// A-23e, 45-i): the room hears the Apple TV. "Geluid aan" brings the usual
/// level back. The volume setting is never written, so the next player opens
/// at the usual level.
class FlyFollowMute {
  final ValueNotifier<bool> muted = ValueNotifier(false);

  /// Mutes [player] when this phone [following]ly attached; true when it did.
  bool engage(Player player, {required bool following}) {
    if (!following || muted.value) return false;
    muted.value = true;
    unawaited(player.setVolume(0));
    return true;
  }

  /// "Geluid aan": back to [volume].
  Future<void> release(Player? player, double volume) async {
    if (!muted.value) return;
    muted.value = false;
    await player?.setVolume(volume);
  }

  void dispose() => muted.dispose();
}
