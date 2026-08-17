import 'package:flutter/material.dart';
import 'package:pleya/widgets/app_icon.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.g.dart';
import '../profiles/active_profile_provider.dart';
import '../profiles/profile_avatar.dart';
import '../theme/mono_theme.dart';
import '../utils/platform_detector.dart';

/// Bottom-nav icon with a red→amber brand dot above the active tab,
/// mirroring the navigation mockup. The dot slot is always reserved so
/// selected and unselected icons stay vertically aligned.
class _TabIcon extends StatelessWidget {
  final IconData icon;
  final String? svgAsset;
  final bool selected;

  /// Replaces the glyph without touching the dot or the alignment above it.
  /// My Pleya uses it to show the active profile's avatar.
  final Widget? glyph;

  const _TabIcon({required this.icon, this.svgAsset, required this.selected, this.glyph});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      children: [
        Container(
          width: 5,
          height: 5,
          margin: const EdgeInsets.only(bottom: 3),
          decoration: selected
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [kAccent, kAccentAlt]),
                  boxShadow: [BoxShadow(color: kAccent.withValues(alpha: 0.9), blurRadius: 8)],
                )
              : null,
        ),
        glyph ?? NavGlyph(svgAsset: svgAsset, icon: icon, size: 24),
      ],
    );
  }
}

/// The My Pleya slot's icon: the active profile's avatar, the same one the
/// desktop and TV header still show, at nav size.
///
/// Watches [ActiveProfileProvider] itself instead of letting the whole
/// navigation bar watch it, so switching profiles repaints one icon rather
/// than rebuilding every destination. Without a resolved profile it falls back
/// to the tab's own glyph, which is what the bar shows during startup binding.
///
/// The avatar carries no semantics of its own: the destination's label already
/// announces "My Pleya", and an image announcing a second time would only get
/// in the way. The PIN badge is dropped too: at 24 logical pixels it is three
/// pixels of noise under a selection dot, and the lock still shows everywhere
/// the profile is actually chosen.
class MyPleyaTabIcon extends StatelessWidget {
  final bool selected;

  const MyPleyaTabIcon({super.key, required this.selected});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ActiveProfileProvider?>()?.active;
    return _TabIcon(
      icon: Symbols.account_circle_rounded,
      selected: selected,
      glyph: profile == null
          ? null
          : ExcludeSemantics(child: ProfileAvatar(profile: profile, size: 24, showLockBadge: false)),
    );
  }
}

/// Whether the Home header still carries the account menu behind the avatar.
///
/// The counterpart of the `isMobile` gate on [NavigationTabId.myPleya] in
/// [NavigationTab.getVisibleTabs], and deliberately the same input: profiles,
/// settings and sign out belong in exactly one place per platform. Mobile has
/// My Pleya in the bottom bar and drops the header menu; desktop and TV have a
/// sidebar with no room for a personal hub, so they keep it.
///
/// A single predicate rather than two conditions that happen to agree, because
/// disagreeing would mean either a duplicate account menu or no way to sign out
/// at all.
bool showsHeaderAccountMenu({required bool isMobile}) => !isMobile;

/// Navigation tab identifiers.
///
/// Order here is not the display order (that is [allNavigationTabs]) and the
/// enum position is not persisted either: `EnumPref` serialises on `.name`, so
/// inserting a value cannot shift a stored `startup_section`.
enum NavigationTabId { discover, libraries, liveTv, search, watchlist, requests, downloads, settings, myPleya }

/// Represents a navigation tab with its configuration
class NavigationTab {
  final NavigationTabId id;
  final bool onlineOnly;
  final IconData icon;

  /// Solid mockup nav glyph; falls back to [icon] when null.
  final String? svgAsset;
  final String Function() getLabel;

  const NavigationTab({
    required this.id,
    required this.onlineOnly,
    required this.icon,
    this.svgAsset,
    required this.getLabel,
  });

  NavigationDestination toDestination() {
    // My Pleya is the one slot whose icon is state, not a constant: it shows
    // whoever is signed in. Resolved here rather than at the call site so
    // every bar that renders this tab gets the same treatment.
    if (id == NavigationTabId.myPleya) {
      return NavigationDestination(
        icon: const MyPleyaTabIcon(selected: false),
        selectedIcon: const MyPleyaTabIcon(selected: true),
        label: getLabel(),
      );
    }
    return NavigationDestination(
      icon: _TabIcon(icon: icon, svgAsset: svgAsset, selected: false),
      selectedIcon: _TabIcon(icon: icon, svgAsset: svgAsset, selected: true),
      label: getLabel(),
    );
  }

  /// Get the index for a tab ID in the visible tabs list
  static int indexFor(
    NavigationTabId id, {
    required bool isOffline,
    bool hasLiveTv = false,
    bool hasSeerr = false,
    bool hasWatchlist = false,
    bool isMobile = false,
  }) {
    final tabs = getVisibleTabs(
      isOffline: isOffline,
      hasLiveTv: hasLiveTv,
      hasSeerr: hasSeerr,
      hasWatchlist: hasWatchlist,
      isMobile: isMobile,
    );
    return tabs.indexWhere((tab) => tab.id == id);
  }

  /// Get tabs filtered by offline mode and feature availability.
  ///
  /// [isMobile] gates My Pleya, which exists only on phones. It is an answer
  /// to a five-slot bottom bar, not a new information architecture: the
  /// sidebar has room for Downloads, Requests and Settings as first-class
  /// destinations and keeps them.
  static List<NavigationTab> getVisibleTabs({
    required bool isOffline,
    bool hasLiveTv = false,
    bool hasSeerr = false,
    bool hasWatchlist = false,
    bool isMobile = false,
  }) {
    return allNavigationTabs.where((tab) {
      if (isOffline && tab.onlineOnly) return false;
      if (tab.id == NavigationTabId.liveTv && !hasLiveTv) return false;
      if (tab.id == NavigationTabId.requests && !hasSeerr) return false;
      if (tab.id == NavigationTabId.watchlist && !hasWatchlist) return false;
      if (tab.id == NavigationTabId.myPleya && !isMobile) return false;
      if (tab.id == NavigationTabId.downloads && PlatformDetector.isAppleTV()) return false;
      return true;
    }).toList();
  }

  /// Resolve which tab the app should open to on launch.
  ///
  /// Offline mode prefers Downloads when available. Online, honours the user's
  /// [preferredStartup] section when it is currently visible, otherwise falls
  /// back to the first visible tab (Home).
  static NavigationTabId resolveDefaultTab({
    required bool isOffline,
    required bool hasLiveTv,
    bool hasSeerr = false,
    bool hasWatchlist = false,
    bool isMobile = false,
    required NavigationTabId? preferredStartup,
  }) {
    final tabs = getVisibleTabs(
      isOffline: isOffline,
      hasLiveTv: hasLiveTv,
      hasSeerr: hasSeerr,
      hasWatchlist: hasWatchlist,
      isMobile: isMobile,
    );
    if (isOffline && tabs.any((t) => t.id == NavigationTabId.downloads)) {
      return NavigationTabId.downloads;
    }
    if (preferredStartup != null && tabs.any((t) => t.id == preferredStartup)) {
      return preferredStartup;
    }
    return tabs.first.id;
  }
}

// Label getters (must be top-level for const constructor)
String _getHomeLabel() => t.common.home;
String _getLibrariesLabel() => t.navigation.libraries;
String _getLiveTvLabel() => t.navigation.liveTv;
String _getSearchLabel() => t.common.search;
String _getRequestsLabel() => t.seerr.title;
String _getDownloadsLabel() => t.navigation.downloads;
String _getSettingsLabel() => t.common.settings;
String _getWatchlistLabel() => t.navigation.watchlist;
String _getMyPleyaLabel() => t.navigation.myPleya;

/// Solid nav glyphs from the sidebar-v2 mockup.
class NavGlyphs {
  static const home = 'assets/icons/nav/home.svg';
  static const library = 'assets/icons/nav/library.svg';
  static const liveTv = 'assets/icons/nav/live_tv.svg';
  static const search = 'assets/icons/nav/search.svg';
  static const requests = 'assets/icons/nav/requests.svg';
  static const downloads = 'assets/icons/nav/downloads.svg';
  static const settings = 'assets/icons/nav/settings.svg';
  static const watchlist = 'assets/icons/nav/watchlist.svg';

  // Library-row glyphs (same solid style, one icon language across the rail).
  static const libMovie = 'assets/icons/nav/movie.svg';
  static const libShow = 'assets/icons/nav/show.svg';
  static const libMusic = 'assets/icons/nav/music.svg';
  static const libPhoto = 'assets/icons/nav/photo.svg';
  static const libMixed = 'assets/icons/nav/mixed.svg';
  static const libFolder = 'assets/icons/nav/folder.svg';
}

/// All navigation tabs in display order
const allNavigationTabs = [
  NavigationTab(
    id: NavigationTabId.discover,
    onlineOnly: true,
    icon: Symbols.home_rounded,
    svgAsset: NavGlyphs.home,
    getLabel: _getHomeLabel,
  ),
  NavigationTab(
    id: NavigationTabId.libraries,
    onlineOnly: true,
    icon: Symbols.video_library_rounded,
    svgAsset: NavGlyphs.library,
    getLabel: _getLibrariesLabel,
  ),
  NavigationTab(
    id: NavigationTabId.liveTv,
    onlineOnly: true,
    icon: Symbols.live_tv_rounded,
    svgAsset: NavGlyphs.liveTv,
    getLabel: _getLiveTvLabel,
  ),
  NavigationTab(
    id: NavigationTabId.search,
    onlineOnly: true,
    icon: Symbols.search_rounded,
    svgAsset: NavGlyphs.search,
    getLabel: _getSearchLabel,
  ),
  NavigationTab(
    id: NavigationTabId.watchlist,
    onlineOnly: false,
    icon: Symbols.bookmark_add_rounded,
    svgAsset: NavGlyphs.watchlist,
    getLabel: _getWatchlistLabel,
  ),
  NavigationTab(
    id: NavigationTabId.requests,
    onlineOnly: true,
    icon: Symbols.playlist_add_rounded,
    svgAsset: NavGlyphs.requests,
    getLabel: _getRequestsLabel,
  ),
  NavigationTab(
    id: NavigationTabId.downloads,
    onlineOnly: false,
    icon: Symbols.download_rounded,
    svgAsset: NavGlyphs.downloads,
    getLabel: _getDownloadsLabel,
  ),
  NavigationTab(
    id: NavigationTabId.settings,
    onlineOnly: false,
    icon: Symbols.settings_rounded,
    svgAsset: NavGlyphs.settings,
    getLabel: _getSettingsLabel,
  ),
  // Last, because it is the mobile bar's rightmost slot. Its icon is the
  // profile avatar rather than this glyph (see [MyPleyaTabIcon]); the fallback
  // below only shows before a profile is resolved.
  NavigationTab(
    id: NavigationTabId.myPleya,
    onlineOnly: false,
    icon: Symbols.account_circle_rounded,
    getLabel: _getMyPleyaLabel,
  ),
];
