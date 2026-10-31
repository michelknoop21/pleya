import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../automation/automation_ids.dart';
import '../automation/automation_node.dart';
import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../providers/watch_state_store.dart';
import '../utils/app_logger.dart';
import '../utils/video_player_navigation.dart';
import 'app_icon.dart';

/// The Afspelen pill of the desktop and tablet Home hero.
///
/// Fixed white pill: TV does not reach this widget at all (its hero is
/// `TvHeroBillboardCarousel`, which draws its own focus), and desktop keyboard
/// focus lands on the hero itself, not on this button.
class HomeHeroPlayButton extends StatelessWidget {
  const HomeHeroPlayButton({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    // The on-deck snapshot refetches shortly after a watch event; the store
    // patch bridges the gap so "minutes left" never lags.
    final heroItem = context.withFreshWatchState(item);
    final hasProgress = heroItem.hasActiveProgress;

    final minutesLeft = hasProgress ? ((heroItem.durationMs! - heroItem.viewOffsetMs!) / 60_000).round() : 0;

    final progress = hasProgress ? heroItem.viewOffsetMs! / heroItem.durationMs! : 0.0;

    const foregroundColor = Colors.black;
    const textStyle = TextStyle(color: foregroundColor, fontSize: 14, fontWeight: FontWeight.w600);
    return AutomationNode(
      id: AutomationIds.discoverHeroPlay,
      role: 'button',
      child: InkWell(
        onTap: () {
          appLogger.d('Playing: ${heroItem.title}');
          navigateToVideoPlayer(context, metadata: heroItem);
        },
        borderRadius: const BorderRadius.all(Radius.circular(24)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(24))),
          child: Row(
            mainAxisSize: .min,
            children: [
              const AppIcon(Symbols.play_arrow_rounded, fill: 1, size: 20, color: foregroundColor),
              const SizedBox(width: 8),
              if (hasProgress) ...[
                // Progress bar
                Container(
                  width: 40,
                  height: 6,
                  decoration: BoxDecoration(
                    color: foregroundColor.withValues(alpha: 0.25),
                    borderRadius: const BorderRadius.all(Radius.circular(3)),
                  ),
                  child: FractionallySizedBox(
                    alignment: .centerLeft,
                    widthFactor: progress,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: foregroundColor,
                        borderRadius: BorderRadius.all(Radius.circular(2)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(t.discover.minutesLeft(minutes: minutesLeft), style: textStyle),
              ] else
                Text(t.common.play, style: textStyle),
            ],
          ),
        ),
      ),
    );
  }
}
