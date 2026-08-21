import '../../navigation/navigation_tabs.dart';

/// Where a destination is drawn, which decides who renders it.
enum NavRailSlot {
  /// A single row inside the scrolling list.
  list,

  /// The library block: one entry that expands into many rows, each with its
  /// own focus key. It owns no focus key of its own.
  libraries,

  /// Pinned below the list, outside the scroll area.
  footer,
}

/// Every place the side rail can take you, in one enum with a stable identity.
///
/// The rail used to hand-write its fixed rows three times: once to render them,
/// once to whitelist their focus nodes, once to order them for the D-pad. The
/// "now watching" row was added to the first list only, so it was painted while
/// its focus node was disposed on every rebuild and the up/down walk skipped
/// straight over it. On a TV that is an item you can see and can never reach.
///
/// So identity lives here and order lives in [buildNavRailDestinations], and
/// everything else is derived: the rows, the focus keys, the traversal order,
/// the activation. Adding a destination means adding an enum value, which the
/// exhaustive switches in the rail refuse to compile without.
enum NavRailDestination {
  reconnect(ownFocusKey: 'reconnect'),
  home(ownFocusKey: 'home', tab: NavigationTabId.discover),
  libraries(slot: NavRailSlot.libraries),
  liveTv(ownFocusKey: 'liveTv', tab: NavigationTabId.liveTv),
  search(ownFocusKey: 'search', tab: NavigationTabId.search),
  watchlist(ownFocusKey: 'watchlist', tab: NavigationTabId.watchlist),
  requests(ownFocusKey: 'requests', tab: NavigationTabId.requests),
  nowWatching(ownFocusKey: 'nowWatching'),
  downloads(ownFocusKey: 'downloads', tab: NavigationTabId.downloads),
  settings(ownFocusKey: 'settings', tab: NavigationTabId.settings),
  fullscreen(ownFocusKey: 'fullscreen', slot: NavRailSlot.footer);

  const NavRailDestination({this.ownFocusKey, this.slot = NavRailSlot.list, this.tab});

  /// The focus key for this destination, or null when it expands into rows that
  /// carry their own keys ([NavRailSlot.libraries]).
  final String? ownFocusKey;

  final NavRailSlot slot;

  /// The tab this destination selects, or null when it opens a route instead
  /// (now watching) or toggles something (fullscreen, reconnect).
  final NavigationTabId? tab;
}

/// What the rail knows about the current profile, server and platform.
class NavRailConditions {
  const NavRailConditions({
    required this.isOfflineMode,
    required this.canReconnect,
    required this.hasLiveTv,
    required this.hasSeerr,
    required this.hasWatchlist,
    required this.showNowWatching,
    required this.showDownloads,
    required this.showFullscreenToggle,
  });

  final bool isOfflineMode;
  final bool canReconnect;
  final bool hasLiveTv;
  final bool hasSeerr;
  final bool hasWatchlist;
  final bool showNowWatching;
  final bool showDownloads;
  final bool showFullscreenToggle;
}

/// The rail's destinations in visual top-to-bottom order.
///
/// "Now watching" sits last in the online group on purpose: it comes and goes
/// with the streams, and an entry that appeared above the fixed rows would
/// shift them under someone's thumb every time a film starts.
List<NavRailDestination> buildNavRailDestinations(NavRailConditions c) => [
  if (c.isOfflineMode && c.canReconnect) NavRailDestination.reconnect,
  if (!c.isOfflineMode) ...[
    NavRailDestination.home,
    NavRailDestination.libraries,
    if (c.hasLiveTv) NavRailDestination.liveTv,
    NavRailDestination.search,
    if (c.hasWatchlist) NavRailDestination.watchlist,
    if (c.hasSeerr) NavRailDestination.requests,
    if (c.showNowWatching) NavRailDestination.nowWatching,
  ],
  if (c.showDownloads) NavRailDestination.downloads,
  NavRailDestination.settings,
  if (c.showFullscreenToggle) NavRailDestination.fullscreen,
];
