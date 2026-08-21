import 'package:flutter/widgets.dart';

import '../../focus/dpad_navigator.dart';
import '../../focus/key_event_utils.dart';
import '../../utils/native_input_session.dart';
import '../../utils/platform_detector.dart';
import 'notice_controller.dart';

/// Lets Back/Menu close a persistent notice on TV.
///
/// This is not a convenience. A notice card is mounted above the `Navigator`,
/// and directional traversal only walks the focused route's `FocusScope`, so
/// no amount of d-pad pressing can ever reach the card's close button. Without
/// this handler a persistent notice on a television cannot be removed at all.
///
/// Only [Notice.isPersistent] notices are eligible, which after the duration
/// policy means "an error offering a recovery action". Anything with a timer
/// clears itself within seconds, so intercepting Back for those would take
/// navigation away and buy nothing — and it would break the
/// press-back-again-to-exit window in `MainScreen`, which is itself a notice.
///
/// An early key handler is the only layer that can do this: [FocusManager]
/// walks the focus tree regardless of what a [HardwareKeyboard] handler
/// answered, and a `DismissIntent` shortcut fires on key-down while the rest
/// of this app acts on key-up, which would close the notice *and* navigate on
/// a single press. The actual edge handling is delegated to
/// [handleBackKeyAction] so the Apple TV down-only rule, [BackKeyUpSuppressor]
/// and [BackKeyCoordinator] all behave exactly as they do everywhere else.
///
/// Known limit: at the root screen of Apple TV, tvOS hands Menu to UIKit
/// natively, so consuming it here cannot keep the app in the foreground. That
/// is not a regression — today nothing dismisses a notice there either.
class NoticeBackDismisser {
  NoticeBackDismisser._();

  static NoticeController _controller = noticeController;
  static bool _installed = false;

  static void install() {
    if (_installed) return;
    _installed = true;
    FocusManager.instance
      ..removeEarlyKeyEventHandler(handleKeyEvent)
      ..addEarlyKeyEventHandler(handleKeyEvent);
  }

  static void uninstall() {
    _installed = false;
    FocusManager.instance.removeEarlyKeyEventHandler(handleKeyEvent);
  }

  @visibleForTesting
  static set debugController(NoticeController controller) => _controller = controller;

  @visibleForTesting
  static void debugReset() {
    _controller = noticeController;
    uninstall();
  }

  @visibleForTesting
  static KeyEventResult handleKeyEvent(KeyEvent event) {
    if (!PlatformDetector.isTV()) return KeyEventResult.ignored;
    if (!event.logicalKey.isBackKey) return KeyEventResult.ignored;
    // Every early handler runs and the order between them is unspecified, so
    // the native text-entry gate answering `handled` does not stop this one.
    if (NativeInputSession.isActive) return KeyEventResult.ignored;

    final id = _topPersistentId();
    if (id == null) return KeyEventResult.ignored;
    return handleBackKeyAction(event, () => _controller.dismiss(id));
  }

  /// Newest first: the top card is the one the user is looking at.
  static String? _topPersistentId() {
    for (final entry in _controller.visible.reversed) {
      if (entry.notice.isPersistent) return entry.id;
    }
    return null;
  }
}
