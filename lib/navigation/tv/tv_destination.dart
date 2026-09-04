/// The TV root shell's destinations (hoofdstuk 6.1 and 6.2 of
/// docs/tvos-unified-experience.md).
///
/// Fase 7 replaces the vertical [SideNavigationRail] on TV with a horizontal
/// top navigation. The route catalogue itself does not move: a destination
/// still resolves to a [NavigationTabId], so the screens list, the tab state
/// and every deep link keep working. What changes is which destinations a TV
/// shows, in which order, and that four of the rail's rows (Libraries,
/// Watchlist, Requests, Settings) become routes *inside* Mijn Pleya instead of
/// siblings of Home.
///
/// The order here is the visual order and it is decided, not derived:
/// profile · Search · Home · Series · Films · [Live TV] · Mijn Pleya · wordmark
/// ([DEC-064], hoofdstuk 33's shared shell). Series sits before Films; the
/// rail's historical Films-then-Series order does not carry over.
library;

import '../../i18n/strings.g.dart';
import '../navigation_tabs.dart';

/// One destination in the TV top navigation.
///
/// Search is a destination and not a free-floating action: it owns a surface,
/// it can be active, and Left/Right has to be able to land on it. Hoofdstuk 33
/// draws it as a compact icon rather than a labelled pill, which is a
/// presentation difference ([TvDestination.isCompact]) and not a different kind
/// of thing.
enum TvDestinationId {
  search,
  home,
  series,
  movies,
  liveTv,
  myPleya;

  /// The route this destination selects.
  ///
  /// Every TV destination maps onto an existing tab, which is what keeps fase 7
  /// a presentation change: `MainScreen` keeps one screens list, one
  /// `_currentTab`, and one `_selectTab`.
  NavigationTabId get tab => switch (this) {
    TvDestinationId.search => NavigationTabId.search,
    TvDestinationId.home => NavigationTabId.discover,
    TvDestinationId.series => NavigationTabId.series,
    TvDestinationId.movies => NavigationTabId.movies,
    TvDestinationId.liveTv => NavigationTabId.liveTv,
    TvDestinationId.myPleya => NavigationTabId.myPleya,
  };

  /// Drawn as an icon-only control rather than a labelled pill (hoofdstuk 33:
  /// "Search = compact icon/control").
  bool get isCompact => this == TvDestinationId.search;

  /// A stable focus key. Deliberately the enum name and not an index: a
  /// conditional Live TV slot appearing or disappearing must not renumber the
  /// keys of its neighbours, or focus memory would silently point at a
  /// different destination than it was stored for (hoofdstuk 7.2, last bullet).
  String get focusKey => 'tvNav_$name';

  String get label => switch (this) {
    TvDestinationId.search => _searchLabel(),
    TvDestinationId.home => _homeLabel(),
    TvDestinationId.series => _seriesLabel(),
    TvDestinationId.movies => _moviesLabel(),
    TvDestinationId.liveTv => _liveTvLabel(),
    TvDestinationId.myPleya => _myPleyaLabel(),
  };
}

/// What the shell knows about the profile, its servers and the platform.
///
/// A value type with a pure builder over it, for the same reason
/// [NavRailConditions] is one: the destination list is what the whole focus
/// contract is indexed by, so it has to be testable without mounting a shell.
class TvNavConditions {
  const TvNavConditions({required this.hasLiveTv});

  /// Whether this profile has Live TV.
  ///
  /// This is the *capability*, not the current reachability of a tuner.
  /// Hoofdstuk 19 is explicit: "Bekende Live TV-capability wordt per profiel
  /// onthouden, zodat het navigatie-item niet bij iedere tijdelijke netwerkdip
  /// verdwijnt." Feeding a raw availability poll in here would make every
  /// sibling destination jump sideways whenever a DVR blinks, which is the
  /// failure this parameter's name is chosen to prevent.
  final bool hasLiveTv;
}

/// The TV top navigation's destinations, left to right.
///
/// Pure, so the ordering and the conditional slot can be tested on their own.
/// Mijn Pleya is unconditional (hoofdstuk 18.3: "Mijn Pleya zelf verdwijnt
/// nooit") — it is the only route to Settings, Servers and Sign out on TV, so a
/// condition that could hide it would be a condition that could strand someone.
List<TvDestinationId> buildTvDestinations(TvNavConditions c) => [
  TvDestinationId.search,
  TvDestinationId.home,
  TvDestinationId.series,
  TvDestinationId.movies,
  if (c.hasLiveTv) TvDestinationId.liveTv,
  TvDestinationId.myPleya,
];

/// The destination the root Back/Menu contract treats as home (hoofdstuk 7.5
/// step 5). Not `destinations.first` — that is Search.
const TvDestinationId tvRootDestination = TvDestinationId.home;

/// Which destination a [NavigationTabId] shows as active.
///
/// The tab can be something the top navigation has no pill for: Settings,
/// Watchlist, Requests and Libraries are Mijn Pleya's nested routes on TV
/// (hoofdstuk 18.2), and Downloads is reachable from there too. They light up
/// Mijn Pleya rather than nothing, so the bar never claims you are nowhere.
/// Returns null only for a tab no TV shell can reach.
TvDestinationId? tvDestinationForTab(NavigationTabId tab) => switch (tab) {
  NavigationTabId.search => TvDestinationId.search,
  NavigationTabId.discover => TvDestinationId.home,
  NavigationTabId.series => TvDestinationId.series,
  NavigationTabId.movies => TvDestinationId.movies,
  NavigationTabId.liveTv => TvDestinationId.liveTv,
  NavigationTabId.myPleya ||
  NavigationTabId.libraries ||
  NavigationTabId.watchlist ||
  NavigationTabId.requests ||
  NavigationTabId.downloads ||
  NavigationTabId.settings => TvDestinationId.myPleya,
};

// Label getters stay top-level so [TvDestinationId] keeps const-friendly
// members, matching how navigation_tabs.dart resolves its labels.
String _searchLabel() => t.common.search;
String _homeLabel() => t.common.home;
String _seriesLabel() => t.unifiedCatalog.seriesTitle;
String _moviesLabel() => t.unifiedCatalog.moviesTitle;
String _liveTvLabel() => t.navigation.liveTv;
String _myPleyaLabel() => t.navigation.myPleya;
