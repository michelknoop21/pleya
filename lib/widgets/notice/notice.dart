import 'package:flutter/foundation.dart';

/// Severity of a [Notice]. Drives color, icon, and the default on-screen
/// duration — callers don't pick a duration, they pick a level.
enum NoticeLevel { success, info, warning, error }

/// How long a [Notice] stays on screen before auto-dismissing. `null` means
/// it stays until the user dismisses it or runs an action.
Duration? noticeDurationFor(NoticeLevel level) => switch (level) {
  NoticeLevel.success => const Duration(seconds: 3),
  NoticeLevel.info => const Duration(seconds: 5),
  NoticeLevel.warning => const Duration(seconds: 8),
  NoticeLevel.error => null,
};

/// A button on a [Notice]. [onPressed] is created at the call site — where a
/// real [BuildContext] (profile-scoped navigator, provider tree) is
/// available — and merely invoked by [NoticeHost]. Never build navigation
/// off the host's own context: it sits outside `ProfileNavigationScope`,
/// see the CLAUDE.md gotcha on `ProfileNavigationScope is required for
/// profile routes`.
@immutable
class NoticeAction {
  final String label;
  final VoidCallback onPressed;

  const NoticeAction({required this.label, required this.onPressed});
}

/// A single in-app notice. Immutable — a repeated notice with the same
/// [level] + [groupKey] within the dedupe window is folded into a counter by
/// [NoticeController] rather than replacing this instance, so [reportCode]
/// keeps pointing at the *first* occurrence's log line.
///
/// [groupKey] is the caller's responsibility to make specific enough: a
/// bare `"network"` would fold together unrelated servers. Prefer including
/// whatever identifies the failing thing (server id, screen, action).
@immutable
class Notice {
  final NoticeLevel level;
  final String title;
  final String? body;
  final NoticeAction? primary;
  final NoticeAction? secondary;

  /// Four-char uppercase hex code (`[0-9A-F]{4}`) pointing at the matching
  /// `appLogger.e('[XXXX] ...')` line, so a report can be traced back to a
  /// log entry. Not a unique id — a correlation hint, generated per error
  /// event via `noticeCode()` in `app_logger.dart`.
  final String? reportCode;

  final String groupKey;

  /// Overrides the level-derived duration. Exists for
  /// `snackbar_helper.dart`'s compatibility facade, which must honor a small
  /// number of pre-existing callers with timing-sensitive durations (e.g.
  /// the "press back again to exit" window), and for playback failures,
  /// which are errors that are over by the time they show: the player has
  /// already closed, so they get a bounded stay instead of waiting to be
  /// clicked away (see `noticeForPlaybackFailureKind`). Other new call sites
  /// should not set this — let [level] decide.
  final Duration? durationOverride;

  const Notice({
    required this.level,
    required this.title,
    this.body,
    this.primary,
    this.secondary,
    this.reportCode,
    required this.groupKey,
    this.durationOverride,
  });

  Duration? get duration => durationOverride ?? noticeDurationFor(level);
}
