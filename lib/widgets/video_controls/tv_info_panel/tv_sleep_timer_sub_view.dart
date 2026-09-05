import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../mpv/mpv.dart';
import '../../../services/sleep_timer_service.dart';
import '../../../utils/formatters.dart';
import 'tv_panel_widgets.dart';

/// The sleep timer as a panel sub-view, on [SleepTimerService] itself rather
/// than on `SleepTimerContent`: that widget closes through the overlay-sheet
/// controller and, without a sheet scope above it, pops the player route.
class TvSleepTimerSubView extends StatelessWidget {
  final Player player;
  final FocusNode firstFocusNode;
  final VoidCallback onDone;

  const TvSleepTimerSubView({super.key, required this.player, required this.firstFocusNode, required this.onDone});

  static const List<int> durationsMinutes = [5, 10, 15, 30, 45, 60, 90, 120];

  @override
  Widget build(BuildContext context) {
    final sleepTimer = SleepTimerService();
    return ListenableBuilder(
      listenable: sleepTimer,
      builder: (context, _) {
        final isActive = sleepTimer.isActive;
        final activeMinutes = isActive && !sleepTimer.isEndOfVideoMode ? sleepTimer.originalDuration?.inMinutes : null;
        final is24Hour = MediaQuery.alwaysUse24HourFormatOf(context);

        final left = <Widget>[];
        var first = true;
        if (isActive) {
          final remaining = sleepTimer.remainingTime;
          final endTime = sleepTimer.endTime;
          left.add(TvPanelSectionHeader(label: t.videoSettings.sleepTimer));
          left.add(
            TvPanelGroup(
              children: [
                TvPanelRow(
                  focusNode: firstFocusNode,
                  title: t.videoControls.tvPanel.sleepActive,
                  subtitle: sleepTimer.isEndOfVideoMode
                      ? t.videoControls.sleepTimerEndOfVideo
                      : (remaining != null && endTime != null
                            ? t.videoControls.tvPanel.sleepActiveHint(
                                time: formatClockTime(endTime, is24Hour: is24Hour),
                                remaining: formatDurationWithSeconds(remaining),
                              )
                            : null),
                  value: t.common.cancel,
                  onSelect: () {
                    sleepTimer.cancelTimer();
                    onDone();
                  },
                ),
              ],
            ),
          );
          left.add(const SizedBox(height: 14));
          first = false;
        }
        left.add(TvPanelSectionHeader(label: t.videoControls.sleepTimerStopAtHeader));
        left.add(
          TvPanelGroup(
            children: [
              TvPanelRow.choice(
                focusNode: first ? firstFocusNode : null,
                title: t.videoControls.sleepTimerEndOfVideo,
                selected: sleepTimer.isEndOfVideoMode,
                onSelect: () {
                  sleepTimer.armEndOfVideo(() => player.pause());
                  onDone();
                },
              ),
            ],
          ),
        );

        final right = <Widget>[
          TvPanelSectionHeader(label: t.videoControls.tvPanel.sleepAfter),
          TvPanelGroup(
            children: [
              for (final minutes in durationsMinutes)
                TvPanelRow.choice(
                  title: formatDurationTextual(minutes * 60 * 1000, abbreviated: false),
                  selected: minutes == activeMinutes,
                  onSelect: () {
                    sleepTimer.startTimer(Duration(minutes: minutes), () => player.pause());
                    onDone();
                  },
                ),
            ],
          ),
        ];
        return TvPanelColumns(left: left, right: right);
      },
    );
  }
}
