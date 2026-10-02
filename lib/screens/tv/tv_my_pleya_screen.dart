/// Mijn Pleya on TV — the personal hub (hoofdstuk 18 of
/// docs/tvos-unified-experience.md, north star 08).
///
/// The mobile [MyPleyaScreen] says in its own doc comment that TV does not use
/// it, and that stays true: a phone list scaled up is not a 10-foot surface.
/// [DEC-063] replaces the TV half of [DEC-023] with this screen; mobile and
/// desktop are untouched.
///
/// **Every tile opens something that already exists.** Fase 7 builds no new
/// features here. Each tile is a route into a screen this app already shipped —
/// Watchlist, Requests, Downloads, Libraries, Connections, Now Watching,
/// Settings, Logs, About — and the two actions (switch profile, sign out) call
/// the same `AccountUiActions` the other shells call. A tile with nothing real
/// behind it would be worse than a missing tile, so conditional tiles simply
/// close up (hoofdstuk 18.3, 33.8) rather than render disabled.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/focus_memory_tracker.dart';
import '../../focus/focus_theme.dart';
import '../../utils/tv_hig.dart';
import '../../widgets/big_p/big_p_avatar.dart';
import '../../focus/focusable_wrapper.dart';
import '../../assistant/assistant_controller.dart';
import '../../automation/automation_ids.dart';
import '../../automation/automation_screen.dart';
import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../mixins/refreshable.dart';
import '../../profiles/active_profile_provider.dart';
import '../../profiles/profile.dart';
import '../../profiles/profile_avatar.dart';
import '../../providers/download_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../providers/now_watching_provider.dart';
import '../../providers/personal_media_provider.dart';
import '../../providers/seerr_provider.dart';
import '../../providers/watchlist_provider.dart';
import '../../theme/mono_theme.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/tv/tv_unified_layout.dart';
import 'tv_my_pleya_sections.dart';

part 'tv_my_pleya_header.dart';
part 'tv_my_pleya_tiles.dart';

/// One tile in a group.
class TvMyPleyaTile {
  const TvMyPleyaTile({
    required this.section,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.count,
  });

  /// What the tile opens. Null for [TvMyPleyaAction] tiles, which act instead
  /// of navigating — sign out is the only one.
  final TvMyPleyaSection? section;

  final IconData icon;
  final String title;
  final String subtitle;

  /// Rendered top-right when non-null. Deliberately nullable rather than
  /// defaulting to zero: a tile reading "0" is a tile that should not carry a
  /// count at all.
  final int? count;

  String get focusKey => 'tvMyPleya_${section?.name ?? 'logout'}';
}

/// A group of tiles under one heading.
class TvMyPleyaGroup {
  const TvMyPleyaGroup({required this.label, required this.tiles});
  final String label;
  final List<TvMyPleyaTile> tiles;
}

/// The hub's groups for the given conditions.
///
/// Pure, and separate from the widget, because *which* tiles exist is the
/// hoofdstuk 18.2 function mapping — the thing that has to be checked against
/// the roadmap rather than read off a build method.
List<TvMyPleyaGroup> buildTvMyPleyaGroups({
  required bool hasWatchlist,
  required bool hasSeerr,
  required bool showDownloads,
  required bool showActivity,
  required bool showCollections,
  required bool showPlaylists,
  bool showAssistant = false,
  int? watchlistCount,
  int? downloadCount,
  int? collectionCount,
  int? playlistCount,
}) {
  // A tile reading "0" is a tile that should not carry a count at all, so the
  // rule lives here rather than at the call site — one place, and the same
  // answer for every caller.
  int? shown(int? value) => (value == null || value == 0) ? null : value;
  final watchlist = shown(watchlistCount);
  final downloads = shown(downloadCount);
  return [
    TvMyPleyaGroup(
      label: t.tvMyPleya.groupContent,
      tiles: [
        if (hasWatchlist)
          TvMyPleyaTile(
            section: TvMyPleyaSection.watchlist,
            icon: Symbols.bookmark_rounded,
            title: t.watchlist.title,
            subtitle: t.tvMyPleya.watchlistSubtitle,
            count: watchlist,
          ),
        if (showCollections)
          TvMyPleyaTile(
            section: TvMyPleyaSection.collections,
            icon: Symbols.collections_bookmark_rounded,
            title: t.collections.title,
            subtitle: t.tvMyPleya.collectionsSubtitle,
            count: shown(collectionCount),
          ),
        if (showPlaylists)
          TvMyPleyaTile(
            section: TvMyPleyaSection.playlists,
            icon: Symbols.playlist_play_rounded,
            title: t.playlists.title,
            subtitle: t.tvMyPleya.playlistsSubtitle,
            count: shown(playlistCount),
          ),
        if (hasSeerr)
          TvMyPleyaTile(
            section: TvMyPleyaSection.requests,
            icon: Symbols.add_circle_rounded,
            title: t.seerr.title,
            subtitle: t.tvMyPleya.requestsSubtitle,
          ),
        if (showDownloads)
          TvMyPleyaTile(
            section: TvMyPleyaSection.downloads,
            icon: Symbols.download_rounded,
            title: t.navigation.downloads,
            subtitle: t.tvMyPleya.downloadsSubtitle,
            count: downloads,
          ),
      ],
    ),
    TvMyPleyaGroup(
      label: t.tvMyPleya.groupSources,
      tiles: [
        TvMyPleyaTile(
          section: TvMyPleyaSection.libraries,
          icon: Symbols.folder_rounded,
          // The screen's name, not the rail's short label. In Dutch the two
          // differ — "Bibliotheken" against "Media" — and the audit of
          // 2 September 2026 counted that as one of three names on one place.
          title: t.libraries.title,
          subtitle: t.tvMyPleya.libraryManagementSubtitle,
        ),
        TvMyPleyaTile(
          section: TvMyPleyaSection.servers,
          icon: Symbols.dns_rounded,
          title: t.tvMyPleya.servers,
          subtitle: t.tvMyPleya.serversSubtitle,
        ),
        if (showActivity)
          TvMyPleyaTile(
            section: TvMyPleyaSection.activity,
            icon: Symbols.monitor_heart_rounded,
            title: t.tvMyPleya.activity,
            subtitle: t.tvMyPleya.activitySubtitle,
          ),
        // Fase 8: this used to hang off the Home billboard's overlaid action
        // bar, which the rounded in-page hero replaced. See
        // `TvMyPleyaSection.watchTogether` for why it landed here rather than
        // being dropped with the bar — and why Pleya Remote did not follow it.
        TvMyPleyaTile(
          section: TvMyPleyaSection.watchTogether,
          icon: Symbols.group_rounded,
          title: t.watchTogether.title,
          subtitle: t.tvMyPleya.watchTogetherSubtitle,
        ),
      ],
    ),
    TvMyPleyaGroup(
      label: t.tvMyPleya.groupPleya,
      tiles: [
        // Mockup 38 A: first in the group, a regular tile that carries Big P's
        // portrait instead of a line icon (see `_Tile`).
        if (showAssistant)
          TvMyPleyaTile(
            section: TvMyPleyaSection.assistant,
            icon: Symbols.smart_toy_rounded,
            title: t.assistant.tileTitle,
            subtitle: t.assistant.tileSubtitle,
          ),
        TvMyPleyaTile(
          section: TvMyPleyaSection.settings,
          icon: Symbols.settings_rounded,
          title: t.settings.title,
          subtitle: t.tvMyPleya.settingsSubtitle,
        ),
        TvMyPleyaTile(
          section: TvMyPleyaSection.logs,
          icon: Symbols.description_rounded,
          title: t.tvMyPleya.logs,
          subtitle: t.tvMyPleya.logsSubtitle,
        ),
        TvMyPleyaTile(
          section: TvMyPleyaSection.about,
          icon: Symbols.info_rounded,
          title: t.about.title,
          subtitle: t.tvMyPleya.aboutSubtitle,
        ),
        TvMyPleyaTile(
          section: null,
          icon: Symbols.logout_rounded,
          title: t.common.logout,
          subtitle: t.tvMyPleya.logoutSubtitle,
        ),
      ],
    ),
  ].where((group) => group.tiles.isNotEmpty).toList();
}

class TvMyPleyaScreen extends StatefulWidget {
  const TvMyPleyaScreen({
    super.key,
    required this.onOpenSection,
    required this.onSwitchProfile,
    required this.onSignOut,
    required this.onExitUp,
  });

  final ValueChanged<TvMyPleyaSection> onOpenSection;
  final VoidCallback onSwitchProfile;
  final VoidCallback onSignOut;

  /// UP out of the top row, back to the top navigation (hoofdstuk 7.5 step 4).
  final VoidCallback onExitUp;

  @override
  State<TvMyPleyaScreen> createState() => TvMyPleyaScreenState();
}

class TvMyPleyaScreenState extends State<TvMyPleyaScreen> implements FocusableTab {
  /// The sections that have a tile as of the last build. OFF6: the shell
  /// asks this after a rebind, to close a section that no longer exists.
  Set<TvMyPleyaSection> get availableSections => _availableSections;
  Set<TvMyPleyaSection> _availableSections = const {};

  /// Owned by the state, not rebuilt per frame: a watchlist count arriving or a
  /// server going offline must not dispose the node the remote is standing on.
  final FocusMemoryTracker nodes = FocusMemoryTracker(debugLabelPrefix: 'tvMyPleya');

  String? _appVersion;

  @override
  void initState() {
    super.initState();
    unawaited(_loadVersion());
    // Big P's tile depends on entitlement, servers and the provider config;
    // the controller computes that only when an entry point asks.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(context.read<AssistantController?>()?.refreshAvailability());
    });
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersion = info.version);
    } catch (_) {
      // A missing version leaves the footer as "Signed in as Michel · Pleya",
      // which is worth strictly more than an error state on a hub screen.
    }
  }

  @override
  void dispose() {
    nodes.dispose();
    super.dispose();
  }

  /// DOWN out of the top navigation. Restores the last position on this hub
  /// where there is one, so leaving Mijn Pleya and coming back does not reset
  /// the remote to the first tile (hoofdstuk 7.6).
  @override
  void focusActiveTabIfReady() => focusKey(nodes.lastFocusedKey ?? _switchProfileKey);

  /// Puts the focus on [key] if it can take it. Public so the shell can restore
  /// the tile a nested section was opened from.
  void focusKey(String? key) {
    if (key == null) return;
    final node = nodes.get(key);
    if (node.canRequestFocus) node.requestFocus();
  }

  String? get appVersion => _appVersion;

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final tk = tokens(context);
    final profile = context.watch<ActiveProfileProvider?>()?.active;
    final servers = context.watch<MultiServerProvider>();
    final watchlist = context.watch<WatchlistProvider?>();
    final downloads = context.watch<DownloadProvider?>();
    final personalMedia = context.watch<PersonalMediaProvider?>();

    final groups = buildTvMyPleyaGroups(
      hasWatchlist: watchlist?.hasWatchlist ?? false,
      hasSeerr: context.watch<SeerrProvider?>()?.isConfigured ?? false,
      // Hoofdstuk 18.3: Downloads never appears on Apple TV. The same predicate
      // `NavigationTab.getVisibleTabs` uses, so the tile and the tab cannot
      // disagree about whether the feature exists on this device.
      showDownloads: !PlatformDetector.isAppleTV(),
      // PB-7: capability and data availability decide this now, not merely
      // "a concrete PlexClient exists". Tautulli Now Watching is the one
      // supported source today; Watch Together and Pleya Remote are separate
      // product concepts and stay out (docs/tvos-redesign-implementatiecontract.md).
      showActivity: context.watch<NowWatchingProvider?>()?.isAvailable ?? false,
      showCollections: personalMedia?.supportsCollections ?? false,
      showPlaylists: personalMedia?.supportsPlaylists ?? false,
      showAssistant:
          (context.watch<AssistantController?>()?.availability ?? AssistantAvailability.hidden) !=
          AssistantAvailability.hidden,
      watchlistCount: watchlist?.entriesByRecentlyAdded.length,
      downloadCount: downloads == null ? null : downloads.downloadedMovies.length + downloads.downloadedShows.length,
      collectionCount: personalMedia?.state == PersonalMediaLoadState.loaded ? personalMedia?.collections.length : null,
      playlistCount: personalMedia?.state == PersonalMediaLoadState.loaded ? personalMedia?.playlists.length : null,
    );

    _availableSections = {
      for (final group in groups)
        for (final tile in group.tiles)
          if (tile.section case final section?) section,
    };

    // A flat, ordered list of every focusable key on the page, so UP out of the
    // first row and the tile-to-tile walk are derived from one sequence rather
    // than from three nested loops that could disagree at a group boundary.
    final keys = [_switchProfileKey, for (final group in groups) ...group.tiles.map((tile) => tile.focusKey)];

    // Every tile spends [TvMyPleyaLayout.tileFocusRingGap] inside its own box
    // before its fill starts. Laying the page out on the plain inset therefore
    // put the tiles a few pixels right of the header card and the group labels
    // above them, and on a page whose whole composition is one left edge that
    // is the one element off it. So the page is inset by the gap less, and
    // everything that carries no focus ring of its own — the title, the header
    // card, the group labels, the footer — adds it back. Every tile fill and
    // every piece of text then starts on the same line.
    final ringGap = TvMyPleyaLayout.tileFocusRingGap * scale;
    final textInset = EdgeInsets.symmetric(horizontal: ringGap);

    // Its own screen id. `screen.main` is mounted for the entire session and
    // says nothing about which destination is showing, so without this the
    // hub is indistinguishable from every other page in `/v1/screens`.
    // Ready as soon as it builds: the tiles are derived from providers that
    // are already resolved by the time this runs, and a hub that renders is a
    // hub you can use.
    return AutomationScreen(
      id: AutomationIds.screenMyPleya,
      readiness: () => const AutomationReadiness.ready(),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: TvTopNavLayout.pageInset * scale - ringGap,
          right: TvTopNavLayout.pageInset * scale - ringGap,
          bottom: TvCatalogLayout.topSafeInset * scale,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: textInset,
              child: Text(
                t.navigation.myPleya,
                style: TextStyle(
                  color: tk.text,
                  fontSize: TvMyPleyaLayout.pageTitleFontSize * scale,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            SizedBox(height: TvMyPleyaLayout.titleGap * scale),
            Padding(
              padding: textInset,
              child: _ProfileHeader(
                profile: profile,
                servers: servers,
                scale: scale,
                node: nodes.get(_switchProfileKey, debugLabel: _switchProfileKey),
                onSwitchProfile: widget.onSwitchProfile,
                onExitUp: widget.onExitUp,
                onNavigateDown: () => focusKey(keys.length > 1 ? keys[1] : null),
              ),
            ),
            for (final group in groups) ...[
              SizedBox(height: TvMyPleyaLayout.groupGap * scale),
              Padding(
                padding: textInset,
                child: Text(
                  group.label,
                  style: TextStyle(
                    color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
                    fontSize: TvMyPleyaLayout.groupLabelFontSize * scale,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(height: TvMyPleyaLayout.groupLabelGap * scale),
              _TileRow(
                tiles: group.tiles,
                scale: scale,
                nodes: nodes,
                keys: keys,
                groups: groups,
                onFocusKey: focusKey,
                onOpen: (tile) => tile.section == null ? widget.onSignOut() : widget.onOpenSection(tile.section!),
              ),
            ],
            SizedBox(height: TvMyPleyaLayout.footerGap * scale),
            Padding(
              padding: textInset,
              child: Text(
                t.tvMyPleya.signedInAs(name: profile?.displayName ?? '', version: _appVersion ?? ''),
                style: TextStyle(
                  color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
                  fontSize: TvMyPleyaLayout.footerFontSize * scale,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const String _switchProfileKey = 'tvMyPleya_switchProfile';
