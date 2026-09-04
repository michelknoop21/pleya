import 'dart:ui' show VoidCallback;

import '../navigation/navigation_tabs.dart';

/// `POST /v1/open`'s only way to move the app to a nav tab: a hook
/// `MainScreen` registers under `kPleyaVerify`, calling the exact same
/// `_selectTab` its own tab bar calls — not a second, parallel navigation
/// path. Same register/unregister-by-owner shape as
/// `ProfileNavigationRegistry.attachNavigator`/`detachNavigator`.
///
/// **Unregistering compares with `==`, never with `identical`.** Every caller
/// registers and unregisters a bound instance-method tear-off (`_openFilters`
/// in `initState`, `_openFilters` again in `dispose`), and Dart builds a fresh
/// closure object for each of those: the two are `==`, because a tear-off's
/// equality is defined as same receiver and same method, but they are not
/// `identical`. An `identical` guard therefore never matches its own
/// registration, so nothing is ever removed. That is the exact semantics these
/// three methods want — "the owner that registered this is taking it back" —
/// and `==` is the operator that expresses it.
class AutomationNavigationHooks {
  AutomationNavigationHooks._();

  static final AutomationNavigationHooks instance = AutomationNavigationHooks._();

  void Function(NavigationTabId tab)? _selectTab;

  void registerSelectTab(void Function(NavigationTabId tab) selectTab) {
    _selectTab = selectTab;
  }

  void unregisterSelectTab(void Function(NavigationTabId tab) selectTab) {
    if (_selectTab == selectTab) _selectTab = null;
  }

  /// `false` when no `MainScreen` is mounted to drive — the caller (`/v1/open`)
  /// turns that into a clear error response, never a crash on a null hook.
  bool selectTab(NavigationTabId tab) {
    final hook = _selectTab;
    if (hook == null) return false;
    hook(tab);
    return true;
  }

  /// Openers for screens that are pushed routes rather than nav tabs, keyed by
  /// automation id. `Alle boeken` is the first: it hangs off Boeken-home, so
  /// `/v1/open` cannot reach it by selecting a tab, and `tap` takes
  /// coordinates only. The screen that owns the route registers the opener, so
  /// the scenario drives the same push a reader's tap does.
  final Map<String, VoidCallback> _routeOpeners = {};

  void registerRouteOpener(String screenId, VoidCallback open) => _routeOpeners[screenId] = open;

  void unregisterRouteOpener(String screenId, VoidCallback open) {
    if (_routeOpeners[screenId] == open) _routeOpeners.remove(screenId);
  }

  /// `false` when nothing has registered an opener for [screenId] — usually
  /// because the screen that owns the route is not on screen yet.
  bool openRoute(String screenId) {
    final open = _routeOpeners[screenId];
    if (open == null) return false;
    open();
    return true;
  }

  /// A hook `AuthScreen` registers under `kPleyaVerify`: the same
  /// push-`ProfileSessionScreen`-after-first-bind tail its own
  /// `_connectToPleyaServer`/`_connectToJellyfin` handlers run
  /// (`lib/screens/auth_screen.dart:182-184`), so `POST /v1/signin` drives
  /// it instead of hardcoding the real widget — a widget test exercising
  /// `handleAutomationSignIn` in isolation (no `AuthScreen` mounted, no
  /// `ProfileSessionScreen`'s full provider tree available) sees this as a
  /// harmless no-op rather than a crash on an unmountable widget.
  void Function()? _firstProfileHandoff;

  void registerFirstProfileHandoff(void Function() handoff) {
    _firstProfileHandoff = handoff;
  }

  void unregisterFirstProfileHandoff(void Function() handoff) {
    if (_firstProfileHandoff == handoff) _firstProfileHandoff = null;
  }

  /// `false` when no screen registered a handoff — `/v1/signin` still
  /// reports its own success/failure independently of this.
  bool handoffToFirstProfile() {
    final hook = _firstProfileHandoff;
    if (hook == null) return false;
    hook();
    return true;
  }
}
