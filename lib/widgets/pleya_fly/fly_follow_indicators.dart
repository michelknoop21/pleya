/// The small pieces of Pleya Fly Meenemen (A-23e) inside the players: the
/// sync line and the sound button on the phone (45-i), the label in the Apple
/// TV's info line (45-t5) and the notices on both sides (45-t4).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../watch_together/providers/watch_together_provider.dart';
import '../app_icon.dart';
import '../notice/notice.dart';
import '../notice/notice_controller.dart';
import '../pleya_fly_icon.dart';

/// The green of "in sync" in the mockups.
const flySyncGreen = Color(0xFF34C759);

class _SyncDot extends StatelessWidget {
  const _SyncDot({this.size = 7});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(color: flySyncGreen, shape: BoxShape.circle),
  );
}

/// "● Synchroon met Woonkamer" under the title of a phone that follows (45-i).
class FlySyncedWithLine extends StatelessWidget {
  const FlySyncedWithLine({super.key});

  @override
  Widget build(BuildContext context) {
    final name = context.select<WatchTogetherProvider?, String?>((p) => p?.flyHostName);
    if (name == null) return const SizedBox.shrink();
    return AutomationNode(
      id: AutomationIds.playerFlySyncedWith,
      role: 'status',
      state: () => {'host': name},
      child: Row(
        mainAxisSize: .min,
        children: [
          const _SyncDot(),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              t.flyFollow.syncedWith(name: name),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              maxLines: 1,
              overflow: .ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// The pill in the Apple TV's info line while a phone follows (45-t5).
class FlyFollowersLabel extends StatelessWidget {
  const FlyFollowersLabel({super.key});

  @override
  Widget build(BuildContext context) {
    // Joined to a string: a list would differ on every read and rebuild on every heartbeat.
    final names = context.select<WatchTogetherProvider?, String>((p) => p?.flyFollowerNames.join(', ') ?? '');
    if (names.isEmpty) return const SizedBox.shrink();
    return AutomationNode(
      id: AutomationIds.playerFlyFollowers,
      role: 'status',
      state: () => {'followers': names},
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 3, 11, 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: const BorderRadius.all(Radius.circular(999)),
        ),
        child: Row(
          mainAxisSize: .min,
          children: [
            const _SyncDot(size: 6),
            const SizedBox(width: 6),
            const PleyaFlyIcon(size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                t.flyFollow.watchingAlong(name: names),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                maxLines: 1,
                overflow: .ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Geluid aan" where the thumb already is (45-i): a following phone starts
/// muted, because the room hears the Apple TV.
class FlySoundOnButton extends StatelessWidget {
  const FlySoundOnButton({super.key, required this.muted, required this.onUnmute});

  final ValueListenable<bool> muted;
  final VoidCallback onUnmute;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: muted,
      builder: (context, isMuted, _) {
        if (!isMuted) return const SizedBox.shrink();
        return AutomationNode(
          id: AutomationIds.playerFlySoundOn,
          role: 'button',
          child: Material(
            color: Colors.white.withValues(alpha: 0.92),
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onUnmute,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 8, 14, 8),
                child: Row(
                  mainAxisSize: .min,
                  children: [
                    const AppIcon(Symbols.volume_off_rounded, color: Color(0xFF141414), size: 20),
                    const SizedBox(width: 8),
                    Text(
                      t.flyFollow.soundOn,
                      style: const TextStyle(color: Color(0xFF141414), fontSize: 13, fontWeight: .w700),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The Apple TV's notice when a phone starts to follow (45-t4).
void showFlyWatchingAlongNotice(String name) => noticeController.show(
  Notice(
    level: NoticeLevel.info,
    title: t.flyFollow.watchingAlong(name: name),
    body: t.flyFollow.watchingAlongBody,
    groupKey: 'pleya-fly-follow:$name',
  ),
);

/// The phone's notice when the Apple TV it followed stopped (DEC point 7).
void showFlyTvStoppedNotice(String name) => noticeController.show(
  Notice(
    level: NoticeLevel.info,
    title: t.flyFollow.tvStopped(name: name),
    body: t.flyFollow.tvStoppedBody,
    groupKey: 'pleya-fly-stopped:$name',
  ),
);
