import '../providers/watchlist_provider.dart';
import 'watchlist_screen.dart';
import 'my_pleya_screen.dart';
import 'dart:async';
import 'dart:ui' show ImageFilter;
import '../automation/automation_event_log.dart';
import '../automation/automation_route_state.dart';
import '../automation/automation_ids.dart';
import '../automation/automation_navigation_hooks.dart';
import '../automation/automation_screen.dart';
import '../automation/pleya_verify.dart';
import '../media/ids.dart';
import '../focus/focus_memory_tracker.dart';
import '../navigation/main_screen_scope.dart';
import '../services/account_ui_actions.dart';
import '../navigation/tv/tv_destination.dart';
import '../navigation/tv/tv_live_tv_capability.dart';
import '../navigation/tv/tv_content_focus_authority.dart';
import '../navigation/tv/tv_navigation_coordinator.dart';
import '../navigation/tv/tv_nested_surface.dart';
import 'tv/tv_movies_screen.dart';
import 'tv/tv_series_screen.dart';
import 'tv/tv_my_pleya_navigator.dart';
import 'tv/tv_my_pleya_screen.dart';
import 'tv/tv_my_pleya_sections.dart';
import 'tv/tv_root_shell.dart';
import '../navigation/sidebar_focus_coordinator.dart';
import '../theme/mono_theme.dart' show kAccent;
import 'dart:io' show Platform, exit;

export '../navigation/main_screen_scope.dart'
    show MainScreenFocusScope, MainScreenScopeAspect, SideNavigationBleedBuilder;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyRepeatEvent, KeyUpEvent, LogicalKeyboardKey;
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../i18n/strings.g.dart';
import '../services/app_exit_service.dart';
import '../services/tvos_system_navigation_service.dart';
import '../services/update_service.dart';
import '../utils/app_logger.dart';
import '../widgets/auth_error_banner.dart';
import '../utils/provider_extensions.dart';
import '../utils/platform_detector.dart';
import '../utils/snackbar_helper.dart';
import '../utils/update_dialog.dart';
import '../utils/video_player_navigation.dart';
import '../mixins/mounted_set_state_mixin.dart';
import '../mixins/refreshable.dart';
import '../widgets/overlay_sheet.dart';
import '../mixins/tab_visibility_aware.dart';
import '../navigation/navigation_tabs.dart';
import '../navigation/profile_navigation_scope.dart';
import '../profiles/active_profile_binder.dart';
import '../profiles/active_profile_provider.dart';
import '../profiles/plex_home_service.dart';
import '../providers/download_provider.dart';
import '../providers/multi_server_provider.dart';
import '../providers/seerr_provider.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/libraries_provider.dart';
import '../providers/playback_state_provider.dart';
import '../widgets/settings_builder.dart';
import '../widgets/tv_virtual_keyboard.dart';
import '../services/api_cache.dart';
import '../services/multi_server_manager.dart';
import '../services/offline_watch_sync_service.dart';
import '../services/settings_service.dart';
import '../services/speech_search_service.dart';
import '../providers/offline_mode_provider.dart';
import '../services/companion_remote/companion_remote_host_controller.dart';
import '../services/companion_remote/companion_remote_receiver.dart';
import '../services/fullscreen_state_manager.dart';
import '../providers/companion_remote_provider.dart';
import '../utils/desktop_window_padding.dart';
import '../widgets/side_navigation_rail.dart';
import '../focus/dpad_navigator.dart';
import '../focus/key_event_utils.dart';
import 'discover_screen.dart';
import 'libraries/library_quick_picker_sheet.dart';
import 'libraries/libraries_screen.dart';
import 'livetv/live_tv_screen.dart';
import 'search_screen.dart';
import 'seerr/seerr_discover_screen.dart';
import 'downloads/downloads_screen.dart';
import 'settings/settings_screen.dart';
import 'profile/profile_switch_screen.dart';
import 'tv/tv_movies_landing_screen.dart';
import 'tv/tv_series_landing_screen.dart';
import '../services/system_shelf_service.dart';
import '../watch_together/watch_together.dart';

/// Provides access to the main screen's focus control.
// MainScreenFocusScope and SideNavigationBleedBuilder live in
// navigation/main_screen_scope.dart (re-exported above) so widgets like the
// browse rail can import the scope without an import cycle through this file.

@visibleForTesting
({double left, double width}) mainScreenSideNavigationContentLayout({
  required double viewportWidth,
  required double currentSideNavigationWidth,
  required double reservedSideNavigationWidth,
}) {
  return (
    left: currentSideNavigationWidth,
    width: (viewportWidth - reservedSideNavigationWidth).clamp(0.0, double.infinity).toDouble(),
  );
}

@visibleForTesting
bool shouldRetryActiveProfileBindAfterReconnect({
  required bool hasActiveProfile,
  required bool hasVisibleConnectedServers,
  required bool hasManagerOnlineServers,
  required bool hasKnownOfflineServers,
}) {
  return hasActiveProfile && !hasVisibleConnectedServers && (hasManagerOnlineServers || !hasKnownOfflineServers);
}

@visibleForTesting
bool shouldRenderMainScreenOffline({
  required bool providerOffline,
  required bool startupOfflineUntilConnected,
  required bool hasVisibleConnectedServers,
}) {
  return providerOffline || (startupOfflineUntilConnected && !hasVisibleConnectedServers);
}

/// Destinations that are hidden from the mobile bottom bar because My Pleya
/// holds them instead.
///
/// Downloads is the exception offline: with Home, Libraries, Live TV, Search
/// and Requests all gone there is room for it, and it is what the user came
/// for.
const _mobileTabsInsideMyPleya = {
  NavigationTabId.watchlist,
  NavigationTabId.downloads,
  NavigationTabId.requests,
  NavigationTabId.settings,
};

@visibleForTesting
List<NavigationTab> mainScreenBottomNavigationTabs({
  required List<NavigationTab> visibleTabs,
  required bool isMobile,
  required bool isOffline,
  required NavigationTabId currentTab,
}) {
  if (!isMobile) return visibleTabs;
  return visibleTabs.where((tab) {
    if (!_mobileTabsInsideMyPleya.contains(tab.id)) return true;
    return isOffline && tab.id == NavigationTabId.downloads;
  }).toList();
}

/// Which bottom-bar destination should light up for [currentTab].
///
/// Tapping Downloads inside My Pleya makes Downloads the current tab, but on
/// mobile online Downloads has no slot in the bar. Without this projection the
/// bar's `indexWhere` returns -1, falls back to 0, and Home lights up while
/// the user is looking at their downloads.
///
/// [barTabs] is what the bar actually renders, so the answer is checked
/// against reality rather than against an assumption about which destinations
/// exist. A tab can be current while its natural target is absent: Live TV
/// without a tuner, or an online-only tab in the frame before
/// `_normalizeTabForMode` has moved the selection. In those cases the first
/// bar destination is the honest fallback, and it is the same thing the bar
/// would have shown anyway, only now deliberately.
@visibleForTesting
NavigationTabId mainScreenSelectedBarTab({
  required NavigationTabId currentTab,
  required bool isOffline,
  required List<NavigationTabId> barTabs,
}) {
  final preferred = switch (currentTab) {
    // Films and Series are TV-only and never appear in a bottom bar, so they
    // can only be `currentTab` here on a device that has no bar at all. They
    // still need a case: the mapping is exhaustive by design, and the answer
    // for a browse destination offline is Downloads, same as its neighbours.
    NavigationTabId.discover ||
    NavigationTabId.movies ||
    NavigationTabId.series ||
    NavigationTabId.libraries ||
    NavigationTabId.liveTv ||
    NavigationTabId.search => isOffline ? NavigationTabId.downloads : currentTab,
    // Offline the bar is Downloads plus My Pleya, so Downloads points at
    // itself; online it lives behind My Pleya.
    NavigationTabId.downloads => isOffline ? NavigationTabId.downloads : NavigationTabId.myPleya,
    NavigationTabId.watchlist ||
    NavigationTabId.requests ||
    NavigationTabId.settings ||
    NavigationTabId.myPleya => NavigationTabId.myPleya,
  };

  if (barTabs.contains(preferred)) return preferred;
  return barTabs.isEmpty ? currentTab : barTabs.first;
}

@visibleForTesting
bool shouldPassTvosMenuToSystem({
  required bool isAppleTV,
  required bool isShowingProfileSelection,
  required bool isOverlaySheetOpen,
  required bool isRouteCurrent,
  required bool isSidebarFocused,
  required bool hasVisibleTabs,
  required bool isCurrentTabRoot,
}) {
  return isAppleTV &&
      isSidebarFocused &&
      !isShowingProfileSelection &&
      !isOverlaySheetOpen &&
      isRouteCurrent &&
      hasVisibleTabs &&
      isCurrentTabRoot;
}

/// Which visible tab `onTabNext`/`onTabPrevious` (companion remote) should
/// move to from [currentTab], wrapping around the ends of [visibleTabs].
/// Returns `null` when [currentTab] isn't among [visibleTabs] — the caller
/// then leaves the selection untouched, matching the original inline
/// `idx >= 0` guard.
@visibleForTesting
NavigationTabId? mainScreenAdjacentTabId({
  required List<NavigationTab> visibleTabs,
  required NavigationTabId currentTab,
  required bool forward,
}) {
  final idx = visibleTabs.indexWhere((t) => t.id == currentTab);
  if (idx < 0) return null;
  final nextIdx = forward ? (idx + 1) % visibleTabs.length : (idx - 1 + visibleTabs.length) % visibleTabs.length;
  return visibleTabs[nextIdx].id;
}

@visibleForTesting
enum ProfileInvalidationAction { none, waitForProfileSwitch, invalidateNow }

@visibleForTesting
ProfileInvalidationAction profileInvalidationAction({
  required String? previousProfileId,
  required String? currentProfileId,
  required bool wasBindingPreviously,
  required bool isBindingNow,
  required bool hasPendingProfileSwitchInvalidation,
  required String? pendingProfileSwitchInvalidationId,
}) {
  if (currentProfileId != previousProfileId) {
    return ProfileInvalidationAction.waitForProfileSwitch;
  }
  if (hasPendingProfileSwitchInvalidation && pendingProfileSwitchInvalidationId == currentProfileId) {
    return ProfileInvalidationAction.none;
  }
  if (wasBindingPreviously && !isBindingNow) {
    return ProfileInvalidationAction.invalidateNow;
  }
  return ProfileInvalidationAction.none;
}

/// The distinct outcomes of a Menu/back press on the main shell, decided
/// purely from the caller's already-computed inputs — see `_handleMainBack`,
/// which reads `_lastBackPressAt`/context to build those inputs and then
/// performs the side effect (navigate home, exit, arm the snackbar, or the
/// tvOS no-op) that matches the outcome below.
@visibleForTesting
enum MainBackDecision {
  /// No tabs are visible at all (e.g. mid-teardown) — swallow the press.
  noVisibleTabs,

  /// Not on the home tab yet — Back/Menu navigates there first.
  goHome,

  /// On tvOS, already on the home tab: the engine normally passes root Menu
  /// presses through to UIKit, so a stale event reaching here should not
  /// show an exit prompt that cannot be honored app-side.
  tvMenuPassthroughStale,

  /// On the home tab, a second press landed within the exit window — exit.
  exitNow,

  /// On the home tab, first press (or the window lapsed) — arm the
  /// "press back again to exit" prompt.
  armExitPrompt,
}

/// What a Back/Menu press does on the fase-7 TV root, before the shared
/// [mainBackKeyDecision] gets a say.
///
/// Hoofdstuk 7.5 is an ordered list, and the order is the whole contract: a
/// nested Mijn Pleya route or a complete catalog closes first, *then* content
/// hands the focus to the top navigation, and only a press that finds neither
/// reaches the root. Written as a pure function because the order is what
/// breaks, and it breaks silently — a shell that checked the focus first would
/// send someone standing in Bibliotheken to the bar instead of back to the hub,
/// and nothing would throw.
@visibleForTesting
enum TvBackStep {
  /// Step 2: something is open inside the active destination. Close it.
  popNested,

  /// Step 4: root content holds the focus. Move it to the top navigation.
  focusTopNavigation,

  /// Step 5: the top navigation holds the focus at the root. Hand over to the
  /// shared decision, which is where the tvOS system contract lives.
  rootContract,
}

@visibleForTesting
TvBackStep tvBackStep({required bool hasNestedRoute, required bool isNavigationFocused}) {
  // Deliberately ahead of the focus test: Back inside a nested route means
  // "leave this route" whether the remote is still on a card or has already
  // walked up to the bar.
  if (hasNestedRoute) return TvBackStep.popNested;
  return isNavigationFocused ? TvBackStep.rootContract : TvBackStep.focusTopNavigation;
}

@visibleForTesting
MainBackDecision mainBackKeyDecision({
  required bool hasVisibleTabs,
  required bool isAtHomeTab,
  required bool isAppleTV,
  required bool hasRecentBackPress,
}) {
  if (!hasVisibleTabs) return MainBackDecision.noVisibleTabs;
  if (!isAtHomeTab) return MainBackDecision.goHome;
  if (isAppleTV) return MainBackDecision.tvMenuPassthroughStale;
  if (hasRecentBackPress) return MainBackDecision.exitNow;
  return MainBackDecision.armExitPrompt;
}

/// The destination stack every shell hosts: one child painted, the rest laid
/// out behind it, and — the part that is not free — none of the rest reachable.
///
/// `IndexedStack` keeps its offscreen children mounted, which is the whole
/// reason it is used: a destination switch must not cost a rebuild of a
/// provider graph, a scroll position or a set of focus nodes (hoofdstuk 24).
/// What it does *not* do is take them out of the focus tree. `TickerMode`
/// silences their animations and nothing silenced their focusables, so the app
/// held a complete second copy of every destination — its cards, its chips, its
/// retry buttons — all focusable, all invisible, in the same scope as the one on
/// screen. A programmatic focus or one traversal step could land on any of them,
/// and the remote then moved something nobody could see (P5). Eleven other
/// places in this repo already pair the two; this was the one that did not.
///
/// Top-level and `@visibleForTesting` so the guard can be driven as the
/// production composition rather than as a copy of it — the same reason
/// [mainScreenSideNavigationContentLayout] is.
@visibleForTesting
Widget mainScreenDestinationStack({required List<Widget> screens, required int currentIndex}) {
  return IndexedStack(
    index: currentIndex,
    clipBehavior: Clip.none,
    children: [
      for (var i = 0; i < screens.length; i++)
        ExcludeFocus(
          excluding: i != currentIndex,
          child: TickerMode(enabled: i == currentIndex, child: screens[i]),
        ),
    ],
  );
}

class MainScreen extends StatefulWidget {
  final bool isOfflineMode;

  /// When `true`, the previous screen (typically [SetupScreen]) already
  /// resolved the launch profile prompt — skip the postFrame prompt that
  /// would otherwise re-fire it.
  final bool initialPromptHandled;

  const MainScreen({super.key, this.isOfflineMode = false, this.initialPromptHandled = false});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with RouteAware, WindowListener, WidgetsBindingObserver, MountedSetStateMixin {
  NavigationTabId _currentTab = NavigationTabId.discover;
  String? _selectedLibraryGlobalKey;

  /// Whether the app is in offline mode (no server connection)
  bool _isOffline = false;

  /// Computed index — searches the same _getVisibleTabs() that _buildScreens iterates,
  /// so _screens[_currentIndex] is always the widget for _currentTab.
  int get _currentIndex {
    final tabs = _getVisibleTabs(_isOffline);
    final idx = tabs.indexWhere((t) => t.id == _currentTab);
    return (idx >= 0 ? idx : 0).clamp(0, _screens.length - 1);
  }

  /// Last selected online tab (restored when coming back online after an offline fallback)
  NavigationTabId? _lastOnlineTabId;

  /// A preferred startup section (e.g. Live TV) that wasn't visible yet at cold
  /// start because servers bind asynchronously. Applied once it becomes
  /// available (see [_handleLiveTvChanged]); cleared on any explicit selection.
  NavigationTabId? _pendingStartupTab;

  /// Whether we auto-switched to Downloads because the previous tab was unavailable offline
  bool _autoSwitchedToDownloads = false;

  OfflineModeProvider? _offlineModeProvider;
  MultiServerProvider? _multiServerProvider;
  SeerrProvider? _seerrProvider;
  WatchlistProvider? _watchlistProvider;
  RouteObserver<PageRoute<dynamic>>? _profileRouteObserver;
  bool _lastHasLiveTv = false;
  bool _lastHasSeerr = false;
  bool _lastHasWatchlist = false;

  /// Whether a reconnection attempt is in progress
  bool _isReconnecting = false;

  /// Startup routed here explicitly offline. Keep the offline shell until a
  /// visible server actually connects; provider warmup can be optimistic when
  /// failed Plex servers have no live client yet.
  bool _offlineUntilConnected = false;

  /// Prevents double-pushing the profile selection screen
  bool _isShowingProfileSelection = false;

  late List<Widget> _screens;
  final GlobalKey<State<DiscoverScreen>> _discoverKey = GlobalKey();
  // Plain keys: both are stateless wrappers over the shared catalog screen, so
  // there is no state to reach into — the key only keeps each page's element
  // identity stable across a tab switch.
  final GlobalKey _moviesKey = GlobalKey();
  final GlobalKey _seriesKey = GlobalKey();
  final GlobalKey<State<LibrariesScreen>> _librariesKey = GlobalKey();
  final GlobalKey<State<LiveTvScreen>> _liveTvKey = GlobalKey();
  final GlobalKey<State<SearchScreen>> _searchKey = GlobalKey();
  final GlobalKey<State<DownloadsScreen>> _downloadsKey = GlobalKey();
  final GlobalKey<State<SettingsScreen>> _settingsKey = GlobalKey();
  final GlobalKey<State<WatchlistScreen>> _watchlistKey = GlobalKey();
  final GlobalKey _myPleyaKey = GlobalKey();
  final GlobalKey<SideNavigationRailState> _sideNavKey = GlobalKey();

  /// Fase 7's TV root. Created once and never rebuilt away, for the same reason
  /// [_focus] is: it holds the active destination and the per-destination focus
  /// memory, and a shell that recreated it would forget where the viewer was
  /// every time a server came online.
  final TvNavigationCoordinator _tvNav = TvNavigationCoordinator();

  /// The one thing on this shell allowed to say "the remote belongs in the
  /// content now" (P2). See [TvContentFocusAuthority] for the three paths this
  /// replaces and the contract it keeps.
  final TvContentFocusAuthority _tvContentFocus = TvContentFocusAuthority();

  /// The bar's focus nodes. Owned here rather than by [TvTopNavigation] so a
  /// rebuild of the bar cannot dispose the node the remote is standing on —
  /// the same ownership rule the rail follows.
  final FocusMemoryTracker _tvNavNodes = FocusMemoryTracker(debugLabelPrefix: 'tvNav');

  final GlobalKey<TvMyPleyaScreenState> _tvMyPleyaKey = GlobalKey();

  /// Reaches the `WatchlistScreen` inside Mijn Pleya ▸ Kijklijst.
  ///
  /// A *second* key beside [_watchlistKey], not a reuse of it, for the same
  /// reason [_tvLibrariesKey] is: the screens list still builds its own
  /// `WatchlistScreen` behind the `IndexedStack`, and one `GlobalKey` cannot be
  /// on two mounted widgets. The offstage one is the copy `ExcludeFocus` in
  /// [_buildTickerAwareStack] now keeps out of the focus tree (P5).
  final GlobalKey<State<WatchlistScreen>> _tvWatchlistKey = GlobalKey();

  /// Reaches the `LibrariesScreen` inside Mijn Pleya ▸ Bibliotheken, so the
  /// hoofdstuk 6.4 adapter can call the same `loadLibraryByKey` the rail's
  /// library rows have always called.
  final GlobalKey<State<LibrariesScreen>> _tvLibrariesKey = GlobalKey();

  /// The remembered Live TV capability for this profile. See
  /// [TvLiveTvCapabilityStore] for why a poll may not clear it.
  bool _tvLiveTvRemembered = false;

  /// Whether this session draws the fase-7 TV shell. A single predicate rather
  /// than scattered `isTV()` calls, so the shell, the focus chain, the back
  /// chain and the screens list cannot end up disagreeing about which root is
  /// on screen.
  bool get _isTvShell => PlatformDetector.isTV();

  TvMyPleyaScreenState? get _tvMyPleya => _tvMyPleyaKey.currentState;

  // Focus management for sidebar/content switching
  final SidebarFocusCoordinator _focus = SidebarFocusCoordinator();

  FocusScopeNode get _sidebarFocusScope => _focus.sidebarScope;
  FocusScopeNode get _contentFocusScope => _focus.contentScope;
  bool get _isSidebarFocused => _focus.isSidebarFocused;
  bool _isSidebarInteractionExpanded = false;
  bool _isOverlaySheetOpen = false;

  /// The binder is now owned by a top-level [Provider] (see main.dart) so
  /// the splash can await its first settle before navigating here. We just
  /// observe its [ActiveProfileProvider.isBinding] state for the once-only
  /// priming below.
  PlexHomeService? _plexHomeService;
  ActiveProfileProvider? _activeProfileForListener;
  String? _lastSeenProfileId;
  // Tracks ActiveProfileProvider.isBinding from the previous notification
  // so we can detect a binding-just-settled transition for the *same*
  // active profile id (e.g. after a borrow/remove rebind). Without this
  // we only invalidate on id change and the libraries sidebar keeps
  // stale entries until the user switches profiles.
  bool _wasBindingPrev = false;
  bool _hasPendingProfileSwitchInvalidation = false;
  String? _pendingProfileSwitchInvalidationId;

  /// Subscription to MultiServerManager status changes. Used to resume any
  /// queued downloads as soon as a Plex client comes online for the first
  /// time after launch (legacy main.dart used to do this from SetupScreen
  /// before navigating).
  StreamSubscription<Map<String, bool>>? _serverStatusSub;
  bool _downloadResumeFired = false;

  /// Listener that fires when [ActiveProfileBinder] settles (Plex *and*
  /// Jellyfin both bound). Drives the once-per-launch priming of
  /// LibrariesProvider + watch sync + tab fullRefresh — wiring this off
  /// the first online-server emission instead would prime before
  /// Jellyfin gets added, leaving its libraries out of the navbar.
  VoidCallback? _bindingSettleListener;
  bool _startupServicesPrimed = false;
  Timer? _startupSettleTimeout;

  /// Hard ceiling on how long we wait for [ActiveProfileBinder] to settle
  /// before priming the UI anyway. The binder always calls
  /// `markBindingFinished` in its `finally`, but this is a defence in depth:
  /// if a transient bug or hung HTTP path keeps `isBinding` true, the user
  /// would otherwise see an empty Discover screen forever. After the
  /// fallback fires the screens render their normal "no servers" state and
  /// the user can pull-to-refresh / open settings.
  static const _startupSettleFallback = Duration(seconds: 15);
  static const _backExitWindow = Duration(seconds: 3);
  DateTime? _lastBackPressAt;

  StreamSubscription<String>? _externalSearchSubscription;

  @override
  void initState() {
    super.initState();
    _isOffline = widget.isOfflineMode;
    _offlineUntilConnected = widget.isOfflineMode;

    WidgetsBinding.instance.addObserver(this);
    _focus.addListener(_handleSidebarFocusChanged);
    _listenForExternalSearchQueries();

    if (PlatformDetector.isDesktopOS()) {
      windowManager.addListener(this);
      windowManager.setPreventClose(true);
    }

    // Synchronize _lastHasLiveTv with provider before building screens
    // so _buildScreens and _hasLiveTv getter agree from the start.
    try {
      _lastHasLiveTv = context.read<MultiServerProvider>().hasLiveTv;
    } catch (_) {
      _lastHasLiveTv = false;
    }
    try {
      _lastHasSeerr = context.read<SeerrProvider>().isConfigured;
    } catch (_) {
      _lastHasSeerr = false;
    }
    try {
      _lastHasWatchlist = context.read<WatchlistProvider>().hasWatchlist;
    } catch (_) {
      _lastHasWatchlist = false;
    }
    _currentTab = _defaultTabForMode(_isOffline);
    // Fase 7: seed the bar before the first frame, then load the remembered
    // Live TV capability. Reading it is async, so the bar opens on what the
    // live poll knows and gains the remembered slot a moment later — the one
    // direction that cannot hide a destination someone was aiming at.
    if (_isTvShell) {
      _tvNav.syncToTab(_currentTab);
      _syncTvDestinations();
      unawaited(_loadTvLiveTvCapability());
      // A cold start lands on the bar, with the startup destination lit — the
      // same place a destination switch leaves the remote (P2).
      //
      // There was no initial focus request on TV at all before this. The remote
      // ended up wherever `DiscoverScreen`'s initial-load post-frame put it,
      // and that path is now allowed to move focus only against an armed
      // intent — so without this the first frame would have no primary focus,
      // which on tvOS is not "nothing highlighted" but "the D-pad does
      // nothing": the engine claims every press before UIKit sees it (see
      // CLAUDE.md's engine-swizzle gotcha), and a tree with no focused node
      // swallows them.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusSidebar();
      });
    }
    _lastOnlineTabId = _isOffline ? null : NavigationTabId.discover;
    _autoSwitchedToDownloads = _isOffline && _currentTab == NavigationTabId.downloads;
    // If the preferred startup section isn't visible yet (e.g. Live TV before
    // servers finish binding), remember it and switch once it becomes available.
    final preferredStartup = SettingsService.instanceOrNull?.read(SettingsService.startupSection);
    _pendingStartupTab = (!_isOffline && preferredStartup != null && preferredStartup != _currentTab)
        ? preferredStartup
        : null;
    _screens = _buildScreens(_isOffline);

    if (kPleyaVerify) {
      AutomationNavigationHooks.instance.registerSelectTab(_selectTab);
    }

    // Warm the TV keyboard's text-layout caches off the first real open
    // (measured ~315ms first-open frame on low-end boxes, mostly cold font
    // shaping). Delayed past the startup burst; no-op off TV.
    if (PlatformDetector.isTV()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) warmUpTvVirtualKeyboardText(context);
        });
      });
    }

    // Set up Watch Together callbacks immediately (must be synchronous to catch early messages)
    if (!_isOffline) {
      _setupWatchTogetherCallback();
      _setupSystemShelfDeepLink();
    }

    // Wire profile binder + tracker bootstrap (skip in offline mode)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final activeProfile = context.read<ActiveProfileProvider>();
      _activeProfileForListener = activeProfile;
      _lastSeenProfileId = activeProfile.activeId;
      activeProfile.addListener(_onActiveProfileChanged);
      _plexHomeService = context.read<PlexHomeService>();
      unawaited(_plexHomeService!.start());
      final manager = context.read<MultiServerProvider>().serverManager;
      // Read the binder so the Provider's `lazy: false` create has fired
      // for sure; start only in online mode so explicit startup offline does
      // not immediately kick off the same connection attempts it skipped.
      final binder = context.read<ActiveProfileBinder>();
      if (!_isOffline) binder.start();
      _runStartupOnFirstOnlineServer(manager);

      if (!_isOffline) {
        // Settings-only initialization — profile identity is managed by
        // ActiveProfileProvider + ActiveProfileBinder.
        final userProfileProvider = context.userProfile;
        await userProfileProvider.initialize();
        if (!mounted) return;

        // Ensure first login (or any unset profile state) requires explicit selection.
        await _promptForInitialProfileSelection();
        if (!mounted) return;

        // Auto-start companion remote server once the active profile is known.
        if (_companionRemoteSetup) {
          unawaited(_autoStartCompanionRemoteServer());
        }
      }

      // Focus content initially (replaces autofocus which caused focus stealing issues)
      // Skip if profile selection is on top — it manages its own focus.
      if (!_isSidebarFocused && !_isShowingProfileSelection) {
        _contentFocusScope.requestFocus();
      }

      _updateTvosMenuPassthrough();

      // Check for updates on startup
      unawaited(_checkForUpdatesOnStartup());
    });
  }

  /// Run startup tasks that depend on having at least one online server:
  /// initialize and load the libraries provider, kick off the initial
  /// watch-state sync, and (for Plex) resume any queued downloads. The
  /// legacy [SetupScreen] path used to do all this before navigating to
  /// MainScreen; with the binder taking over for the connect, we hook
  /// into [ActiveProfileProvider.isBinding] (for the once-only priming,
  /// which must wait for *all* connections — Plex *and* Jellyfin — to
  /// land so the navbar shows libraries from both backends) and
  /// [MultiServerManager.statusStream] (for download resume, which only
  /// cares about the first online Plex client). Fires at most once per
  /// MainScreen lifetime.
  void _runStartupOnFirstOnlineServer(MultiServerManager manager) {
    if (_isOffline || _downloadResumeFired) return;

    final activeProfile = context.read<ActiveProfileProvider>();

    void primeServicesOnBindingSettle({bool fromTimeout = false}) {
      if (_startupServicesPrimed || !mounted) return;
      // Wait for the binder to finish — `_rebind` only flips `isBinding`
      // false after both `_bindPlexHome` AND `_bindJoinRows` (where
      // Jellyfin gets added) complete. Priming on the first Plex status
      // emit instead would load libraries before Jellyfin is registered.
      //
      // The `fromTimeout` escape hatch lets the [_startupSettleTimeout]
      // bypass this gate if the binder has somehow not flipped the flag
      // within [_startupSettleFallback]. Logs a warning so the silent
      // path is still surfaced in diagnostics.
      if (activeProfile.isBinding && !fromTimeout) return;
      if (fromTimeout) {
        appLogger.w(
          'ActiveProfileBinder still binding after ${_startupSettleFallback.inSeconds}s '
          '— priming UI anyway so the user is not stuck on an empty screen.',
        );
      }
      // Set the guard before the await so re-entrant listener fires can't
      // race a second prime.
      _startupServicesPrimed = true;
      _startupSettleTimeout?.cancel();
      _startupSettleTimeout = null;

      unawaited(_primeOnlineServices(manager));
    }

    void tryDownloadResume() {
      if (_downloadResumeFired || !mounted) return;
      // Wait for any online client before firing the resume — the download
      // pipeline is backend-neutral (resumeQueuedDownloads accepts a
      // MediaServerClient and per-item resolution picks up the right
      // backend), so a Jellyfin-only setup can resume too.
      final onlineClient = manager.onlineClients.values.firstOrNull;
      if (onlineClient == null) return;
      _downloadResumeFired = true;
      _serverStatusSub?.cancel();
      _serverStatusSub = null;
      final downloadProvider = context.read<DownloadProvider>();
      unawaited(
        downloadProvider.ensureInitialized().then((_) {
          if (!mounted) return;
          downloadProvider.resumeQueuedDownloads(onlineClient);
        }),
      );
    }

    // Listen for binding-settle so the once-only priming runs after both
    // Plex and Jellyfin are wired up.
    _bindingSettleListener = () => primeServicesOnBindingSettle();
    activeProfile.addListener(_bindingSettleListener!);

    // Defence in depth: bypass the binder gate after a hard ceiling so a
    // hung bind path can't strand the user on an empty screen.
    _startupSettleTimeout?.cancel();
    _startupSettleTimeout = Timer(_startupSettleFallback, () {
      primeServicesOnBindingSettle(fromTimeout: true);
    });

    // Fast paths: binder may have already settled / first Plex server may
    // already be online (binder finished before this microtask).
    primeServicesOnBindingSettle();
    tryDownloadResume();
    if (_downloadResumeFired) return;

    _serverStatusSub = manager.statusStream.listen((_) => tryDownloadResume());
  }

  /// Shared online-entry hook for cold startup and reconnect-from-offline.
  /// It mirrors `_invalidateAllScreens`: libraries load before tab refreshes
  /// so screens don't initialize against an empty provider and remain blank.
  Future<void> _primeOnlineServices(MultiServerManager manager) async {
    if (manager.onlineServerIds.isNotEmpty) {
      if (!mounted) return;
      final mp = context.read<MultiServerProvider>();
      if (mp.hasConnectedServers) {
        final lp = context.read<LibrariesProvider>();
        lp.initialize(mp.aggregationService);
        await lp.loadLibraries();
        if (!mounted) return;
        context.read<OfflineWatchSyncService>().onServersConnected();
        unawaited(context.read<DownloadProvider>().refreshMetadataFromCache());
        _resumeQueuedDownloadsIfPossible(mp);
      }
    }

    if (!mounted) return;
    if (_discoverKey.currentState case final FullRefreshable refreshable) {
      refreshable.fullRefresh();
    }
    if (_librariesKey.currentState case final FullRefreshable refreshable) {
      refreshable.fullRefresh();
    }
    if (_searchKey.currentState case final FullRefreshable refreshable) {
      refreshable.fullRefresh();
    }
  }

  void _resumeQueuedDownloadsIfPossible(MultiServerProvider mp) {
    if (_downloadResumeFired || !mounted) return;
    for (final serverId in mp.onlineServerIds) {
      final onlineClient = mp.getClientForServer(ServerId(serverId));
      if (onlineClient == null) continue;
      _downloadResumeFired = true;
      unawaited(
        context.read<DownloadProvider>().ensureInitialized().then((_) {
          if (!mounted) return;
          context.read<DownloadProvider>().resumeQueuedDownloads(onlineClient);
        }),
      );
      return;
    }
  }

  void _onActiveProfileChanged() {
    final activeProfile = _activeProfileForListener;
    if (activeProfile == null) return;
    final id = activeProfile.activeId;
    final isBindingNow = activeProfile.isBinding;
    final action = profileInvalidationAction(
      previousProfileId: _lastSeenProfileId,
      currentProfileId: id,
      wasBindingPreviously: _wasBindingPrev,
      isBindingNow: isBindingNow,
      hasPendingProfileSwitchInvalidation: _hasPendingProfileSwitchInvalidation,
      pendingProfileSwitchInvalidationId: _pendingProfileSwitchInvalidationId,
    );

    if (action == ProfileInvalidationAction.waitForProfileSwitch) {
      _lastSeenProfileId = id;
      _wasBindingPrev = isBindingNow;
      _hasPendingProfileSwitchInvalidation = true;
      _pendingProfileSwitchInvalidationId = id;
      // We're called inside the synchronous notify cascade *before* the
      // binder's listener has fired (registration order). At this exact
      // instant `_isBinding` is still false, so calling awaitBindingSettle
      // here would resolve immediately. Hop to a microtask so the binder's
      // listener gets to flip the flag first, then wait properly.
      unawaited(
        Future.microtask(() async {
          final scheduledProfileId = id;
          if (!mounted) return;
          await activeProfile.awaitBindingSettle();
          if (!mounted) return;
          try {
            if (_hasPendingProfileSwitchInvalidation &&
                _pendingProfileSwitchInvalidationId == scheduledProfileId &&
                activeProfile.activeId == scheduledProfileId) {
              await _invalidateAllScreens();
            }
          } finally {
            if (_hasPendingProfileSwitchInvalidation && _pendingProfileSwitchInvalidationId == scheduledProfileId) {
              _hasPendingProfileSwitchInvalidation = false;
              _pendingProfileSwitchInvalidationId = null;
            }
          }
        }),
      );
      return;
    }

    // Same active id, but a rebind cycle for that profile just settled
    // (true → false transition). Fires after borrow / connection-removal
    // flows trigger ActiveProfileBinder.rebindIfActive, so the libraries
    // sidebar reflects the new server set without an app restart.
    if (action == ProfileInvalidationAction.invalidateNow) {
      _wasBindingPrev = isBindingNow;
      unawaited(_invalidateAllScreens());
      return;
    }
    _wasBindingPrev = isBindingNow;
  }

  Future<void> _promptForInitialProfileSelection() async {
    if (!mounted || _isShowingProfileSelection) return;
    if (widget.initialPromptHandled) return;

    final activeProfile = context.read<ActiveProfileProvider>();
    // The provider's initialize() is fire-and-forget from MultiProvider —
    // wait for it to settle so `active` and `profiles` reflect storage
    // before we decide whether to prompt.
    await activeProfile.initialize();
    if (!mounted) return;

    final settingsService = await SettingsService.getInstance();
    if (!mounted) return;

    // Always prompt when there's no active profile but profiles exist
    // (fresh sign-in with multiple Plex Home users): otherwise the binder
    // has no profile to bind, and the user lands on an empty screen with
    // no way back to the picker.
    final hasNoActive = activeProfile.active == null && activeProfile.profiles.isNotEmpty;
    final requireOnOpen =
        settingsService.read(SettingsService.requireProfileSelectionOnOpen) && activeProfile.hasMultipleProfiles;

    if (!hasNoActive && !requireOnOpen) return;

    _isShowingProfileSelection = true;
    _setTvosMenuPassthrough(false);
    await Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (context) => const ProfileSwitchScreen(requireSelection: true)));
    if (!mounted) return;
    _isShowingProfileSelection = false;
    _updateTvosMenuPassthrough();
  }

  Future<void> _checkForUpdatesOnStartup() async {
    if (!mounted) return;

    final settingsService = await SettingsService.getInstance();
    if (!settingsService.read(SettingsService.autoCheckUpdatesOnStartup)) return;

    // Native updater (Sparkle/WinSparkle) handles everything — skip Flutter dialog
    if (UpdateService.useNativeUpdater) {
      await UpdateService.checkForUpdatesNative(inBackground: true);
      return;
    }

    try {
      final updateInfo = await UpdateService.checkForUpdatesOnStartup();

      if (updateInfo != null && updateInfo['hasUpdate'] == true && mounted) {
        await _showUpdateDialog(updateInfo);
      }
    } catch (e) {
      appLogger.e('Error checking for updates', error: e);
    }
  }

  Future<void> _showUpdateDialog(Map<String, dynamic> updateInfo) => showUpdateAvailableDialog(
    context,
    updateInfo,
    title: t.update.available,
    dismissLabel: t.common.later,
    showSkipVersion: true,
  );

  /// Set up the Watch Together navigation callback for guests
  void _setupWatchTogetherCallback() {
    try {
      final watchTogether = context.read<WatchTogetherProvider>();
      watchTogether.onMediaSwitched = (ratingKey, serverId, mediaTitle) async {
        appLogger.d('WatchTogether: Media switch received - navigating to $mediaTitle');
        await _navigateToWatchTogetherMedia(ratingKey, serverId);
      };
      watchTogether.onHostExitedPlayer = () {
        appLogger.d('WatchTogether: Host exited player - exiting player for guest');
        // Watch Together playback lives in the profile navigator; root-level
        // dialogs/profile picker must not be affected.
        if (!mounted) return;
        final navigator = Navigator.of(context);
        bool isVideoPlayerOnTop = false;
        navigator.popUntil((route) {
          if (route.isCurrent) {
            isVideoPlayerOnTop = route.settings.name == kVideoPlayerRouteName;
          }
          return true;
        });
        if (isVideoPlayerOnTop && navigator.canPop()) {
          navigator.pop();
        }
      };
    } catch (e) {
      appLogger.w('Could not set up Watch Together callback', error: e);
    }
  }

  /// Set up launcher shelf deep link handling for Android TV and tvOS taps.
  void _setupSystemShelfDeepLink() {
    if (!Platform.isAndroid && !PlatformDetector.isAppleTV()) return;

    final systemShelf = SystemShelfService();

    // Listen for deep links when app is already running (warm start)
    systemShelf.onShelfItemTap = (contentId) {
      appLogger.d('System shelf tap: $contentId');
      _handleShelfContentId(contentId);
    };

    // Check for pending deep link from cold start
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final contentId = await systemShelf.getInitialDeepLink();
      if (contentId != null && mounted) {
        appLogger.d('System shelf initial deep link: $contentId');
        unawaited(_handleShelfContentId(contentId));
      }
    });
  }

  /// Handle a launcher shelf content ID by fetching metadata and starting playback.
  Future<void> _handleShelfContentId(String contentId) async {
    if (!mounted) return;

    final parsed = SystemShelfService.parseContentId(contentId);
    if (parsed == null) {
      appLogger.w('System shelf: invalid content ID: $contentId');
      return;
    }

    final (serverId, ratingKey) = parsed;

    try {
      final multiServer = context.read<MultiServerProvider>();
      final client = multiServer.getClientForServer(serverId);

      if (client == null) {
        appLogger.w('System shelf: server $serverId not available');
        return;
      }

      final metadata = await client.fetchItem(ratingKey);

      if (metadata == null || !mounted) return;

      unawaited(navigateToVideoPlayer(context, metadata: metadata));
    } catch (e) {
      appLogger.e('System shelf: failed to navigate to media', error: e);
    }
  }

  /// Navigate to media when host switches content in Watch Together session
  Future<void> _navigateToWatchTogetherMedia(String ratingKey, ServerId serverId) async {
    if (!mounted) return; // Check before any context usage

    try {
      await navigateToWatchTogetherPlayback(context, ratingKey: ratingKey, serverId: serverId);
    } catch (e) {
      appLogger.e('WatchTogether: Failed to navigate to media', error: e);
    }
  }

  bool _companionRemoteSetup = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Listen for offline/online transitions to refresh navigation & screens.
    // If the provider already observed a failed bind before this listener
    // attached, mirror that missed state after build.
    final provider = context.read<OfflineModeProvider?>();
    if (provider != null && provider != _offlineModeProvider) {
      _offlineModeProvider?.removeListener(_handleOfflineStatusChanged);
      _offlineModeProvider = provider;
      _offlineModeProvider!.addListener(_handleOfflineStatusChanged);
      if (!widget.isOfflineMode && !_isOffline && provider.isOffline) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _handleOfflineStatusChanged();
        });
      }
    }

    // Listen for Live TV / DVR availability changes
    final multiServer = context.read<MultiServerProvider>();
    if (multiServer != _multiServerProvider) {
      _multiServerProvider?.removeListener(_handleLiveTvChanged);
      _multiServerProvider = multiServer;
      _multiServerProvider!.addListener(_handleLiveTvChanged);
    }

    // Listen for the Jellyseerr/Overseerr session appearing/disappearing so the
    // Requests tab shows up (or hides) live.
    final seerr = context.read<SeerrProvider>();
    if (seerr != _seerrProvider) {
      _seerrProvider?.removeListener(_handleSeerrChanged);
      _watchlistProvider?.removeListener(_handleWatchlistChanged);
      _seerrProvider = seerr;
      _seerrProvider!.addListener(_handleSeerrChanged);
    }

    // Same for the kijklijst: its sources resolve asynchronously after a
    // profile bind, so the Watchlist destination appears once there is one.
    final watchlist = context.read<WatchlistProvider>();
    if (watchlist != _watchlistProvider) {
      _watchlistProvider?.removeListener(_handleWatchlistChanged);
      _watchlistProvider = watchlist;
      _watchlistProvider!.addListener(_handleWatchlistChanged);
    }

    // Wire up Companion Remote command routing (host devices only, once)
    if (!_companionRemoteSetup && PlatformDetector.shouldActAsRemoteHost(context)) {
      _companionRemoteSetup = true;
      _setupCompanionRemote();
    }

    final scopedRouteObserver = ProfileNavigationScope.of(context).routeObserver;
    if (scopedRouteObserver != _profileRouteObserver) {
      _profileRouteObserver?.unsubscribe(this);
      _profileRouteObserver = scopedRouteObserver;
      final route = ModalRoute.of(context);
      if (route is PageRoute<dynamic>) {
        scopedRouteObserver.subscribe(this, route);
      }
    }
  }

  void _setupCompanionRemote() {
    final companionRemote = context.read<CompanionRemoteProvider>();
    companionRemote.onCommandReceived = (command) {
      if (mounted) {
        CompanionRemoteReceiver.instance.handleCommand(command, context);
      }
    };

    final receiver = CompanionRemoteReceiver.instance;

    receiver.onTabNext = () {
      final next = mainScreenAdjacentTabId(
        visibleTabs: _getVisibleTabs(_isOffline),
        currentTab: _currentTab,
        forward: true,
      );
      if (next != null) _selectTab(next);
    };
    receiver.onTabPrevious = () {
      final previous = mainScreenAdjacentTabId(
        visibleTabs: _getVisibleTabs(_isOffline),
        currentTab: _currentTab,
        forward: false,
      );
      if (previous != null) _selectTab(previous);
    };
    receiver.onTabDiscover = () => _selectTab(NavigationTabId.discover);
    receiver.onTabLibraries = () => _selectTab(NavigationTabId.libraries);
    receiver.onTabSearch = () => _selectTab(NavigationTabId.search);
    receiver.onTabDownloads = () => _selectTab(NavigationTabId.downloads);
    receiver.onTabSettings = () => _selectTab(NavigationTabId.settings);
    receiver.onHome = () => _selectTab(NavigationTabId.discover);
    receiver.onSearchAction = _openSearchWithQuery;
  }

  /// Open the search tab and, when a finished query came with it (companion
  /// remote, Assistant voice search), run it straight away.
  void _openSearchWithQuery(String? query) {
    _selectTab(NavigationTabId.search);
    if (query == null || query.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_searchKey.currentState case final SearchInputFocusable searchable) {
        searchable.submitSearchQuery(query);
      }
    });
  }

  /// Android Assistant / TV global search ("search X in Pleya").
  void _listenForExternalSearchQueries() {
    unawaited(SpeechSearchService.instance.startListeningForSearchIntents());
    _externalSearchSubscription = SpeechSearchService.instance.externalQueries.listen((query) {
      if (mounted) _openSearchWithQuery(query);
    });
  }

  Future<void> _autoStartCompanionRemoteServer() async {
    try {
      final settings = await SettingsService.getInstance();
      if (!settings.read(SettingsService.enableCompanionRemoteServer)) return;
      if (!mounted) return;
      await startCompanionRemoteHost(context);
    } catch (e) {
      appLogger.e('CompanionRemote: Failed to auto-start server', error: e);
    }
  }

  @override
  void dispose() {
    if (kPleyaVerify) {
      AutomationNavigationHooks.instance.unregisterSelectTab(_selectTab);
    }
    WidgetsBinding.instance.removeObserver(this);
    _profileRouteObserver?.unsubscribe(this);
    if (PlatformDetector.isDesktopOS()) {
      windowManager.removeListener(this);
      windowManager.setPreventClose(false);
    }
    _offlineModeProvider?.removeListener(_handleOfflineStatusChanged);
    _multiServerProvider?.removeListener(_handleLiveTvChanged);
    _seerrProvider?.removeListener(_handleSeerrChanged);
    if (_bindingSettleListener != null) {
      _activeProfileForListener?.removeListener(_bindingSettleListener!);
    }
    _activeProfileForListener?.removeListener(_onActiveProfileChanged);
    _serverStatusSub?.cancel();
    _startupSettleTimeout?.cancel();
    _startupSettleTimeout = null;
    _focus.removeListener(_handleSidebarFocusChanged);
    _focus.dispose();
    _tvNav.dispose();
    _tvNavNodes.dispose();
    _setTvosMenuPassthrough(false);

    // Clean up companion remote callbacks
    if (_companionRemoteSetup) {
      final receiver = CompanionRemoteReceiver.instance;
      receiver.onTabNext = null;
      receiver.onTabPrevious = null;
      receiver.onTabDiscover = null;
      receiver.onTabLibraries = null;
      receiver.onTabSearch = null;
      receiver.onTabDownloads = null;
      receiver.onTabSettings = null;
      receiver.onHome = null;
      receiver.onSearchAction = null;
    }
    unawaited(_externalSearchSubscription?.cancel());

    super.dispose();
  }

  @override
  void onWindowClose() {
    exit(0);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isOffline && !_isShowingProfileSelection) {
      // Only show profile selection on resume for mobile platforms.
      // On desktop, "resumed" fires on every window focus gain (alt-tab, click),
      // which is too frequent — the initial prompt on startup is sufficient.
      if (Platform.isAndroid || Platform.isIOS) {
        _showProfileSelectionOnResume();
      }
    }
  }

  Future<void> _showProfileSelectionOnResume() async {
    final settingsService = await SettingsService.getInstance();
    if (!settingsService.read(SettingsService.requireProfileSelectionOnOpen)) return;
    if (!mounted) return;

    final activeProfile = context.read<ActiveProfileProvider>();
    if (!activeProfile.hasMultipleProfiles) return;

    _isShowingProfileSelection = true;
    _setTvosMenuPassthrough(false);
    await Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (context) => const ProfileSwitchScreen(requireSelection: true)));
    if (!mounted) return;
    _isShowingProfileSelection = false;
    _updateTvosMenuPassthrough();
  }

  /// IndexedStack that disables tickers for offscreen children to prevent
  /// animation controllers on non-visible tabs from scheduling frames.
  Widget _buildTickerAwareStack() {
    return Column(
      children: [
        // Hoofdstuk 18.4: on TV a rejected token may not put a permanent
        // full-width red strip over Home, Films, Series and Search. The 10-foot
        // surface says it once, small, on the destination that can actually fix
        // it — the attention dot on Mijn Pleya (`TvTopNavigation`), leading to
        // the Servers screen that names the concrete server.
        //
        // Every other form factor keeps the banner exactly as it was: on a
        // phone or a desktop window the top strip is a reasonable place for it,
        // and it is the only affordance those layouts have.
        if (!_isTvShell) const AuthErrorBanner(),
        Expanded(
          child: mainScreenDestinationStack(screens: _screens, currentIndex: _currentIndex),
        ),
      ],
    );
  }

  List<Widget> _buildScreens(bool offline) {
    return [
      for (final tab in _getVisibleTabs(offline))
        switch (tab.id) {
          // `onManageServers` is hoofdstuk 14.7's escape from a source
          // picker with nothing reachable, and only this shell can change
          // tab — same reasoning as the discovery landings below, extended
          // to the Home hero's fase-6 activation wiring.
          NavigationTabId.discover => DiscoverScreen(
            key: _discoverKey,
            onManageServers: () => _selectTab(NavigationTabId.settings),
          ),
          // Fase 6 of docs/tvos-unified-experience.md (hoofdstuk 10.2a,
          // DEC-064): the discovery landing, one level above the fase-5
          // complete catalog those screens still are behind "Alles
          // bekijken".
          NavigationTabId.movies => TvMoviesLandingScreen(
            landingKey: _moviesKey,
            onManageServers: () => _selectTab(NavigationTabId.settings),
            onOpenAll: () => _openTvCompleteCatalog(TvDestinationId.movies),
          ),
          NavigationTabId.series => TvSeriesLandingScreen(
            landingKey: _seriesKey,
            onManageServers: () => _selectTab(NavigationTabId.settings),
            onOpenAll: () => _openTvCompleteCatalog(TvDestinationId.series),
          ),
          NavigationTabId.libraries => LibrariesScreen(
            key: _librariesKey,
            onLibraryOrderChanged: _onLibraryOrderChanged,
            onLibrarySelected: _handleLibrariesScreenSelected,
          ),
          NavigationTabId.liveTv => LiveTvScreen(key: _liveTvKey),
          NavigationTabId.search => SearchScreen(
            key: _searchKey,
            onManageServers: () => _selectTab(NavigationTabId.settings),
          ),
          NavigationTabId.requests => const SeerrDiscoverScreen(),
          NavigationTabId.downloads => DownloadsScreen(key: _downloadsKey),
          NavigationTabId.settings => SettingsScreen(key: _settingsKey),
          NavigationTabId.watchlist => WatchlistScreen(key: _watchlistKey),
          // Fase 7: TV gets its own personal hub ([DEC-063] replaces the TV
          // half of [DEC-023]). Mobile keeps `MyPleyaScreen`, which says in its
          // own doc comment that a phone list is not a 10-foot surface.
          NavigationTabId.myPleya =>
            _isTvShell
                ? TvMyPleyaScreen(
                    key: _tvMyPleyaKey,
                    onExitUp: _focusSidebar,
                    onOpenSection: _openTvMyPleyaSection,
                    onSwitchProfile: () => unawaited(_openProfilesFromShell()),
                    onSignOut: () => unawaited(AccountUiActions.logout(context)),
                  )
                : MyPleyaScreen(key: _myPleyaKey, onOpenTab: _selectTab),
        },
    ];
  }

  /// Normalize tab ID when switching between offline/online modes.
  /// Preserves the current tab if it exists in the new mode, otherwise defaults to first tab.
  NavigationTabId _normalizeTabForMode(NavigationTabId currentTab, bool isOffline) {
    final tabs = _getVisibleTabs(isOffline);
    if (tabs.any((t) => t.id == currentTab)) return currentTab;
    return _defaultTabForMode(isOffline);
  }

  NavigationTabId _defaultTabForMode(bool isOffline) => NavigationTab.resolveDefaultTab(
    isOffline: isOffline,
    hasLiveTv: _hasLiveTv,
    hasSeerr: _hasSeerr,
    hasWatchlist: _hasWatchlist,
    isMobile: _isMobile,
    preferredStartup: SettingsService.instanceOrNull?.read(SettingsService.startupSection),
  );

  void _triggerReconnect() {
    if (_isReconnecting) return;
    setState(() => _isReconnecting = true);

    final multiServerProvider = context.read<MultiServerProvider>();
    final serverManager = multiServerProvider.serverManager;
    final activeProfile = context.read<ActiveProfileProvider>();
    final binder = context.read<ActiveProfileBinder>();
    unawaited(() async {
      try {
        binder.start();
        // Health check first so stale "online" servers get marked offline before
        // we snapshot the offline list for reconnection.
        await serverManager.checkServerHealth();
        await serverManager.reconnectOfflineServers(forceRediscovery: true);
        if (!mounted) return;
        if (shouldRetryActiveProfileBindAfterReconnect(
          hasActiveProfile: activeProfile.active != null,
          hasVisibleConnectedServers: multiServerProvider.hasConnectedServers,
          hasManagerOnlineServers: serverManager.onlineServerIds.isNotEmpty,
          hasKnownOfflineServers: serverManager.offlineServerIds.isNotEmpty,
        )) {
          await binder.rebindActive();
        }
        if (!mounted) return;
        if (multiServerProvider.hasConnectedServers) {
          _offlineUntilConnected = false;
          _handleOfflineStatusChanged();
        }
      } finally {
        setStateIfMounted(() => _isReconnecting = false);
      }
    }());
  }

  Future<void> _loadTvLiveTvCapability() async {
    final remembered = await TvLiveTvCapabilityStore.read();
    if (!mounted || remembered == _tvLiveTvRemembered) return;
    _tvLiveTvRemembered = remembered;
    _syncTvDestinations();
  }

  void _handleLiveTvChanged() {
    final hasLiveTv = _multiServerProvider?.hasLiveTv ?? false;
    if (hasLiveTv == _lastHasLiveTv) {
      // The availability did not move, but a check may just have become
      // conclusive — which is the only event that may retire a remembered
      // capability. Returning here would leave a Live TV item in the bar for a
      // profile that provably no longer has one.
      _syncTvDestinations();
      return;
    }
    _lastHasLiveTv = hasLiveTv;

    setState(() {
      _screens = _buildScreens(_isOffline);
      _currentTab = _normalizeTabForMode(_currentTab, _isOffline);
    });
    _syncTvDestinations();
    _updateTvosMenuPassthrough();

    // A preferred startup section (only Live TV can be deferred) just became
    // available — switch to it via _selectTab so it gets the usual visibility
    // and focus handling. _selectTab clears _pendingStartupTab.
    final pending = _pendingStartupTab;
    if (pending != null && _getVisibleTabs(_isOffline).any((t) => t.id == pending)) {
      _selectTab(pending);
    }
  }

  void _handleSeerrChanged() {
    final hasSeerr = _seerrProvider?.isConfigured ?? false;
    if (hasSeerr == _lastHasSeerr) return;
    _lastHasSeerr = hasSeerr;
    if (!mounted) return;

    setState(() {
      _screens = _buildScreens(_isOffline);
      _currentTab = _normalizeTabForMode(_currentTab, _isOffline);
    });
    _updateTvosMenuPassthrough();
  }

  void _handleWatchlistChanged() {
    final hasWatchlist = _watchlistProvider?.hasWatchlist ?? false;
    if (hasWatchlist == _lastHasWatchlist) return;
    _lastHasWatchlist = hasWatchlist;
    if (!mounted) return;

    setState(() {
      _screens = _buildScreens(_isOffline);
      _currentTab = _normalizeTabForMode(_currentTab, _isOffline);
    });
    _updateTvosMenuPassthrough();
  }

  void _handleOfflineStatusChanged() {
    final hasVisibleConnectedServers = context.read<MultiServerProvider>().hasConnectedServers;
    if (hasVisibleConnectedServers) _offlineUntilConnected = false;
    final providerOffline = _offlineModeProvider?.isOffline ?? false;
    final newOffline = shouldRenderMainScreenOffline(
      providerOffline: providerOffline,
      startupOfflineUntilConnected: _offlineUntilConnected,
      hasVisibleConnectedServers: hasVisibleConnectedServers,
    );

    if (newOffline == _isOffline) return;

    final previousTab = _currentTab;
    final wasOffline = _isOffline;
    setState(() {
      _isReconnecting = false;
      _isOffline = newOffline;
      _screens = _buildScreens(_isOffline);
      _selectedLibraryGlobalKey = _isOffline ? null : _selectedLibraryGlobalKey;

      if (_isOffline) {
        // Remember the online tab so we can restore it when reconnecting.
        if (!wasOffline) {
          _lastOnlineTabId = previousTab;
        }

        final normalizedTab = _normalizeTabForMode(_currentTab, _isOffline);
        _currentTab = normalizedTab;

        // Track if we auto-switched to Downloads because the previous tab was unavailable.
        _autoSwitchedToDownloads =
            previousTab != NavigationTabId.downloads && normalizedTab == NavigationTabId.downloads;
      } else {
        // Coming back online: restore the last online tab if we forced a switch to Downloads.
        if (_autoSwitchedToDownloads) {
          final restoredTab = _lastOnlineTabId ?? NavigationTabId.discover;
          _currentTab = _normalizeTabForMode(restoredTab, _isOffline);
        } else {
          _currentTab = _normalizeTabForMode(_currentTab, _isOffline);
        }
        _autoSwitchedToDownloads = false;
      }
    });
    _updateTvosMenuPassthrough();

    // Refresh sidebar focus after rebuilding navigation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sideNavKey.currentState?.focusActiveItem();
    });

    // Ensure profile settings are warmed when coming back online
    if (!_isOffline) {
      unawaited(() async {
        final mp = context.read<MultiServerProvider>();
        final binder = context.read<ActiveProfileBinder>();
        binder.start();
        if (!mp.hasConnectedServers && context.read<ActiveProfileProvider>().active != null) {
          await binder.rebindActive();
          if (!mounted) return;
        }
        await context.userProfile.initialize();
        if (!mounted) return;
        await _primeOnlineServices(mp.serverManager);
      }());
    }
  }

  void _focusSidebar() {
    // On TV "the sidebar" is the top navigation. One method rather than two,
    // because every content screen already calls this to leave content and
    // none of them should have to know which shell they are in — see
    // [TvRootShell]'s note on the reused vocabulary.
    if (_isTvShell) {
      // The remote is going back to the bar, so a content-focus intent that has
      // not been satisfied yet is void. Without this, a DOWN pressed while the
      // first server was still answering would still be honoured a second later
      // — pulling the viewer out of the bar they had deliberately walked back
      // to (P2).
      _tvContentFocus.cancel();
      _focus.focusSidebar(
        focusActiveItem: () {
          if (!mounted) return;
          // The item the ring was last on, not the active destination: walking
          // to Search, going down into content and coming back should return
          // to Search rather than snapping to the open page.
          final node = _tvNavNodes.get(_tvNav.focusedDestination.focusKey);
          if (node.canRequestFocus) node.requestFocus();
        },
      );
      return;
    }
    // Capture target before requestFocus() auto-focuses a sidebar descendant
    // and overwrites lastFocusedKey (e.g. to the Libraries toggle button).
    final targetKey = _sideNavKey.currentState?.lastFocusedKey;
    _focus.focusSidebar(
      focusActiveItem: () {
        if (!mounted) return;
        _sideNavKey.currentState?.focusActiveItem(targetKey: targetKey);
      },
    );
  }

  void _focusContent({bool restorePreviousFocus = true}) {
    // Arming happens here rather than at each call site, because *every* way
    // the focus is deliberately moved into content goes through this method —
    // DOWN out of the bar, a re-select of the active destination, a nested
    // route opening. A screen that cannot satisfy it yet leaves it armed, and
    // consumes it when its content finally lands (P2).
    if (_isTvShell) {
      _tvContentFocus.arm(restorePreviousFocus ? TvContentFocusIntent.restore : TvContentFocusIntent.primary);
    }
    _focus.focusContent(
      restorePreviousFocus: restorePreviousFocus,
      focusDefault: () {
        if (!mounted) return;
        // A nested route is what the viewer is looking at; the destination's
        // own screen is offstage behind it, and focusing that would put the
        // remote on something invisible (hoofdstuk 7.5 step 2's stack).
        if (_isTvShell && _tvNav.activeCanPop) {
          _focusTvNestedRoute();
          return;
        }
        if (_screenKeyFor(_currentTab)?.currentState case final FocusableTab focusable) {
          focusable.focusActiveTabIfReady();
        }
      },
    );
  }

  /// The rail is drawn from [SidebarFocusCoordinator.isSidebarFocused], so the
  /// screen has to rebuild when it moves — including when it moves because the
  /// focus tree moved rather than because this screen asked for it.
  void _handleSidebarFocusChanged() {
    if (!mounted) return;
    setStateIfMounted(() {});
    _updateTvosMenuPassthrough();
  }

  void _handleSidebarInteractionExpandedChanged(bool expanded) {
    if (_isSidebarInteractionExpanded == expanded) return;
    setState(() => _isSidebarInteractionExpanded = expanded);
  }

  void _handleOverlaySheetOpenChanged(bool open) {
    if (_isOverlaySheetOpen == open) return;
    _isOverlaySheetOpen = open;
    _updateTvosMenuPassthrough();
  }

  double _sideNavigationWidth(BuildContext context, {required bool alwaysExpanded}) {
    final isExpanded = alwaysExpanded || _isSidebarFocused || _isSidebarInteractionExpanded;
    return isExpanded
        ? SideNavigationRailState.expandedWidth
        : SideNavigationRailState.collapsedWidthForContext(context);
  }

  bool get _shouldPassTvosMenuToSystem {
    final tabs = _getVisibleTabs(_isOffline);
    return shouldPassTvosMenuToSystem(
      isAppleTV: PlatformDetector.isAppleTV(),
      isShowingProfileSelection: _isShowingProfileSelection,
      isOverlaySheetOpen: _isOverlaySheetOpen,
      isRouteCurrent: ModalRoute.of(context)?.isCurrent == true,
      isSidebarFocused: _isSidebarFocused,
      hasVisibleTabs: tabs.isNotEmpty,
      // Fase 7: a nested Mijn Pleya section is a route the app can still pop,
      // so Menu belongs to the app, not to the system, until it is closed.
      isCurrentTabRoot: tabs.isNotEmpty && _currentTab == tabs.first.id && !(_isTvShell && _tvNav.activeCanPop),
    );
  }

  void _setTvosMenuPassthrough(bool enabled) {
    if (!PlatformDetector.isAppleTV()) return;
    unawaited(TvosSystemNavigationService.setMenuPassthroughEnabled(enabled));
  }

  void _updateTvosMenuPassthrough() {
    if (!mounted) return;
    _setTvosMenuPassthrough(_shouldPassTvosMenuToSystem);
  }

  /// Opens the management profile picker with the same Menu bracket the
  /// launch gate already uses (`_promptForInitialProfileSelection`).
  ///
  /// [AccountUiActions.openProfiles] pushes on the **root** navigator, and
  /// this screen's route observer watches the *profile* navigator, so
  /// `didPushNext` never fires for it — nothing else would lower the
  /// passthrough. The chip is pressed from exactly the state that raised it
  /// (bar focused, tab root), so without this the picker opens with Menu
  /// still handed to UIKit and the first Menu press leaves the app instead of
  /// closing the picker.
  Future<void> _openProfilesFromShell() async {
    _isShowingProfileSelection = true;
    _setTvosMenuPassthrough(false);
    await AccountUiActions.openProfiles(context);
    if (!mounted) return;
    _isShowingProfileSelection = false;
    _updateTvosMenuPassthrough();
  }

  /// Suppress stray back events after a child route pops.
  /// On Android TV the platform popRoute can arrive before the key events,
  /// so BackKeySuppressorObserver misses them and they leak into _handleBackKey.
  bool _suppressBackAfterPop = false;

  KeyEventResult _handleMainBack() {
    final tabs = _getVisibleTabs(_isOffline);
    final homeTab = tabs.isNotEmpty ? tabs.first.id : null;
    final now = DateTime.now();
    final lastBackPressAt = _lastBackPressAt;
    final hasRecentBackPress = lastBackPressAt != null && now.difference(lastBackPressAt) < _backExitWindow;

    final decision = mainBackKeyDecision(
      hasVisibleTabs: tabs.isNotEmpty,
      isAtHomeTab: homeTab != null && _currentTab == homeTab,
      isAppleTV: PlatformDetector.isAppleTV(),
      hasRecentBackPress: hasRecentBackPress,
    );

    switch (decision) {
      case MainBackDecision.noVisibleTabs:
        return KeyEventResult.handled;
      case MainBackDecision.goHome:
        _selectTab(homeTab!);
        _lastBackPressAt = null;
        return KeyEventResult.handled;
      case MainBackDecision.tvMenuPassthroughStale:
        // The tvOS engine normally passes root Menu presses through to UIKit.
        // If a stale event still reaches Flutter, avoid showing an exit
        // prompt that cannot be honored app-side.
        _lastBackPressAt = null;
        return KeyEventResult.handled;
      case MainBackDecision.exitNow:
        _lastBackPressAt = null;
        unawaited(AppExitService.requestExit());
        return KeyEventResult.handled;
      case MainBackDecision.armExitPrompt:
        _lastBackPressAt = now;
        showMainSnackBar(t.common.pressBackAgainToExit, duration: _backExitWindow);
        return KeyEventResult.handled;
    }
  }

  KeyEventResult _handleMainBackKeyAction(KeyEvent event) {
    if (!event.logicalKey.isBackKey) return KeyEventResult.ignored;

    if (BackKeyUpSuppressor.consumeIfSuppressed(event)) {
      return KeyEventResult.handled;
    }

    // AppleTV: KeyDown does the work, KeyUp is consumed silently. See the
    // matching comment in handleBackKeyAction for why the suppressor pattern
    // doesn't fit here.
    if (PlatformDetector.isAppleTV() && event is KeyDownEvent) {
      final result = _handleMainBack();
      if (result == KeyEventResult.handled) {
        BackKeyCoordinator.markHandled();
      }
      return result;
    }
    if (PlatformDetector.isAppleTV() && event is KeyUpEvent) {
      return KeyEventResult.handled;
    }

    if (event is KeyUpEvent) {
      final result = _handleMainBack();
      if (result == KeyEventResult.handled) {
        BackKeyCoordinator.markHandled();
      }
      return result;
    }
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleBackKey(KeyEvent event) {
    if (ModalRoute.of(context)?.isCurrent != true) {
      return KeyEventResult.ignored;
    }

    if (_suppressBackAfterPop && event.logicalKey.isBackKey) {
      if (event is KeyUpEvent) _suppressBackAfterPop = false;
      return KeyEventResult.handled;
    }

    if (_isTvShell) {
      return switch (tvBackStep(hasNestedRoute: _tvNav.activeCanPop, isNavigationFocused: _isSidebarFocused)) {
        TvBackStep.popNested => handleBackKeyAction(event, _popTvNestedRoute),
        TvBackStep.focusTopNavigation => handleBackKeyAction(event, _focusSidebar),
        TvBackStep.rootContract => _handleMainBackKeyAction(event),
      };
    }

    if (!_isSidebarFocused) {
      // Content focused → move to sidebar
      return handleBackKeyAction(event, _focusSidebar);
    }

    return _handleMainBackKeyAction(event);
  }

  /// F11 toggles OS fullscreen from anywhere in the main UI. The in-player
  /// hotkey (default `f`) only works while the player is mounted; this is
  /// the escape hatch when fullscreen persists after the player closes.
  KeyEventResult _handleFullscreenShortcut(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.f11) return KeyEventResult.ignored;
    if (!PlatformDetector.isDesktopOS()) return KeyEventResult.ignored;

    unawaited(FullscreenStateManager().toggleFullscreen());
    return KeyEventResult.handled;
  }

  /// Handle Cmd+F (macOS) / Ctrl+F (Windows/Linux) to navigate to search.
  KeyEventResult _handleSearchShortcut(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.keyF) return KeyEventResult.ignored;

    final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
    final isControlPressed = HardwareKeyboard.instance.isControlPressed;

    final isMacShortcut = Platform.isMacOS && isMetaPressed && !isControlPressed;
    final isOtherShortcut = !Platform.isMacOS && isControlPressed && !isMetaPressed;

    if (!isMacShortcut && !isOtherShortcut) return KeyEventResult.ignored;
    if (_isOffline) return KeyEventResult.handled;

    _selectTab(NavigationTabId.search);
    if (_isSidebarFocused) _focusContent();
    // Schedule focus after the frame so the search screen is visible in the IndexedStack
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_searchKey.currentState case final SearchInputFocusable searchable) {
        searchable.focusSearchInput();
      }
    });
    return KeyEventResult.handled;
  }

  @override
  void didPush() {
    // Called when this route has been pushed (initial navigation)
    if (_currentTab == NavigationTabId.discover) {
      _onDiscoverBecameVisible();
    }
  }

  @override
  void didPushNext() {
    _setTvosMenuPassthrough(false);
    // Called when a child route is pushed on top (e.g., video player)
    if (_currentTab == NavigationTabId.discover) {
      if (_discoverKey.currentState case final TabVisibilityAware aware) {
        aware.onTabHidden();
      }
    }
  }

  @override
  void didPopNext() {
    // Suppress stray back key events from the pop that just returned us here
    _suppressBackAfterPop = true;
    // Auto-clear after 2 frames in case no back event arrives
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _suppressBackAfterPop = false;
      });
    });

    // Called when returning to this route from a child route (e.g., from video player)
    _updateTvosMenuPassthrough();
    if (_currentTab == NavigationTabId.discover) {
      if (_discoverKey.currentState case final TabVisibilityAware aware) {
        aware.onTabShown();
      }
      _onDiscoverBecameVisible();
    }
  }

  void _onDiscoverBecameVisible() {
    appLogger.d('Navigated to home');
    // Refresh content when returning to discover page
    if (_discoverKey.currentState case final Refreshable refreshable) {
      refreshable.refresh();
    }
  }

  void _onLibraryOrderChanged() {
    // Refresh side navigation when library order changes
    _sideNavKey.currentState?.reloadLibraries();
  }

  /// Invalidate cached data across screens after a profile switch.
  /// The [ActiveProfileBinder] has already pushed fresh per-server tokens
  /// into [MultiServerManager], so this just clears UI caches and refreshes
  /// the visible screens.
  Future<void> _invalidateAllScreens() async {
    appLogger.d('Invalidating screen data after profile switch');

    // Hoofdstuk 7.6: "profielwissel → geheugen volledig wissen". A remembered
    // group id belongs to the profile it was stored under, and re-focusing it
    // for the next profile would be a privacy leak (hoofdstuk 22), not just an
    // odd jump. The Live TV capability is per profile in storage, so it is
    // re-read rather than carried over.
    if (_isTvShell) {
      _tvNav.clearFocusMemory();
      _tvNav.clearNestedRoutes();
      _tvLiveTvRemembered = false;
      unawaited(_loadTvLiveTvCapability());
    }

    final multiServerProvider = context.read<MultiServerProvider>();
    final hiddenLibrariesProvider = context.read<HiddenLibrariesProvider>();
    final librariesProvider = context.read<LibrariesProvider>();
    final playbackStateProvider = context.read<PlaybackStateProvider>();

    // Drop volatile API cache rows before screens kick off their refetch.
    // Pinned rows back offline downloads and must survive profile switches.
    try {
      await ApiCache.instance.clearVolatile();
    } catch (e, st) {
      appLogger.w('Failed to clear ApiCache on profile switch', error: e, stackTrace: st);
    }

    await hiddenLibrariesProvider.refresh();
    if (!mounted) return;

    librariesProvider.clear();

    if (multiServerProvider.serverManager.serverIds.isNotEmpty) {
      if (!mounted) return;
      context.read<OfflineWatchSyncService>().onServersConnected();
      // Profile switches re-bind connections — give DownloadProvider a chance
      // to repopulate metadata that the per-backend caches now resolve.
      unawaited(context.read<DownloadProvider>().refreshMetadataFromCache());
      librariesProvider.initialize(multiServerProvider.aggregationService);
      await librariesProvider.refresh();
    }

    playbackStateProvider.clearShuffle();

    if (_discoverKey.currentState case final FullRefreshable refreshable) {
      refreshable.fullRefresh();
    }
    if (_librariesKey.currentState case final FullRefreshable refreshable) {
      refreshable.fullRefresh();
    }
    if (_searchKey.currentState case final FullRefreshable refreshable) {
      refreshable.fullRefresh();
    }

    // Refresh user-level settings (audio/sub defaults) for the new identity.
    if (mounted) {
      unawaited(context.userProfile.refreshProfileSettings());
    }
  }

  void _selectTab(NavigationTabId tab) {
    // Guard: ignore if tab isn't available in current mode
    if (!_getVisibleTabs(_isOffline).any((t) => t.id == tab)) return;

    // Fase 7, hoofdstuk 18.2: on TV these four live inside Mijn Pleya rather
    // than beside Home. Every existing caller — the companion remote, a
    // "manage servers" action, `_selectLibrary` — keeps working and simply
    // arrives at the new place.
    if (_isTvShell) {
      if (_tvSectionForTab(tab) case final TvMyPleyaSection section) {
        _openTvMyPleyaSection(section);
        return;
      }
      _tvNav.syncToTab(tab);
    }

    final previousTab = _currentTab;
    setState(() {
      _currentTab = tab;
      // An explicit selection cancels any deferred startup-section switch.
      _pendingStartupTab = null;
      if (!_isOffline) {
        _lastOnlineTabId = tab;
      } else if (previousTab != tab) {
        // User made an explicit offline selection, so don't auto-restore later.
        _autoSwitchedToDownloads = false;
      }
    });
    _updateTvosMenuPassthrough();

    if (previousTab != tab) {
      // Only AutomationScreen/AutomationRouteObserver gate this internally;
      // a bare AutomationEventLog.emit() call needs its own guard so a
      // normal build never accumulates event history for nothing.
      if (kPleyaVerify) {
        AutomationEventLog.instance.emit('navigation.tab_changed', {'from': previousTab.name, 'to': tab.name});
        AutomationRouteState.instance.updateTab(tab.name);
      }

      // Notify previous screen it's being hidden
      if (_screenKeyFor(previousTab)?.currentState case final TabVisibilityAware aware) {
        aware.onTabHidden();
      }
      // Notify and focus new screen
      final newState = _screenKeyFor(tab)?.currentState;
      if (newState case final TabVisibilityAware aware) {
        aware.onTabShown();
      }
      // Not on the TV shell. There, moving the focus is the shell's decision
      // and nobody else's (P2): activating a destination in the bar leaves the
      // remote in the bar, and this line was the third of the three paths that
      // disagreed about that. Every TV route that *should* move the focus —
      // DOWN out of the bar, a re-select, opening a Mijn Pleya section or a
      // nested route — calls `_focusContent` explicitly, which arms the one
      // authority. On the rail and bottom-bar shells the old behaviour is
      // exactly right and is untouched.
      if (!_isTvShell) {
        if (newState case final FocusableTab focusable) {
          focusable.focusActiveTabIfReady();
        }
      }
    }

    // Discover: always refresh content (even on re-selection)
    if (!_isOffline && tab == NavigationTabId.discover) {
      _onDiscoverBecameVisible();
    }

    // Focus search input after rebuild so IndexedStack has made it visible
    if (tab == NavigationTabId.search) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_searchKey.currentState case final SearchInputFocusable searchable) {
          searchable.focusSearchInput();
        }
      });
    }
  }

  /// Selects Mijn Pleya and opens [section] inside it.
  ///
  /// The navigator may not be mounted yet on the frame that selects the
  /// destination — it is built by the `IndexedStack` this call is about to
  /// switch to — so the open is deferred by a frame rather than dropped.
  void _openTvMyPleyaSection(TvMyPleyaSection section) {
    _selectTab(NavigationTabId.myPleya);
    _tvNav.pushNested(
      TvDestinationId.myPleya,
      tvMyPleyaNestedRoute(section, librariesKey: _tvLibrariesKey, watchlistKey: _tvWatchlistKey),
    );
    _focusContent(restorePreviousFocus: false);
  }

  /// Opens a screen above the active destination's root, with the top
  /// navigation still on screen (hoofdstuk 33's shared shell is binding on all
  /// eight references, "Alle films" included).
  void _openTvNestedRoute(TvDestinationId destination, TvNestedRoute route) {
    _tvNav.activate(destination);
    _tvNav.pushNested(destination, route);
    // The screen is not mounted until the frame this push schedules, so its
    // focus is claimed after it rather than in the same breath.
    _focus.focusContent(
      restorePreviousFocus: false,
      focusDefault: () {
        if (!mounted) return;
        _focusTvNestedRoute();
      },
    );
  }

  /// Puts the focus inside the nested route currently on top, once it exists.
  ///
  /// Delegates to [TvNestedSurface], which asks the screen's own
  /// `FocusableTab` first and falls back to the first focusable control in the
  /// route's subtree. The old body did only the first half, against a
  /// `screenKey` that eight of the ten Mijn Pleya sections never attached to
  /// anything — so for those it matched nothing, requested nothing, and the
  /// section opened with the remote on empty space and no way back.
  void _focusTvNestedRoute() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _tvNav.activeNestedRoute?.surfaceKey.currentState?.focusEntry();
    });
  }

  /// "Alles bekijken" from a Films or Series landing (DEC-064, DEC-068).
  ///
  /// A nested route rather than a push on the profile navigator, because
  /// hoofdstuk 33.5 and 33.6 draw the complete catalog with the top navigation
  /// above it and the destination still lit — the shared shell is binding on
  /// all eight references. The landing underneath stays mounted, so Back
  /// returns to the row and the tile it was left on rather than reloading a
  /// projection.
  void _openTvCompleteCatalog(TvDestinationId destination) {
    _openTvNestedRoute(
      destination,
      TvNestedRoute(
        id: 'tvCatalog_${destination.name}',
        screenKey: GlobalKey(debugLabel: 'tvCatalog_${destination.name}'),
        // Hoofdstuk 7.6, register I22/I23. The catalog is the one TV surface
        // that is torn down and rebuilt on a destination switch — every
        // destination *root* stays mounted in the `IndexedStack` and keeps its
        // own place — so its place is read from and written back to the
        // coordinator, which outlives the switch. Read here rather than
        // captured once: the builder runs again on the way back, and by then
        // the map holds what the previous visit reported.
        builder: (context) => destination == TvDestinationId.series
            ? TvSeriesScreen(
                catalogKey: _tvNav.nestedRoutesFor(destination).last.screenKey,
                onManageServers: () => _selectTab(NavigationTabId.settings),
                restoreFrom: _tvNav.contentFocusFor(destination),
                onRemember: (place) => _tvNav.rememberContentFocus(destination, place),
              )
            : TvMoviesScreen(
                catalogKey: _tvNav.nestedRoutesFor(destination).last.screenKey,
                onManageServers: () => _selectTab(NavigationTabId.settings),
                restoreFrom: _tvNav.contentFocusFor(destination),
                onRemember: (place) => _tvNav.rememberContentFocus(destination, place),
              ),
      ),
    );
  }

  /// Back inside a destination (hoofdstuk 7.5 step 2): pop, and put the remote
  /// back on the control that opened the route.
  bool _popTvNestedRoute() {
    final popped = _tvNav.popNested();
    if (popped == null) return false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = popped.restoreFocusKey;
      if (key != null && _tvNav.active == TvDestinationId.myPleya) {
        _tvMyPleya?.focusKey(key);
        return;
      }
      _focusContent(restorePreviousFocus: true);
    });
    return true;
  }

  /// Handle library selection from side navigation rail
  void _selectLibrary(String libraryGlobalKey) {
    _selectedLibraryGlobalKey = libraryGlobalKey;
    // Hoofdstuk 6.4's compatibility adapter: on TV the shell selects Mijn
    // Pleya, the Mijn Pleya navigator opens Bibliotheken, and the very same
    // `loadLibraryByKey` receives the very same global key. The central media
    // and library navigation did not have to be rewritten for the new shell.
    if (_isTvShell) {
      _openTvMyPleyaSection(TvMyPleyaSection.libraries);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_tvLibrariesKey.currentState case final LibraryLoadable loadable) {
          loadable.loadLibraryByKey(libraryGlobalKey);
        }
        if (_tvLibrariesKey.currentState case final FocusableTab focusable) {
          focusable.focusActiveTabIfReady();
        }
      });
      return;
    }
    _selectTab(NavigationTabId.libraries);
    // Tell LibrariesScreen to load this library after tab switch
    if (_librariesKey.currentState case final LibraryLoadable loadable) {
      loadable.loadLibraryByKey(libraryGlobalKey);
    }
    if (_librariesKey.currentState case final FocusableTab focusable) {
      focusable.focusActiveTabIfReady();
    }
  }

  void _openSettings() {
    if (PlatformDetector.shouldUseSideNavigation(context)) {
      _selectTab(NavigationTabId.settings);
      _focusContent(restorePreviousFocus: false);
      return;
    }

    Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  void _handleLibrariesScreenSelected(String libraryGlobalKey) {
    if (_selectedLibraryGlobalKey == libraryGlobalKey) return;
    setState(() => _selectedLibraryGlobalKey = libraryGlobalKey);
  }

  void _showLibraryQuickPicker(BuildContext context) {
    if (_isOffline) return;

    final controller = OverlaySheetController.of(context);
    final groupByServer = SettingsService.instanceOrNull?.read(SettingsService.groupLibrariesByServer) ?? false;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.62;

    controller
        .show<String>(
          showDragHandle: true,
          constraints: BoxConstraints(maxHeight: maxHeight),
          builder: (sheetContext) {
            return Consumer2<LibrariesProvider, HiddenLibrariesProvider>(
              builder: (context, librariesProvider, hiddenLibrariesProvider, _) {
                if (!hiddenLibrariesProvider.isInitialized) {
                  return LibraryQuickPickerSheet(
                    libraries: const [],
                    selectedLibraryKey: _selectedLibraryGlobalKey,
                    isLoading: true,
                    groupByServer: groupByServer,
                    emptyMessage: t.libraries.noLibrariesFound,
                    onSelected: (libraryGlobalKey) => controller.close(libraryGlobalKey),
                  );
                }

                final allLibraries = librariesProvider.libraries;
                final hiddenKeys = hiddenLibrariesProvider.hiddenLibraryKeys;
                final visibleLibraries = allLibraries
                    .where((library) => !hiddenKeys.contains(library.globalKey))
                    .toList();
                final emptyMessage = allLibraries.isEmpty
                    ? t.libraries.noLibrariesFound
                    : t.libraries.allLibrariesHidden;

                return LibraryQuickPickerSheet(
                  libraries: visibleLibraries,
                  selectedLibraryKey: _selectedLibraryGlobalKey,
                  isLoading: librariesProvider.isLoading,
                  groupByServer: groupByServer,
                  emptyMessage: emptyMessage,
                  onSelected: (libraryGlobalKey) => controller.close(libraryGlobalKey),
                );
              },
            );
          },
        )
        .then((libraryGlobalKey) {
          if (!mounted || libraryGlobalKey == null) return;
          _selectLibrary(libraryGlobalKey);
        });
  }

  /// Whether the Live TV tab is currently visible
  /// Use the synchronized value so screens list and nav bar always agree.
  /// Updated by _handleLiveTvChanged when the provider notifies.
  bool get _hasLiveTv => _lastHasLiveTv;

  /// Whether the Requests (Jellyseerr/Overseerr) tab is currently visible.
  /// Synchronized value so the screens list and nav bar always agree.
  bool get _hasSeerr => _lastHasSeerr;

  /// Whether there is a kijklijst to show. Gates the Watchlist destination
  /// only; My Pleya exists on mobile regardless, because it also holds
  /// Downloads, Requests and Settings.
  bool get _hasWatchlist => _lastHasWatchlist;

  /// Whether this build renders the mobile shell. Captured at the top of
  /// [build] so the tab list, the screens list and the bottom bar all answer
  /// from the same value instead of each re-reading the layout.
  bool _isMobile = false;

  /// Get navigation tabs filtered by offline mode
  List<NavigationTab> _getVisibleTabs(bool isOffline) {
    return NavigationTab.getVisibleTabs(
      isOffline: isOffline,
      hasLiveTv: _hasLiveTv,
      hasSeerr: _hasSeerr,
      hasWatchlist: _hasWatchlist,
      isMobile: _isMobile,
    );
  }

  List<NavigationTab> _getBottomNavigationTabs(BuildContext context) {
    return mainScreenBottomNavigationTabs(
      visibleTabs: _getVisibleTabs(_isOffline),
      isMobile: PlatformDetector.isMobile(context),
      isOffline: _isOffline,
      currentTab: _currentTab,
    );
  }

  /// Get the GlobalKey for a given tab.
  GlobalKey? _screenKeyFor(NavigationTabId tab) {
    return switch (tab) {
      NavigationTabId.discover => _discoverKey,
      NavigationTabId.movies => _moviesKey,
      NavigationTabId.series => _seriesKey,
      NavigationTabId.libraries => _librariesKey,
      NavigationTabId.liveTv => _liveTvKey,
      NavigationTabId.search => _searchKey,
      NavigationTabId.requests => null,
      NavigationTabId.downloads => _downloadsKey,
      NavigationTabId.settings => _settingsKey,
      NavigationTabId.watchlist => _watchlistKey,
      NavigationTabId.myPleya => _isTvShell ? _tvMyPleyaKey : _myPleyaKey,
    };
  }

  Widget _buildBottomNavigationBar(BuildContext context, {required bool hideLabels}) {
    final tabs = _getBottomNavigationTabs(context);
    final projected = mainScreenSelectedBarTab(
      currentTab: _currentTab,
      isOffline: _isOffline,
      barTabs: tabs.map((tab) => tab.id).toList(),
    );
    final selectedIndex = tabs.indexWhere((tab) => tab.id == projected);
    final navigationBar = NavigationBar(
      selectedIndex: selectedIndex >= 0 ? selectedIndex : 0,
      onDestinationSelected: (i) {
        if (i >= 0 && i < tabs.length) _selectTab(tabs[i].id);
      },
      labelBehavior: hideLabels
          ? NavigationDestinationLabelBehavior.alwaysHide
          : NavigationDestinationLabelBehavior.alwaysShow,
      destinations: tabs.map((tab) => tab.toDestination()).toList(),
    );

    // Netflix mobile: frosted near-black bar. Blur the content scrolling
    // behind it; the translucent color comes from navigationBarTheme.
    Widget frosted(Widget bar) => ClipRect(
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: bar),
    );

    final librariesIndex = tabs.indexWhere((tab) => tab.id == NavigationTabId.libraries);
    if (tabs.isEmpty) return frosted(navigationBar);

    return frosted(
      LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedWidth) return navigationBar;

          final itemWidth = constraints.maxWidth / tabs.length;
          final isRtl = Directionality.of(context) == TextDirection.rtl;

          double itemLeft(int index) => isRtl ? constraints.maxWidth - (itemWidth * (index + 1)) : itemWidth * index;

          return Stack(
            children: [
              navigationBar,
              // Solid red indicator bar above the active icon.
              if (selectedIndex >= 0)
                Positioned(
                  left: itemLeft(selectedIndex) + (itemWidth - 18) / 2,
                  top: 0,
                  width: 18,
                  height: 3,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: kAccent, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                ),
              if (librariesIndex >= 0)
                Positioned(
                  left: itemLeft(librariesIndex),
                  top: 0,
                  bottom: 0,
                  width: itemWidth,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    excludeFromSemantics: true,
                    onLongPress: () {
                      Feedback.forLongPress(context);
                      _showLibraryQuickPicker(context);
                    },
                    child: const SizedBox.expand(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final useSideNav = PlatformDetector.shouldUseSideNavigation(context);
    // My Pleya only exists on the mobile shell, and the screens list has to
    // agree with the tab list about that. Rebuild the screens when the answer
    // actually changes (a fold, a window resize) rather than on every build.
    final isMobile = PlatformDetector.isMobile(context);
    if (isMobile != _isMobile) {
      _isMobile = isMobile;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _screens = _buildScreens(_isOffline);
          _currentTab = _normalizeTabForMode(_currentTab, _isOffline);
        });
      });
    }
    return AutomationScreen(
      id: AutomationIds.screenMain,
      readiness: () => const AutomationReadiness.ready(),
      child: _buildContent(context, useSideNav),
    );
  }

  /// The fase-7 TV root (hoofdstuk 6.2). See [TvRootShell] for why the focus
  /// coordinator's "sidebar" vocabulary is reused rather than renamed.
  Widget _buildTvShell(BuildContext context) {
    return TvRootShell(
      coordinator: _tvNav,
      contentFocus: _tvContentFocus,
      navNodes: _tvNavNodes,
      navFocusScope: _sidebarFocusScope,
      contentFocusScope: _contentFocusScope,
      isNavFocused: _isSidebarFocused,
      profile: context.watch<ActiveProfileProvider?>()?.active,
      onSelectDestination: _selectTvDestination,
      onFocusContent: _focusContent,
      onFocusNav: _focusSidebar,
      onOpenProfiles: () => unawaited(_openProfilesFromShell()),
      onOverlaySheetOpenChanged: _handleOverlaySheetOpenChanged,
      onKeyEvent: _handleTvShellKey,
      selectLibrary: _selectLibrary,
      openSettings: _openSettings,
      child: _buildTickerAwareStack(),
    );
  }

  KeyEventResult _handleTvShellKey(KeyEvent event) {
    // While a sheet is open, closing it is the host's job (hoofdstuk 7.5 step
    // 1). Acting here too made the same press close the sheet *and* move the
    // focus underneath it — the bug the rail shell already carries a comment
    // about.
    if (_isOverlaySheetOpen) return KeyEventResult.ignored;
    final searchResult = _handleSearchShortcut(event);
    if (searchResult == KeyEventResult.handled) return searchResult;
    return _handleBackKey(event);
  }

  /// A destination was activated in the bar.
  ///
  /// Re-selecting the destination you are already on restores the position you
  /// had inside it instead of resetting to the top, and starts no refresh
  /// (hoofdstuk 7.2) — [_selectTab] already returns early for an unchanged tab.
  /// Two different presses, and they were being treated as one.
  ///
  /// Select on the destination you are **already on** is hoofdstuk 7.2's
  /// "restore where I was", and it keeps calling `_focusContent`. Select on
  /// **another** destination is a change of what is on screen, not a request to
  /// go stand in it: the viewer is walking the bar, the page behind it changes,
  /// and the remote stays where the ring is. Focusing the content there was the
  /// first of the three paths P2 is about, and it is the one the report opened
  /// with — choosing Home dropped the remote onto the billboard's Afspelen pill
  /// before the viewer had asked for anything.
  void _selectTvDestination(TvDestinationId destination) {
    final wasActive = _tvNav.active == destination && _currentTab == destination.tab;
    _tvNav.activate(destination);
    // `_selectTab` is *not* a no-op for the tab it is already on: it setStates
    // unconditionally and, for Home, calls `_onDiscoverBecameVisible()` — a
    // network refresh. Hoofdstuk 7.2 is explicit that Select on the destination
    // you are already on "start geen automatische netwerkrefresh", so the guard
    // is here rather than being wished for downstream.
    // The rule itself lives on the authority, not here — see
    // [TvContentFocusAuthority.onDestinationSelected]. This method's job is to
    // change the page; where the remote belongs afterwards is one decision with
    // one owner.
    final intent = _tvContentFocus.onDestinationSelected(wasActive: wasActive);
    if (!wasActive) _selectTab(destination.tab);
    if (intent != null) _focusContent(restorePreviousFocus: true);
  }

  /// Recomputes the bar and, when the active destination just disappeared,
  /// moves to Home (hoofdstuk 19).
  void _syncTvDestinations() {
    if (!_isTvShell) return;
    final resolved = resolveLiveTvCapability(
      remembered: _tvLiveTvRemembered,
      available: _hasLiveTv,
      conclusive: _multiServerProvider?.lastLiveTvCheckWasConclusive ?? false,
    );
    if (resolved.store case final bool store) {
      _tvLiveTvRemembered = store;
      unawaited(store ? TvLiveTvCapabilityStore.remember() : TvLiveTvCapabilityStore.forget());
    }
    final displaced = _tvNav.updateConditions(TvNavConditions(hasLiveTv: resolved.visible));
    if (displaced != null) _selectTab(displaced.tab);
  }

  /// The Mijn Pleya section a tab maps to on TV, or null when the tab is a
  /// destination in its own right.
  ///
  /// Hoofdstuk 18.2 moved four of the rail's rows inside Mijn Pleya. Redirecting
  /// here rather than leaving them as parallel root tabs is what keeps one
  /// answer to "where am I": without it, `_selectTab(settings)` would show
  /// Settings as root content while the bar lit up Mijn Pleya, and Back would
  /// go to the bar instead of to the hub.
  static TvMyPleyaSection? _tvSectionForTab(NavigationTabId tab) => switch (tab) {
    NavigationTabId.libraries => TvMyPleyaSection.libraries,
    NavigationTabId.watchlist => TvMyPleyaSection.watchlist,
    NavigationTabId.requests => TvMyPleyaSection.requests,
    NavigationTabId.downloads => TvMyPleyaSection.downloads,
    NavigationTabId.settings => TvMyPleyaSection.settings,
    _ => null,
  };

  Widget _buildContent(BuildContext context, bool useSideNav) {
    // Fase 7: TV gets its own root. Checked before [useSideNav] because a TV is
    // also a "should use side navigation" surface — it was one until this fase
    // — and the two branches must never both be able to run (hoofdstuk 6.2:
    // one root navigation authority, never a rail and a bar at once).
    if (_isTvShell) return _buildTvShell(context);

    if (useSideNav) {
      return SettingValueBuilder<bool>(
        pref: SettingsService.alwaysKeepSidebarOpen,
        builder: (context, alwaysExpanded, _) {
          final targetContentOffset = _sideNavigationWidth(context, alwaysExpanded: alwaysExpanded);
          final reservedContentOffset = alwaysExpanded
              ? SideNavigationRailState.expandedWidth
              : SideNavigationRailState.collapsedWidthForContext(context);

          return OverlaySheetHost(
            onOpenChanged: _handleOverlaySheetOpenChanged,
            // canPop:false blocks the system route-pop (matching the old inert
            // PopScope). The dpad/key back chain (content → top tabs → sidebar →
            // home) is owned entirely by the key path below; there is NO
            // onSystemBack because a pure popRoute must not short-circuit that
            // chain to home. The host still closes an open sheet on system back.
            canPop: false,
            child: Focus(
              onKeyEvent: (node, event) {
                // While a sheet is open, closing it (and refocusing escaped
                // nav keys) is the host's fallback handler's job. Acting here
                // too made the same back press close the sheet AND jump focus
                // to the sidebar underneath it.
                if (_isOverlaySheetOpen) return KeyEventResult.ignored;
                final fullscreenResult = _handleFullscreenShortcut(event);
                if (fullscreenResult == KeyEventResult.handled) return fullscreenResult;
                final searchResult = _handleSearchShortcut(event);
                if (searchResult == KeyEventResult.handled) return searchResult;
                return _handleBackKey(event);
              },
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                tween: Tween<double>(end: targetContentOffset),
                child: FocusScope(
                  node: _contentFocusScope,
                  // No autofocus - we control focus programmatically to prevent
                  // autofocus from stealing focus back after setState() rebuilds
                  child: _buildTickerAwareStack(),
                ),
                builder: (context, contentLeftPadding, contentChild) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final viewportWidth = constraints.maxWidth;
                      // Layout from the tween END value: deriving it from the
                      // animated value changed MainScreenFocusScope every tick
                      // of the sidebar expansion, rebuilding every dependent
                      // (the whole TV content tree) per frame. The slide is a
                      // paint-only translate on the content below instead.
                      final contentLayout = mainScreenSideNavigationContentLayout(
                        viewportWidth: viewportWidth,
                        currentSideNavigationWidth: targetContentOffset,
                        reservedSideNavigationWidth: reservedContentOffset,
                      );
                      return MainScreenFocusScope(
                        focusSidebar: _focusSidebar,
                        focusContent: _focusContent,
                        isSidebarFocused: _isSidebarFocused,
                        sideNavigationWidth: targetContentOffset,
                        reservedSideNavigationWidth: reservedContentOffset,
                        foregroundLeft: contentLayout.left,
                        foregroundWidth: contentLayout.width,
                        viewportWidth: viewportWidth,
                        selectLibrary: _selectLibrary,
                        openSettings: _openSettings,
                        child: SideNavigationScope(
                          child: Stack(
                            clipBehavior: Clip.hardEdge,
                            children: [
                              Positioned.fill(child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor)),
                              Positioned(
                                top: 0,
                                bottom: 0,
                                left: contentLayout.left,
                                width: contentLayout.width,
                                // Duration/curve of this tween must stay in
                                // sync with SideNavigationBleedBuilder, which
                                // counter-animates viewport-pinned overlays.
                                child: Transform.translate(
                                  offset: Offset(contentLeftPadding - targetContentOffset, 0),
                                  child: contentChild!,
                                ),
                              ),
                              Positioned(
                                top: 0,
                                bottom: 0,
                                left: 0,
                                child: FocusScope(
                                  node: _sidebarFocusScope,
                                  child: SideNavigationRail(
                                    key: _sideNavKey,
                                    selectedTab: _currentTab,
                                    selectedLibraryKey: _selectedLibraryGlobalKey,
                                    isOfflineMode: _isOffline,
                                    isSidebarFocused: _isSidebarFocused,
                                    alwaysExpanded: alwaysExpanded,
                                    isReconnecting: _isReconnecting,
                                    onInteractionExpandedChanged: _handleSidebarInteractionExpandedChanged,
                                    onDestinationSelected: (tab) {
                                      final restorePreviousFocus = tab == _currentTab;
                                      _selectTab(tab);
                                      _focusContent(restorePreviousFocus: restorePreviousFocus);
                                    },
                                    onLibrarySelected: (key) {
                                      _selectLibrary(key);
                                      _focusContent(restorePreviousFocus: false);
                                    },
                                    onNavigateToContent: _focusContent,
                                    onReconnect: _triggerReconnect,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          );
        },
      );
    }

    return OverlaySheetHost(
      onOpenChanged: _handleOverlaySheetOpenChanged,
      // Host owns sheet + system back; onSystemBack mirrors the old PopScope
      // (go to home tab, then press-back-twice to exit).
      canPop: false,
      onSystemBack: () {
        if (BackKeyCoordinator.consumeIfHandled()) return;
        _handleMainBack();
      },
      child: ScaffoldMessenger(
        key: ProfileNavigationScope.of(context).mainScaffoldMessengerKey,
        child: Scaffold(
          body: _buildTickerAwareStack(),
          bottomNavigationBar: Column(
            mainAxisSize: .min,
            children: [
              // Reconnect bar when offline
              if (_isOffline)
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: InkWell(
                    onTap: _isReconnecting ? null : _triggerReconnect,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        mainAxisAlignment: .center,
                        children: [
                          if (_isReconnecting)
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            )
                          else
                            Icon(Symbols.wifi_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            t.common.reconnect,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: .w500,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              SettingValueBuilder<bool>(
                pref: SettingsService.showNavBarLabels,
                builder: (context, showNavBarLabels, _) {
                  final hideLabels = !showNavBarLabels;
                  return NavigationBarTheme(
                    data: NavigationBarTheme.of(context).copyWith(height: hideLabels ? 56 : null),
                    child: _buildBottomNavigationBar(context, hideLabels: hideLabels),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
