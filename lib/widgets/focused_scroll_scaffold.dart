import 'package:flutter/material.dart';
import '../focus/input_mode_tracker.dart';
import '../focus/key_event_utils.dart';
import 'desktop_app_bar.dart';
import 'ios_status_bar_tap_scroll_to_top.dart';
import 'scroll_crown/scroll_crown.dart';
import 'settings/settings_studio_bar.dart';

/// A scaffold widget that wraps Focus + Scaffold + CustomScrollView
/// with consistent keyboard navigation handling and app bar styling.
///
/// This widget reduces boilerplate for screens that need:
/// - Keyboard navigation (back key handling)
/// - Custom scrollable content with slivers
/// - Consistent app bar with title and optional actions
///
/// Automatically focuses the first content item (skipping the app bar)
/// when in keyboard navigation mode.
class FocusedScrollScaffold extends StatefulWidget {
  /// The title to display in the app bar.
  /// Can be a Text widget or a more complex widget like Column.
  final Widget title;

  /// The list of slivers to display in the scroll view.
  /// Should not include the app bar (it's added automatically).
  final List<Widget> slivers;

  /// Optional actions to display in the app bar (e.g., IconButton widgets).
  final List<Widget>? actions;

  /// Whether the app bar should remain visible when scrolling.
  /// Defaults to true.
  final bool pinned;

  /// Whether to automatically add a back button.
  /// Defaults to true.
  final bool automaticallyImplyLeading;

  /// Optional override for the back key handler.
  /// When set, this callback is invoked instead of the default
  /// [handleBackKeyNavigation] (which pops the current route).
  final VoidCallback? onBackPressed;

  /// A large header between the app bar and [slivers] that scrolls away with
  /// the content (A-24: the settings Studio header off TV). While it is in
  /// view the pinned bar leaves its own title out, and fades it in once the
  /// header has gone under the bar. Null keeps the plain bar.
  final Widget? header;

  const FocusedScrollScaffold({
    super.key,
    required this.title,
    required this.slivers,
    this.actions,
    this.pinned = true,
    this.automaticallyImplyLeading = true,
    this.onBackPressed,
    this.header,
  });

  @override
  State<FocusedScrollScaffold> createState() => _FocusedScrollScaffoldState();
}

class _FocusedScrollScaffoldState extends State<FocusedScrollScaffold> {
  final _scopeNode = FocusScopeNode();
  final _headerCollapsed = ValueNotifier<bool>(false);
  bool _focusRequested = false;

  @override
  void dispose() {
    _scopeNode.dispose();
    _headerCollapsed.dispose();
    super.dispose();
  }

  void _requestInitialFocus() {
    if (_focusRequested || !mounted || !InputModeTracker.isKeyboardMode(context)) return;
    _focusRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scopeNode.focusedChild != null) return;
      _scopeNode.requestFocus();
      _scopeNode.nextFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_focusRequested && InputModeTracker.isKeyboardMode(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestInitialFocus());
    }

    final header = widget.header;
    Widget body = ScrollCrown(
      child: CustomScrollView(
        slivers: [
          ExcludeFocus(
            child: header == null
                ? CustomAppBar(
                    title: widget.title,
                    pinned: widget.pinned,
                    actions: widget.actions,
                    automaticallyImplyLeading: widget.automaticallyImplyLeading,
                  )
                : SettingsStudioBar(
                    collapsed: _headerCollapsed,
                    title: widget.title,
                    pinned: widget.pinned,
                    actions: widget.actions,
                    automaticallyImplyLeading: widget.automaticallyImplyLeading,
                  ),
          ),
          if (header != null) SliverToBoxAdapter(child: ExcludeFocus(child: header)),
          ...widget.slivers,
        ],
      ),
    );
    if (header != null) {
      body = NotificationListener<ScrollNotification>(
        onNotification: (n) => settingsStudioTrackScroll(_headerCollapsed, n),
        child: body,
      );
    }

    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) {
        if (widget.onBackPressed != null) {
          return handleBackKeyAction(event, widget.onBackPressed!);
        }
        return handleBackKeyNavigation(context, event);
      },
      child: FocusScope(
        node: _scopeNode,
        child: IosStatusBarTapScrollToTop(child: Scaffold(body: body)),
      ),
    );
  }
}
