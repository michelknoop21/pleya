import 'package:flutter/material.dart';

import '../widgets/notice/notice.dart';
import '../widgets/notice/notice_controller.dart';
import 'layout_constants.dart';

/// Global key for the root ScaffoldMessenger. A handful of call sites
/// elsewhere (dialogs.dart, add_local_folder_screen.dart, ...) still use it
/// directly for a native [SnackBar]; unrelated to the [Notice] system below.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Types of snackbars available in the app.
enum SnackBarType { info, success, error }

NoticeLevel _levelFor(SnackBarType type) => switch (type) {
  SnackBarType.info => NoticeLevel.info,
  SnackBarType.success => NoticeLevel.success,
  SnackBarType.error => NoticeLevel.error,
};

/// Compatibility facade over [NoticeController]/`NoticeHost`. Every one of
/// this file's existing call sites keeps working unchanged — they render as
/// notice cards now instead of raw [SnackBar]s, with AA-contrast colors, tv
/// scaling, and a close button (plus swipe-to-dismiss on mobile) they didn't
/// have before.
///
/// [context] and [dismissible] are accepted for source compatibility but are
/// no longer load-bearing: a notice is shown globally (`NoticeController`
/// needs no [BuildContext]) and is always dismissible. [duration], when
/// passed, overrides the level's default duration — most callers should
/// leave it null and let [type] decide.
void showSnackBar(
  BuildContext context,
  String message, {
  SnackBarType type = SnackBarType.info,
  Duration? duration,
  bool? dismissible,
}) {
  noticeController.show(Notice(level: _levelFor(type), title: message, groupKey: message, durationOverride: duration));
}

void showAppSnackBar(BuildContext context, String message, {Duration? duration}) {
  showSnackBar(context, message, type: SnackBarType.info, duration: duration);
}

void showErrorSnackBar(BuildContext context, String message) {
  showSnackBar(context, message, type: SnackBarType.error);
}

/// Shows an info notice. Used to route through the main-screen
/// `ScaffoldMessenger` so it would float above the mobile `NavigationBar`;
/// `NoticeHost` already renders above it for every screen, so that detour is
/// gone. Repeated calls with the same [message] within the dedupe window
/// (`NoticeController.dedupeWindow`) refresh the existing card's timer
/// instead of stacking a duplicate — the same "press again to confirm"
/// behavior the old `removeCurrentSnackBar` + re-show got by hand.
void showMainSnackBar(String message, {Duration duration = AppDurations.snackBarDefault}) {
  noticeController.show(Notice(level: NoticeLevel.info, title: message, groupKey: message, durationOverride: duration));
}

void showSuccessSnackBar(BuildContext context, String message) {
  showSnackBar(context, message, type: SnackBarType.success);
}
