import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../mpv/mpv.dart';
import 'film_frame_palette.dart';
import 'widgets/circular_control_button.dart';
import 'widgets/play_pause_stream_builder.dart';

/// The centre row of the mobile player: previous episode, play/pause, next
/// episode. Live TV has no previous/next, and neither does a film with nothing
/// before or after it in the queue: then the pair is not drawn and play stands
/// alone. An episode always keeps the pair, greyed where a direction is
/// missing (also for a Watch Together guest, who cannot navigate), so play
/// stays centred and the row does not change shape between episodes. Sizes follow mockup A (Filmbeeld): play 68 pt, skip 52 pt,
/// 18 pt between them, centred. Play/pause carries
/// [AutomationIds.playerPlayPause] with `playing` as its state, the same id
/// the desktop/TV controls register.
class MobilePlaybackControls extends StatelessWidget {
  const MobilePlaybackControls({
    super.key,
    required this.player,
    required this.isLive,
    this.isEpisode = false,
    this.onPrevious,
    this.onNext,
    this.onCancelAutoHide,
    this.onStartAutoHide,
  });

  final Player player;
  final bool isLive;
  final bool isEpisode;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onCancelAutoHide;
  final VoidCallback? onStartAutoHide;

  @override
  Widget build(BuildContext context) {
    final showSkip = !isLive && (isEpisode || onPrevious != null || onNext != null);
    return PlayPauseStreamBuilder(
      player: player,
      builder: (context, isPlaying) {
        return Row(
          mainAxisSize: .min,
          spacing: kFilmTransportGap,
          children: [
            if (showSkip)
              CircularControlButton(
                semanticLabel: t.videoControls.previousButton,
                icon: Symbols.skip_previous_rounded,
                iconSize: 26,
                dimension: kFilmSkipSize,
                onPressed: onPrevious,
              ),
            AutomationNode(
              id: AutomationIds.playerPlayPause,
              role: 'button',
              state: () => {'playing': isPlaying},
              child: CircularControlButton(
                semanticLabel: isPlaying ? t.videoControls.pauseButton : t.videoControls.playButton,
                icon: isPlaying ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
                iconSize: 36,
                dimension: kFilmPlaySize,
                primary: true,
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
            if (showSkip)
              CircularControlButton(
                semanticLabel: t.videoControls.nextButton,
                icon: Symbols.skip_next_rounded,
                iconSize: 26,
                dimension: kFilmSkipSize,
                onPressed: onNext,
              ),
          ],
        );
      },
    );
  }
}
