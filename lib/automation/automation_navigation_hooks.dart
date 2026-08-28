import '../navigation/navigation_tabs.dart';

/// `POST /v1/open`'s only way to move the app to a nav tab: a hook
/// `MainScreen` registers under `kPleyaVerify`, calling the exact same
/// `_selectTab` its own tab bar calls — not a second, parallel navigation
/// path. Same register/unregister-by-identity shape as
/// `ProfileNavigationRegistry.attachNavigator`/`detachNavigator`.
class AutomationNavigationHooks {
  AutomationNavigationHooks._();

  static final AutomationNavigationHooks instance = AutomationNavigationHooks._();

  void Function(NavigationTabId tab)? _selectTab;

  void registerSelectTab(void Function(NavigationTabId tab) selectTab) {
    _selectTab = selectTab;
  }

  void unregisterSelectTab(void Function(NavigationTabId tab) selectTab) {
    if (identical(_selectTab, selectTab)) _selectTab = null;
  }

  /// `false` when no `MainScreen` is mounted to drive — the caller (`/v1/open`)
  /// turns that into a clear error response, never a crash on a null hook.
  bool selectTab(NavigationTabId tab) {
    final hook = _selectTab;
    if (hook == null) return false;
    hook(tab);
    return true;
  }
}
