/// Mijn Pleya on TV, the personal hub, in the Editorial layout of A-24b
/// (northstar `docs/assets/a24b-northstars/02-Mijn-Pleya/images/01-tvos-landing.png`).
///
/// The mobile [MyPleyaScreen] is a phone list; this is the ten-foot page.
/// Both read the same function mapping ([buildTvMyPleyaGroups]) and the same
/// kijklijst and Big P pieces (`my_pleya_shared.dart`), so the two platforms
/// show the same destinations under the same names.
///
/// Composition: title, a profile line with `Profiel wisselen` and the
/// non-focusable server status, a hairline, then two columns. Left: the
/// kijklijst as a poster rail with `Bekijk alles`, Mijn content and
/// Bibliotheken en bronnen. Right, behind a vertical line: Pleya (the Big P
/// card) and Beheer (Instellingen, Logboeken, Over Pleya, Uitloggen).
///
/// **Every tile opens something that already exists.** Each tile is a route
/// into a screen this app already shipped, and the two actions (switch
/// profile, sign out) call the same `AccountUiActions` the other shells call.
/// Conditional tiles close up rather than render disabled (hoofdstuk 18.3,
/// 33.8); a group with nothing left disappears, and Beheer then sits directly
/// under Pleya (northstar 04).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../assistant/assistant_controller.dart';
import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../automation/automation_screen.dart';
import '../../focus/focus_memory_tracker.dart';
import '../../focus/focus_theme.dart';
import '../../focus/focusable_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/unified/source_row_descriptor.dart' show backendDisplayLabel;
import '../../media/watchlist_entry.dart';
import '../../mixins/refreshable.dart';
import '../../profiles/active_profile_provider.dart';
import '../../profiles/profile.dart';
import '../../profiles/profile_avatar.dart';
import '../../providers/download_provider.dart';
import '../../providers/libraries_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../providers/now_watching_provider.dart';
import '../../providers/personal_media_provider.dart';
import '../../providers/seerr_provider.dart';
import '../../providers/watchlist_provider.dart';
import '../../theme/mono_theme.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../utils/media_navigation_helper.dart';
import '../../utils/platform_detector.dart';
import '../../utils/tv_hig.dart';
import '../../widgets/tv/tv_unified_layout.dart';
import '../../widgets/tv/tv_catalog_card.dart';
import '../../widgets/tv/tv_watchlist_card.dart' show tvWatchlistSemanticLabel;
import '../my_pleya_shared.dart';
import 'tv_my_pleya_groups.dart';
import 'tv_my_pleya_sections.dart';

export 'tv_my_pleya_groups.dart';

part 'tv_my_pleya_big_p.dart';
part 'tv_my_pleya_focus.dart';
part 'tv_my_pleya_header.dart';
part 'tv_my_pleya_tiles.dart';
part 'tv_my_pleya_watchlist.dart';

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
  /// Kijklijst counts while the page offers it, as the rail's `Bekijk alles`.
  Set<TvMyPleyaSection> get availableSections => _availableSections;
  Set<TvMyPleyaSection> _availableSections = const {};

  /// Owned by the state, not rebuilt per frame: a watchlist count arriving or a
  /// server going offline must not dispose the node the remote is standing on.
  final FocusMemoryTracker nodes = FocusMemoryTracker(debugLabelPrefix: 'tvMyPleya');
  final Map<String, String> _cameFrom = {};

  String? _appVersion;

  @override
  void initState() {
    super.initState();
    unawaited(_loadVersion());
    // Big P's card depends on entitlement, servers and the provider config;
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
  void focusActiveTabIfReady() {
    final last = nodes.lastFocusedKey;
    if (last != null && nodes.nodeFor(last)?.context != null) {
      focusKey(last);
    } else {
      focusKey(_switchProfileKey);
    }
  }

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
    final pt = TvHig.of(context);
    final tk = tokens(context);
    final profile = context.watch<ActiveProfileProvider?>()?.active;
    final servers = context.watch<MultiServerProvider>();
    final watchlist = context.watch<WatchlistProvider?>();
    final downloads = context.watch<DownloadProvider?>();
    final personalMedia = context.watch<PersonalMediaProvider?>();
    final libraries = context.watch<LibrariesProvider?>();
    final personalLoaded = personalMedia?.state == PersonalMediaLoadState.loaded;

    final groups = buildTvMyPleyaGroups(
      hasWatchlist: watchlist?.hasWatchlist ?? false,
      hasSeerr: context.watch<SeerrProvider?>()?.isConfigured ?? false,
      // Hoofdstuk 18.3: Downloads never appears on Apple TV. The same predicate
      // `NavigationTab.getVisibleTabs` uses, so the tile and the tab cannot
      // disagree about whether the feature exists on this device.
      showDownloads: !PlatformDetector.isAppleTV(),
      // PB-7: Tautulli Now Watching is the one supported source today.
      showActivity: context.watch<NowWatchingProvider?>()?.isAvailable ?? false,
      showCollections: personalMedia?.supportsCollections ?? false,
      showPlaylists: personalMedia?.supportsPlaylists ?? false,
      showAssistant:
          (context.watch<AssistantController?>()?.availability ?? AssistantAvailability.hidden) !=
          AssistantAvailability.hidden,
      watchlistCount: watchlist?.entriesByRecentlyAdded.length,
      downloadCount: downloads == null ? null : downloads.downloadedMovies.length + downloads.downloadedShows.length,
      collectionCount: personalLoaded ? personalMedia?.collections.length : null,
      playlistCount: personalLoaded ? personalMedia?.playlists.length : null,
      libraryCount: libraries?.libraries.length,
      onlineServerCount: servers.onlineServerCount,
      totalServerCount: servers.totalServerCount,
    );

    _availableSections = {
      for (final group in groups)
        for (final tile in group.tiles) ?tile.section,
    };

    // The kijklijst is a rail with `Bekijk alles` here, not a tile.
    final leftGroups = [
      for (final group in groups)
        if (group.kind != TvMyPleyaGroupKind.pleya)
          TvMyPleyaGroup(
            kind: group.kind,
            label: group.label,
            tiles: group.tiles.where((tile) => tile.section != TvMyPleyaSection.watchlist).toList(),
          ),
    ].where((group) => group.tiles.isNotEmpty).toList();
    final pleyaTiles = groups.where((g) => g.kind == TvMyPleyaGroupKind.pleya).expand((g) => g.tiles).toList();
    final bigP = pleyaTiles.where((tile) => tile.section == TvMyPleyaSection.assistant).firstOrNull;
    final manageTiles = pleyaTiles.where((tile) => tile.section != TvMyPleyaSection.assistant).toList();
    final entries = watchlist != null && watchlist.hasWatchlist ? myPleyaWatchlistEntries(watchlist) : null;

    final map = _HubFocusMap(
      nodes: nodes,
      railKeys: [
        if (entries != null) ...[for (final entry in entries) _posterKey(entry), _seeAllKey],
      ],
      tileRows: [
        for (final group in leftGroups)
          for (final row in _rowsOf(group.tiles)) [for (final tile in row) tile.focusKey],
      ],
      rightKeys: [?bigP?.focusKey, for (final tile in manageTiles) tile.focusKey],
      cameFrom: _cameFrom,
    );

    void open(TvMyPleyaTile tile) => tile.section == null ? widget.onSignOut() : widget.onOpenSection(tile.section!);

    // The page is inset by the ring gap less, and everything that carries no
    // focus ring of its own adds it back, so every tile fill and every piece
    // of text starts on the same line.
    final ringGap = TvMyPleyaLayout.tileFocusRingGap * scale;
    final textInset = EdgeInsets.symmetric(horizontal: ringGap);

    final leftColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (entries != null && watchlist != null)
          _WatchlistBlock(
            entries: entries,
            provider: watchlist,
            map: map,
            seeAllNode: nodes.get(_seeAllKey, debugLabel: _seeAllKey),
            onOpenAll: () => widget.onOpenSection(TvMyPleyaSection.watchlist),
          ),
        for (final (index, group) in leftGroups.indexed) ...[
          if (index > 0 || entries != null) SizedBox(height: kTvMyPleyaGroupGapPt * pt),
          _GroupLabel(group.label),
          SizedBox(height: kTvMyPleyaLabelGapPt * pt),
          _TileGrid(tiles: group.tiles, map: map, onOpen: open),
        ],
      ],
    );

    final rightColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GroupLabel(t.tvMyPleya.groupPleya),
        SizedBox(height: kTvMyPleyaLabelGapPt * pt),
        if (bigP != null) ...[
          _BigPCard(tile: bigP, map: map, onOpen: () => open(bigP)),
          SizedBox(height: kTvMyPleyaGroupGapPt * pt),
          _GroupLabel(t.settingsStudio.manage),
          SizedBox(height: kTvMyPleyaLabelGapPt * pt),
        ],
        for (final (index, tile) in manageTiles.indexed) ...[
          if (index > 0) SizedBox(height: kTvMyPleyaRowGapPt * pt),
          _Tile(tile: tile, map: map, onSelect: () => open(tile)),
        ],
      ],
    );

    // Its own screen id: `screen.main` is mounted for the entire session and
    // says nothing about which destination is showing.
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
                onNavigateDown: () => focusKey(map.firstBelowProfile),
              ),
            ),
            Padding(
              padding: textInset,
              child: Divider(height: 1, thickness: 1, color: tk.outline),
            ),
            SizedBox(height: kTvMyPleyaColumnsTopPt * pt),
            _TwoColumns(left: leftColumn, right: rightColumn),
            SizedBox(height: kTvMyPleyaFooterGapPt * pt),
            Padding(
              padding: textInset,
              child: Text(
                t.tvMyPleya.signedInAs(name: profile?.displayName ?? '', version: _appVersion ?? ''),
                style: TextStyle(
                  color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
                  fontSize: TvHig.caption2 * pt,
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

/// `Bekijk alles` carries the kijklijst section's own focus key, so the pop
/// back from the kijklijst lands on it (hoofdstuk 7.6).
final String _seeAllKey = TvMyPleyaSection.watchlist.tileFocusKey;

String _posterKey(WatchlistEntry entry) => 'tvMyPleya_poster_${entry.key}';

/// Northstar 01, in HIG points on the 1920 x 1080 canvas.
const double kTvMyPleyaAvatarPt = 64;
const double kTvMyPleyaColumnsTopPt = 18;
const double kTvMyPleyaRightColumnPt = 440;
const double kTvMyPleyaDividerGapLeftPt = 52;
const double kTvMyPleyaDividerGapRightPt = 36;
const double kTvMyPleyaGroupGapPt = 20;
const double kTvMyPleyaLabelGapPt = 8;
const double kTvMyPleyaRowGapPt = 8;
const double kTvMyPleyaFooterGapPt = 34;
