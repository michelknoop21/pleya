import 'package:pleya/widgets/notice/notice_controller.dart';

/// Clears the global notice queue.
///
/// Call this at the end of a test body, never from `addTearDown`: an error
/// notice carries an auto-dismiss timer, and the test binding asserts that no
/// timers are pending *before* tearDowns run. A test that raises a notice and
/// leaves it behind fails with "A Timer is still pending even after the widget
/// tree was disposed", sometimes only under the load of a full-suite run.
void drainNotices() {
  for (final entry in noticeController.visible.toList()) {
    noticeController.dismiss(entry.id);
  }
}
