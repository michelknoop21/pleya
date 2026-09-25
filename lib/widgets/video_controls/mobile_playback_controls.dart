import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../mpv/mpv.dart';
import 'widgets/circular_control_button.dart';
import 'widgets/play_pause_stream_builder.dart';

/// The centre row of the mobile player: previous episode, play/pause, next
/// episode (no previous/next on live TV). Extracted from
/// `MobileVideoControls` without behavior change; play/pause carries
/// [AutomationIds.playerPlayPause] with `playing` as its state, the same id
/// the desktop/TV controls register.
class MobilePlaybackControls extends StatelessWidget {
  const MobilePlaybackControls({
    super.key,
    required this.player,
    required this.isLive,
    this.onPrevious,
    this.onNext,
    this.onCancelAutoHide,
    this.onStartAutoHide,
  });

  final Player player;
  final bool isLive;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onCancelAutoHide;
  final VoidCallback? onStartAutoHide;

  @override
  Widget build(BuildContext context) {
    return PlayPauseStreamBuilder(
      player: player,
      builder: (context, isPlaying) {
        return Row(
          mainAxisAlignment: .center,
          children: [
            if (!isLive) ...[
              // Previous episode button (greyed out when unavailable)
              CircularControlButton(
                semanticLabel: t.videoControls.previousButton,
                icon: Symbols.skip_previous_rounded,
                iconSize: 48,
                onPressed: onPrevious,
              ),
              const SizedBox(width: 24),
            ],
            AutomationNode(
              id: AutomationIds.playerPlayPause,
              role: 'button',
              state: () => {'playing': isPlaying},
              child: CircularControlButton(
                semanticLabel: isPlaying ? t.videoControls.pauseButton : t.videoControls.playButton,
                icon: isPlaying ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
                iconSize: 72,
                onPressed: () {
                  if (isPlaying) {
                    player.pause();
                    onCancelAutoHide?.call(); // Cancel auto-hide when paused
                  } else {
                    player.play();
                    onStartAutoHide?.call(); // Start auto-hide when playing
                  }
                },
              ),
            ),
            if (!isLive) ...[
              const SizedBox(width: 24),
              // Next episode button (greyed out when unavailable)
              CircularControlButton(
                semanticLabel: t.videoControls.nextButton,
                icon: Symbols.skip_next_rounded,
                iconSize: 48,
                onPressed: onNext,
              ),
            ],
          ],
        );
      },
    );
  }
}
