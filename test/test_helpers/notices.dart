/// Helpers for the global `noticeController`, which is what the app's
/// user-facing messages actually go through.
///
/// `showSnackBar` / `showErrorSnackBar` / `showSuccessSnackBar` are a facade
/// over `NoticeController` rather than Material `SnackBar`s — see
/// `lib/utils/snackbar_helper.dart`. Two things follow for widget tests, and
/// both of them bit several test files that predate that migration:
///
/// 1. A message is **not** in the widget tree unless a `NoticeHost` is mounted.
///    `find.text(...)` finds nothing; assert on [noticeTitles] instead.
/// 2. Every notice arms a multi-second auto-dismiss timer on a *global*
///    controller. A timer still pending when the widget tree goes away fails
///    the test binding's `!timersPending` invariant, and the failure names the
///    notice rather than whatever the test was actually exercising.
library;

import 'package:pleya/widgets/notice/notice_controller.dart';

/// Titles of the notices currently on screen (or that would be, given a host).
///
/// The replacement for `find.text(someMessage)` in a tree without a
/// `NoticeHost`. It reads a process-global controller, so a `contains` here
/// only proves *this* test showed the message if the controller started out
/// empty: pair it with `setUp(resetNotices)`.
List<String> noticeTitles() => noticeController.visible.map((e) => e.notice.title).toList();

/// Empties the controller — visible and queued — cancelling every auto-dismiss
/// timer with it.
///
/// Two uses, both needed:
///
/// * `setUp(resetNotices)`, so [noticeTitles] starts from a known-empty state
///   and an assertion on it is a statement about this test.
/// * From inside the test body, after the action that shows a notice, to clear
///   its timer. Not from `tearDown`: the binding checks `!timersPending`
///   before teardown callbacks run, so cleaning up there is too late.
///
/// Dismissing the visible ones is enough to reach the queue as well.
/// `NoticeController.show` only queues while `_visible` is full, and every
/// `dismiss` promotes one queued notice into the freed slot (arming its timer,
/// which is exactly why a single pass over the visible snapshot left timers
/// behind). Draining until nothing is visible therefore empties both lists,
/// and it terminates because nothing here shows a new notice.
void resetNotices() {
  while (noticeController.visible.isNotEmpty) {
    noticeController.dismiss(noticeController.visible.first.id);
  }
}
