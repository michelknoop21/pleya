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
import '../../focus/focusable_wrapper.dart';
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
import '../../providers/seerr_provider.dart';
import '../../providers/watchlist_provider.dart';
import '../../theme/mono_theme.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/tv/tv_unified_layout.dart';
import 'tv_my_pleya_sections.dart';

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
  int? watchlistCount,
  int? downloadCount,
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
          subtitle: t.tvMyPleya.librariesSubtitle,
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
        TvMyPleyaTile(
          section: TvMyPleyaSection.settings,
          icon: Symbols.settings_rounded,
          title: t.common.settings,
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
  /// Owned by the state, not rebuilt per frame: a watchlist count arriving or a
  /// server going offline must not dispose the node the remote is standing on.
  final FocusMemoryTracker nodes = FocusMemoryTracker(debugLabelPrefix: 'tvMyPleya');

  String? _appVersion;

  @override
  void initState() {
    super.initState();
    unawaited(_loadVersion());
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

    final groups = buildTvMyPleyaGroups(
      hasWatchlist: watchlist?.hasWatchlist ?? false,
      hasSeerr: context.watch<SeerrProvider?>()?.isConfigured ?? false,
      // Hoofdstuk 18.3: Downloads never appears on Apple TV. The same predicate
      // `NavigationTab.getVisibleTabs` uses, so the tile and the tab cannot
      // disagree about whether the feature exists on this device.
      showDownloads: !PlatformDetector.isAppleTV(),
      // Hoofdstuk 18.3: "Server Activities verschijnt alleen wanneer een
      // relevante Plex-bron aanwezig is."
      showActivity: servers.hasOnlinePlexServers,
      watchlistCount: watchlist?.entriesByRecentlyAdded.length,
      downloadCount: downloads == null ? null : downloads.downloadedMovies.length + downloads.downloadedShows.length,
    );

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

/// One group's tiles, laid out on the shared column grid.
///
/// Every group uses the same [TvMyPleyaLayout.tilesPerRow] track width, so a
/// group of three and a group of four line up down the page instead of each
/// stretching to fill its own row — which is what the north star shows, and
/// what keeps a conditional tile disappearing from *closing up* rather than
/// resizing its neighbours (hoofdstuk 33.8).
class _TileRow extends StatelessWidget {
  const _TileRow({
    required this.tiles,
    required this.scale,
    required this.nodes,
    required this.keys,
    required this.groups,
    required this.onFocusKey,
    required this.onOpen,
  });

  final List<TvMyPleyaTile> tiles;
  final double scale;
  final FocusMemoryTracker nodes;
  final List<String> keys;

  /// Every group on the page, in order. One group is one visual row, which is
  /// what up/down has to move by — see [_verticalNeighbour].
  final List<TvMyPleyaGroup> groups;
  final void Function(String? key) onFocusKey;
  final ValueChanged<TvMyPleyaTile> onOpen;

  @override
  Widget build(BuildContext context) {
    final gap = TvMyPleyaLayout.tileGap * scale;
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth =
            (constraints.maxWidth - gap * (TvMyPleyaLayout.tilesPerRow - 1)) / TvMyPleyaLayout.tilesPerRow;
        // The tiles in a row share a height, so a two-line subtitle in one of
        // them does not leave its neighbours short — a ragged row of boxes is
        // exactly what the north star's even grid is not. `IntrinsicHeight`
        // rather than a fixed height, because the height that matters is the
        // tallest tile's, and that depends on the locale. Four children at
        // most, so the second pass costs nothing worth measuring.
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                SizedBox(
                  width: trackWidth,
                  child: _Tile(
                    tile: tiles[i],
                    scale: scale,
                    node: nodes.get(tiles[i].focusKey, debugLabel: tiles[i].focusKey),
                    onSelect: () => onOpen(tiles[i]),
                    onNavigateLeft: () => onFocusKey(_neighbour(tiles[i].focusKey, -1)),
                    onNavigateRight: () => onFocusKey(_neighbour(tiles[i].focusKey, 1)),
                    onNavigateUp: () => onFocusKey(_verticalNeighbour(tiles[i].focusKey, -1)),
                    onNavigateDown: () => onFocusKey(_verticalNeighbour(tiles[i].focusKey, 1)),
                  ),
                ),
              ],
              // The remaining tracks stay empty rather than letting three tiles
              // stretch across four columns.
              if (tiles.length < TvMyPleyaLayout.tilesPerRow)
                SizedBox(width: (trackWidth + gap) * (TvMyPleyaLayout.tilesPerRow - tiles.length)),
            ],
          ),
        );
      },
    );
  }

  /// Left/right walks the flat page order, so the end of one group hands over
  /// to the start of the next instead of dead-ending mid-page.
  String? _neighbour(String key, int delta) {
    final index = keys.indexOf(key);
    if (index < 0) return null;
    final target = index + delta;
    return (target < 0 || target >= keys.length) ? null : keys[target];
  }

  /// Up/down moves one visual row, keeping the column.
  ///
  /// It used to step [TvMyPleyaLayout.tilesPerRow] places through the flat
  /// order instead, which is only the same thing when every row is full and
  /// nothing precedes the grid. Neither holds: the profile header is the first
  /// entry in [keys] while being no part of the grid, and a group with three
  /// tiles is still one row. Both errors compound, and the result was
  /// reproducible on the simulator — DOWN from Servers, the second tile of a
  /// three-tile row, landed on Over, the *third* tile of the row below.
  ///
  /// A row is a group, so the column is the tile's index within its own group
  /// and the neighbour is the same column in the adjacent group, clamped to
  /// that group's width. From the top row UP lands on the profile header,
  /// whose own handler continues up to the top navigation; from the bottom row
  /// DOWN stays put rather than snapping to the last tile of the page, which
  /// is what clamping to [keys.last] used to do from any column.
  String? _verticalNeighbour(String key, int direction) {
    for (var g = 0; g < groups.length; g++) {
      final column = groups[g].tiles.indexWhere((tile) => tile.focusKey == key);
      if (column < 0) continue;
      final target = g + direction;
      if (target < 0) return keys.first;
      if (target >= groups.length) return null;
      final row = groups[target].tiles;
      if (row.isEmpty) return null;
      return row[column < row.length ? column : row.length - 1].focusKey;
    }
    return null;
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.tile,
    required this.scale,
    required this.node,
    required this.onSelect,
    required this.onNavigateLeft,
    required this.onNavigateRight,
    required this.onNavigateUp,
    required this.onNavigateDown,
  });

  final TvMyPleyaTile tile;
  final double scale;
  final FocusNode node;
  final VoidCallback onSelect;
  final VoidCallback onNavigateLeft;
  final VoidCallback onNavigateRight;
  final VoidCallback onNavigateUp;
  final VoidCallback onNavigateDown;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final radius = TvMyPleyaLayout.tileRadius * scale;

    return FocusableWrapper(
      focusNode: node,
      onSelect: onSelect,
      onNavigateLeft: onNavigateLeft,
      onNavigateRight: onNavigateRight,
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
      borderRadius: radius,
      // Suffixed by section name, not by index: the tile order follows what
      // the profile actually has (Aanvragen only with a Seerr server), so an
      // index would address a different section on a different fixture.
      // `logout` for the one tile that opens nothing.
      automationId: AutomationIds.myPleyaTile,
      automationInstance: tile.section?.name ?? 'logout',
      automationRole: 'grid.item',
      // The bounds a focus-ring measurement needs are the wrapper's, which is
      // what the ring is drawn around — not the inner fill, which sits a
      // `tileFocusRingGap` inside it.
      automationState: () => <String, Object?>{'title': tile.title, if (tile.count != null) 'count': tile.count},
      // Hoofdstuk 33.8: menu tiles do not scale. Twelve boxes where one grows
      // reads as an unstable wall; the ring and the lighter fill are enough.
      disableScale: true,
      semanticLabel: tile.count == null
          ? t.tvMyPleya.semantics.tile(title: tile.title, subtitle: tile.subtitle)
          : t.tvMyPleya.semantics.tileWithCount(
              title: tile.title,
              subtitle: tile.subtitle,
              count: tile.count.toString(),
            ),
      // The label above already names the tile and says what it is for.
      // Leaving the icon, the count and the two Texts in the tree as well would
      // merge a second copy into the same node, and VoiceOver would read
      // "Servers, connections and local sources, Servers, connections and
      // local sources".
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.all(TvMyPleyaLayout.tileFocusRingGap * scale),
          child: Builder(
            builder: (context) {
              final focused = Focus.of(context).hasFocus;
              return AnimatedContainer(
                duration: TvTopNavLayout.focusDuration,
                curve: Curves.easeOut,
                constraints: BoxConstraints(minHeight: TvMyPleyaLayout.tileMinHeight * scale),
                padding: EdgeInsets.all(TvMyPleyaLayout.tilePadding * scale),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  color: tk.text.withValues(
                    alpha: focused ? TvMyPleyaLayout.tileFocusedFillAlpha : TvMyPleyaLayout.tileFillAlpha,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          tile.icon,
                          size: TvMyPleyaLayout.tileIconSize * scale,
                          color: tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
                        ),
                        const Spacer(),
                        if (tile.count != null)
                          Text(
                            '${tile.count}',
                            style: TextStyle(
                              color: tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
                              fontSize: TvMyPleyaLayout.tileCountFontSize * scale,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: TvMyPleyaLayout.tileIconTitleGap * scale),
                    Text(
                      tile.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tk.text,
                        fontSize: TvMyPleyaLayout.tileTitleFontSize * scale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: TvMyPleyaLayout.tileTitleSubtitleGap * scale),
                    Text(
                      tile.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
                        fontSize: TvMyPleyaLayout.tileSubtitleFontSize * scale,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Avatar, name, how many servers answered, and the one action that belongs to
/// an identity rather than to a section.
///
/// Hoofdstuk 18.4 is the rule on the right-hand list: one server down among
/// several healthy ones is a line in this list, not a banner over the content,
/// and an auth failure is an amber line rather than a blocking red one.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.servers,
    required this.scale,
    required this.node,
    required this.onSwitchProfile,
    required this.onExitUp,
    required this.onNavigateDown,
  });

  final Profile? profile;
  final MultiServerProvider servers;
  final double scale;
  final FocusNode node;
  final VoidCallback onSwitchProfile;
  final VoidCallback onExitUp;
  final VoidCallback onNavigateDown;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final total = servers.totalServerCount;
    final online = servers.onlineServerCount;

    return Container(
      padding: EdgeInsets.all(TvMyPleyaLayout.headerPadding * scale),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TvMyPleyaLayout.headerRadius * scale),
        color: tk.text.withValues(alpha: TvMyPleyaLayout.tileFillAlpha),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ExcludeSemantics(
            child: ProfileAvatar(profile: profile, size: TvMyPleyaLayout.avatarSize * scale),
          ),
          SizedBox(width: TvMyPleyaLayout.headerGap * scale),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                profile?.displayName ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tk.text,
                  fontSize: TvMyPleyaLayout.headerNameFontSize * scale,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                total == 0 ? t.tvMyPleya.noServers : t.tvMyPleya.serversOnline(online: '$online', total: '$total'),
                style: TextStyle(
                  color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
                  fontSize: TvMyPleyaLayout.headerMetaFontSize * scale,
                ),
              ),
            ],
          ),
          SizedBox(width: TvMyPleyaLayout.headerGap * scale),
          _SwitchProfileAction(
            node: node,
            scale: scale,
            onSelect: onSwitchProfile,
            onNavigateUp: onExitUp,
            onNavigateDown: onNavigateDown,
          ),
          const Spacer(),
          Flexible(
            child: _ServerStatusList(servers: servers, scale: scale),
          ),
        ],
      ),
    );
  }
}

class _SwitchProfileAction extends StatelessWidget {
  const _SwitchProfileAction({
    required this.node,
    required this.scale,
    required this.onSelect,
    required this.onNavigateUp,
    required this.onNavigateDown,
  });

  final FocusNode node;
  final double scale;
  final VoidCallback onSelect;
  final VoidCallback onNavigateUp;
  final VoidCallback onNavigateDown;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    const shape = StadiumBorder();
    return FocusableWrapper(
      focusNode: node,
      onSelect: onSelect,
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
      focusShapeBorder: shape,
      disableScale: true,
      semanticLabel: t.screens.switchProfile,
      child: Padding(
        padding: EdgeInsets.all(TvTopNavLayout.focusRingGap * scale),
        child: Container(
          decoration: ShapeDecoration(
            shape: shape,
            color: tk.text.withValues(alpha: TvMyPleyaLayout.tileFocusedFillAlpha),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: TvTopNavLayout.pillPaddingHorizontal * scale,
            vertical: TvTopNavLayout.pillPaddingVertical * scale,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Symbols.switch_account_rounded,
                size: TvMyPleyaLayout.tileIconSize * scale,
                color: tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
              ),
              SizedBox(width: TvCatalogLayout.actionIconGap * scale),
              Text(
                t.screens.switchProfile,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tk.text,
                  fontSize: TvTopNavLayout.itemFontSize * scale,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The right-hand server list: a dot per server, and the auth line underneath.
///
/// Not focusable. It is a status readout, and a remote that has to walk past
/// three servers to reach the first tile is a remote fighting the page. It is
/// still announced, as one node, so a VoiceOver user hears the same summary a
/// sighted user reads.
class _ServerStatusList extends StatelessWidget {
  const _ServerStatusList({required this.servers, required this.scale});

  final MultiServerProvider servers;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final rows = servers.serverIds
        .map(
          (id) => (
            name: servers.serverManager.serverDisplayName(ServerId(id)),
            online: servers.onlineServerIds.contains(id),
          ),
        )
        .toList();
    if (rows.isEmpty) return const SizedBox.shrink();

    final authErrors = servers.authErrorServers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows)
          Padding(
            padding: EdgeInsets.only(bottom: TvMyPleyaLayout.serverRowGap * scale),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: TvMyPleyaLayout.serverDotSize * scale,
                  height: TvMyPleyaLayout.serverDotSize * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // Red here is a status dot on a status list, not navigation
                    // chrome — hoofdstuk 33 reserves the brand red for the
                    // progress line and small semantic marks, and this is one.
                    color: row.online ? const Color(0xFF3FBF5F) : kAccent,
                  ),
                ),
                SizedBox(width: TvMyPleyaLayout.serverRowGap * scale),
                Text(
                  row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tk.text,
                    fontSize: TvMyPleyaLayout.serverRowFontSize * scale,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: TvMyPleyaLayout.serverRowGap * scale),
                Text(
                  row.online ? t.tvMyPleya.statusOnline : t.tvMyPleya.statusOffline,
                  style: TextStyle(
                    color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
                    fontSize: TvMyPleyaLayout.serverRowFontSize * scale,
                  ),
                ),
              ],
            ),
          ),
        // Hoofdstuk 18.4: amber, one line, and never a blocking banner over the
        // content.
        if (authErrors.isNotEmpty)
          Text(
            authErrors.length == 1
                ? t.connections.sessionExpiredOne(name: authErrors.first.displayName)
                : t.connections.sessionExpiredMany(count: '${authErrors.length}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: kAccentAlt, fontSize: TvMyPleyaLayout.serverRowFontSize * scale),
          ),
      ],
    );
  }
}
