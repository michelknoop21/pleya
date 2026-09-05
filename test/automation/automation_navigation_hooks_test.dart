import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_navigation_hooks.dart';
import 'package:pleya/navigation/navigation_tabs.dart';

/// `AutomationNavigationHooks.selectTab` in isolation, standing in for
/// `MainScreen`'s real `_selectTab`: a fake hook plays the two outcomes
/// `_selectTab` can return (selected, or rejected because the destination
/// has no slot on this platform) without mounting the app.
void main() {
  tearDown(() {
    // The hook is a singleton; a test that registers one must not leak it
    // into the next.
  });

  test('selectTab reports null when no MainScreen is mounted', () {
    expect(AutomationNavigationHooks.instance.selectTab(NavigationTabId.discover), isNull);
  });

  test('selectTab surfaces the hook\'s true result, not a blanket true', () {
    bool onlyDiscoverIsVisible(NavigationTabId tab) => tab == NavigationTabId.discover;
    AutomationNavigationHooks.instance.registerSelectTab(onlyDiscoverIsVisible);
    addTearDown(() => AutomationNavigationHooks.instance.unregisterSelectTab(onlyDiscoverIsVisible));

    expect(AutomationNavigationHooks.instance.selectTab(NavigationTabId.discover), isTrue);
  });

  test('selectTab surfaces the hook\'s false result instead of claiming success', () {
    bool onlyDiscoverIsVisible(NavigationTabId tab) => tab == NavigationTabId.discover;
    AutomationNavigationHooks.instance.registerSelectTab(onlyDiscoverIsVisible);
    addTearDown(() => AutomationNavigationHooks.instance.unregisterSelectTab(onlyDiscoverIsVisible));

    // series has no slot on this fake platform — the old implementation
    // called the hook and then returned true unconditionally.
    expect(AutomationNavigationHooks.instance.selectTab(NavigationTabId.series), isFalse);
  });

  test('unregisterSelectTab only removes the hook that registered it', () {
    bool hookA(NavigationTabId tab) => true;
    bool hookB(NavigationTabId tab) => false;
    AutomationNavigationHooks.instance.registerSelectTab(hookA);
    AutomationNavigationHooks.instance.unregisterSelectTab(hookB);

    // hookB never matched the registered identity, so hookA is still active.
    expect(AutomationNavigationHooks.instance.selectTab(NavigationTabId.discover), isTrue);
    AutomationNavigationHooks.instance.unregisterSelectTab(hookA);
    expect(AutomationNavigationHooks.instance.selectTab(NavigationTabId.discover), isNull);
  });
}
