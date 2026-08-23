import 'package:flutter/material.dart';

/// Owns which side of the shell has the focus: the navigation rail or the
/// content beside it. The rail draws itself open while this says the sidebar
/// is focused, so this is also what decides whether the rail is open.
///
/// It used to be a plain `bool` on the main screen, flipped by hand in the two
/// methods that move focus. That made it a second source of truth, and the two
/// drifted apart in both directions:
///
///  * Focus could leave the rail without the flag hearing about it — a route
///    pushed from a rail row and popped back, a pointer landing in the
///    content, a rail row disappearing under the focus that was on it. The
///    flag stayed `true` and the rail stayed open with nothing on it, and on a
///    remote there was then no key that led out.
///  * Focus could stay in the rail while the flag said it had left. Moving to
///    the content was a request the target screen was allowed to decline —
///    Libraries declines while no library is selected, Settings outside
///    keyboard mode — and a declined request left the remote on the nav item
///    the user had just pressed.
///
/// So the flag is derived from [sidebarScope] rather than mirrored, and every
/// deferred piece of focus work carries the [intent] it was scheduled under.
/// A callback whose intent has been superseded does nothing: with fast
/// repeated remote input two intents land inside one frame, and the older one
/// must not decide where the focus ends up.
class SidebarFocusCoordinator extends ChangeNotifier {
  SidebarFocusCoordinator({FocusScopeNode? sidebarScope, FocusScopeNode? contentScope})
    : sidebarScope = sidebarScope ?? FocusScopeNode(debugLabel: 'Sidebar'),
      contentScope = contentScope ?? FocusScopeNode(debugLabel: 'Content') {
    this.sidebarScope.addListener(_handleSidebarFocusChanged);
  }

  final FocusScopeNode sidebarScope;
  final FocusScopeNode contentScope;

  bool _isSidebarFocused = false;

  /// Whether the rail currently holds the focus, and therefore whether it is
  /// drawn open.
  bool get isSidebarFocused => _isSidebarFocused;

  int _intent = 0;

  /// The number of the most recent focus request. Deferred work captures this
  /// before it waits and passes it to [ownsIntent] when it resumes.
  int get intent => _intent;

  /// Whether [candidate] is still the live intent. `false` once a newer
  /// request has been made, which is the signal for a late callback to stand
  /// down instead of overwriting it.
  bool ownsIntent(int candidate) => candidate == _intent;

  bool _disposed = false;

  /// Move the focus to the rail.
  ///
  /// [focusActiveItem] runs after the frame, once the scope holds the focus,
  /// and only while this request is still the live one.
  void focusSidebar({required VoidCallback focusActiveItem}) {
    final intent = ++_intent;
    _setSidebarFocused(true);
    sidebarScope.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !ownsIntent(intent)) return;
      focusActiveItem();
    });
  }

  /// Move the focus to the content.
  ///
  /// Primary focus leaves the rail synchronously, not in the deferred
  /// callback: [focusDefault] is allowed to decline, and when it declined the
  /// focus used to stay on the nav item the user had just activated. Asking
  /// the scope is enough on its own — with no focusable child yet the scope
  /// itself takes primary focus, which is still out of the rail.
  ///
  /// With [restorePreviousFocus] the scope brings back whatever it had focused
  /// before, and [focusDefault] only runs if it had nothing. Without it the
  /// remembered child is dropped first: a deliberate move to another
  /// destination should not land on the previous destination's position.
  void focusContent({bool restorePreviousFocus = true, required VoidCallback focusDefault}) {
    final intent = ++_intent;
    _setSidebarFocused(false);
    if (restorePreviousFocus) {
      contentScope.requestFocus();
    } else {
      // The scope itself, deliberately not its remembered child.
      // `requestFocus()` walks down into whatever the scope had focused last,
      // which for a move to another destination is a row of the tab the user
      // just left — still mounted behind the new one in the IndexedStack, so a
      // perfectly valid thing to focus and completely invisible. And
      // `focusedChild?.unfocus()` does not prevent that: `unfocus` returns
      // immediately for a node that does not currently have the focus, which
      // that one does not — the rail does.
      contentScope.requestScopeFocus();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !ownsIntent(intent)) return;
      if (restorePreviousFocus && contentScope.focusedChild != null) return;
      focusDefault();
    });
  }

  void _handleSidebarFocusChanged() {
    if (_disposed) return;
    _setSidebarFocused(sidebarScope.hasFocus);
  }

  void _setSidebarFocused(bool value) {
    if (_isSidebarFocused == value) return;
    _isSidebarFocused = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    sidebarScope.removeListener(_handleSidebarFocusChanged);
    sidebarScope.dispose();
    contentScope.dispose();
    super.dispose();
  }
}
