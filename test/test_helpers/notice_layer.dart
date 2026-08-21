import 'package:flutter/material.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/widgets/notice/notice_controller.dart';
import 'package:pleya/widgets/notice/notice_host.dart';

/// Mount the notice layer the way the running app does.
///
/// Since the notice rework, `showErrorSnackBar` and friends no longer build a
/// `SnackBar` into the screen that called them: they hand the message to the
/// global [noticeController], and `NoticeHost` renders it as a `Stack` layer
/// inside `MaterialApp.builder` in the app shell (`main.dart`).
///
/// A test that pumps a bare `MaterialApp(home: SomeScreen())` therefore has no
/// renderer for that message. The screen behaves correctly, the controller
/// receives the notice, and `find.text(...)` still finds nothing — which is
/// exactly what left fifteen tests red on main.
///
/// Pass this as the `builder` of the `MaterialApp` under test:
///
/// ```dart
/// MaterialApp(builder: noticeLayer, home: LogsScreen(...))
/// ```
Widget noticeLayer(BuildContext context, Widget? child) {
  // A notice card reads its colours from the MonoTokens theme extension, and
  // `tokens()` null-checks it. A test that pumps a themeless MaterialApp would
  // otherwise trade the missing message for a type error; one that brings its
  // own monoTheme keeps it.
  const host = _NoticeTestScope(child: NoticeHost());
  final themed = Theme.of(context).extension<MonoTokens>() == null
      ? Theme(data: monoTheme(dark: true), child: host)
      : host;
  return Stack(children: [if (child != null) child, themed]);
}

/// Cancels the notice timers when the tree comes down.
///
/// A notice that auto-dismisses holds a `Timer`, and `testWidgets` fails a test
/// that leaves one pending. The check runs while the tree is being torn down,
/// which is earlier than `tearDown` and earlier than `addTearDown`, so the only
/// place that reliably gets there first is a `dispose()` inside the tree.
class _NoticeTestScope extends StatefulWidget {
  const _NoticeTestScope({required this.child});

  final Widget child;

  @override
  State<_NoticeTestScope> createState() => _NoticeTestScopeState();
}

class _NoticeTestScopeState extends State<_NoticeTestScope> {
  @override
  void dispose() {
    noticeController.debugReset(notify: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The same layer as a `MaterialApp.builder`, composed over an existing one.
///
/// Several screens under test already use `builder` for something of their own
/// (a `MediaQuery` override, for instance), so this wraps rather than replaces:
/// `builder: withNoticeLayer(myBuilder)`.
TransitionBuilder withNoticeLayer([TransitionBuilder? inner]) =>
    (context, child) => noticeLayer(context, inner == null ? child : inner(context, child));

/// Clear notices left standing by an earlier test. Call from `setUp`.
///
/// The controller is a singleton and its dedupe window is ten seconds, so
/// without this a message from the previous test is still on screen and the
/// next identical one folds into it instead of appearing.
void resetNotices() => noticeController.debugReset();
