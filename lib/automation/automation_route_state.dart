import 'automation_event_log.dart';

/// The answer to "where is the app right now?", as one pollable value.
///
/// Everything else the transport offers is a transition or a proxy.
/// `screen.changed` and `navigation.tab_changed` are events, so a harness that
/// asks a moment too late sees nothing and a harness that asks after a restart
/// has no history to read. `/v1/screens` reports the four `AutomationScreen`s
/// that happen to be *mounted*, which on a shell built out of an `IndexedStack`
/// is not the same question — `screen.main` is always mounted, and a hidden
/// destination's screen stays mounted behind the visible one. `/v1/ui_tree`'s
/// `nav.*` nodes carry `state: {active: true}`, which does answer it for the
/// root bar, but says nothing about what is open *inside* a destination.
///
/// A nested TV route was therefore invisible to automation: pressing SELECT on
/// a Mijn Pleya tile and pressing nothing at all produced the same observable
/// state, so "did BACK actually return to the hub?" could not be answered by
/// evidence at all. This holds the three values that do answer it, written by
/// the authorities that already own them rather than inferred.
///
/// Verify-only. Nothing in a normal build writes it — every writer is behind a
/// `kPleyaVerify` guard at the call site, in the same style as
/// `AutomationEventLog`'s.
class AutomationRouteState {
  AutomationRouteState._();

  static final AutomationRouteState instance = AutomationRouteState._();

  /// `NavigationTabId.name` of `MainScreen`'s current tab — the one field all
  /// three shells (rail, bar, mobile) share.
  String? activeTab;

  /// `TvDestinationId.name`. Null off TV.
  String? tvDestination;

  /// `TvNestedRoute.id` of whatever the active TV destination has open above
  /// its root — `tvMyPleya_watchlist`, `tvCatalog_movies`, … — or null when the
  /// destination's own root screen is showing.
  String? tvNestedRoute;

  /// Depth of the profile navigator, and the names it knows. Most routes in
  /// this app are unnamed (see [AutomationRouteObserver]), so the depth is the
  /// reliable half and the names are a bonus where they exist.
  final List<String> _navigatorStack = [];

  List<String> get navigatorStack => List.unmodifiable(_navigatorStack);

  void pushNavigatorRoute(String? name) {
    _navigatorStack.add(name ?? '<unnamed>');
  }

  void popNavigatorRoute() {
    if (_navigatorStack.isNotEmpty) _navigatorStack.removeLast();
  }

  void replaceNavigatorRoute(String? name) {
    if (_navigatorStack.isEmpty) {
      pushNavigatorRoute(name);
      return;
    }
    _navigatorStack[_navigatorStack.length - 1] = name ?? '<unnamed>';
  }

  /// Records the TV shell's position, and emits `route.changed` when it
  /// actually moved.
  ///
  /// The event exists so a scenario can `wait_until` on a navigation instead of
  /// sleeping through it; the fields exist so it can assert on where it landed.
  /// Emitting only on a real change keeps a `ChangeNotifier` that fires for
  /// unrelated reasons (a focus-ring move along the bar, say) from filling the
  /// 500-entry event ring with duplicates.
  void updateTv({required String? destination, required String? nestedRoute}) {
    if (destination == tvDestination && nestedRoute == tvNestedRoute) return;
    tvDestination = destination;
    tvNestedRoute = nestedRoute;
    AutomationEventLog.instance.emit('route.changed', {'destination': ?destination, 'nested': ?nestedRoute});
  }

  void updateTab(String? tab) {
    if (tab == activeTab) return;
    activeTab = tab;
    AutomationEventLog.instance.emit('route.changed', {'tab': ?tab});
  }

  /// Reset between runs of the same process — only the tests need it; a real
  /// app has exactly one lifetime per launch.
  void reset() {
    activeTab = null;
    tvDestination = null;
    tvNestedRoute = null;
    _navigatorStack.clear();
  }

  Map<String, Object?> toJson() => {
    'activeTab': activeTab,
    'tvDestination': tvDestination,
    'tvNestedRoute': tvNestedRoute,
    'navigatorDepth': _navigatorStack.length,
    'navigatorStack': navigatorStack,
  };
}
