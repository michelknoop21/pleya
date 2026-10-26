/// Which Mijn Pleya destinations exist, with their icon, title and subtitle.
///
/// Shared by the iPhone page ([MyPleyaScreen]) and the Apple TV hub
/// ([TvMyPleyaScreen]), so the two platforms read one function mapping and one
/// set of Editorial labels (A-24b, northstars `02-Mijn-Pleya/images/00` and
/// `01`). Where each platform puts a destination is its own screen's business.
library;

import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import 'tv_my_pleya_sections.dart';

/// The three blocks of the hub. On Apple TV [content] and [sources] form the
/// left column and [pleya] the right one (northstar 01).
enum TvMyPleyaGroupKind { content, sources, pleya }

/// One tile in a group.
class TvMyPleyaTile {
  const TvMyPleyaTile({
    required this.section,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.count,
  });

  /// What the tile opens. Null for the sign-out tile, which acts instead of
  /// navigating.
  final TvMyPleyaSection? section;

  final IconData icon;
  final String title;
  final String subtitle;

  /// Rendered at the end of the row when non-null. Deliberately nullable rather
  /// than defaulting to zero: a tile reading "0" is a tile that should not
  /// carry a count at all.
  final int? count;

  String get focusKey => 'tvMyPleya_${section?.name ?? 'logout'}';
}

/// A group of tiles under one heading.
class TvMyPleyaGroup {
  const TvMyPleyaGroup({required this.kind, required this.label, required this.tiles});
  final TvMyPleyaGroupKind kind;
  final String label;
  final List<TvMyPleyaTile> tiles;
}

/// The hub's groups for the given conditions.
///
/// Pure, and separate from the widgets, because *which* tiles exist is the
/// hoofdstuk 18.2 function mapping, the thing that has to be checked against
/// the roadmap rather than read off a build method. The counts only change a
/// subtitle ("6 bibliotheken", "2 online") or the number at the end of a row;
/// they never decide whether a tile exists.
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
  int? libraryCount,
  int? onlineServerCount,
  int? totalServerCount,
}) {
  // A tile reading "0" is a tile that should not carry a count at all, so the
  // rule lives here rather than at the call site.
  int? shown(int? value) => (value == null || value == 0) ? null : value;
  final collections = shown(collectionCount);
  final playlists = shown(playlistCount);
  final libraries = shown(libraryCount);
  final serversSubtitle = switch ((onlineServerCount, totalServerCount)) {
    (_, 0) => t.tvMyPleya.noServers,
    (final int online, _) => t.myPleya.serversOnline(count: '$online'),
    _ => t.tvMyPleya.serversSubtitle,
  };
  return [
    TvMyPleyaGroup(
      kind: TvMyPleyaGroupKind.content,
      label: t.tvMyPleya.groupContent,
      tiles: [
        if (hasWatchlist)
          TvMyPleyaTile(
            section: TvMyPleyaSection.watchlist,
            icon: Symbols.bookmark_rounded,
            title: t.watchlist.title,
            subtitle: t.tvMyPleya.watchlistSubtitle,
            count: shown(watchlistCount),
          ),
        if (showCollections)
          TvMyPleyaTile(
            section: TvMyPleyaSection.collections,
            icon: Symbols.shelves_rounded,
            title: t.collections.title,
            subtitle: collections == null
                ? t.tvMyPleya.collectionsSubtitle
                : t.myPleya.collectionsCount(n: collections),
          ),
        if (showPlaylists)
          TvMyPleyaTile(
            section: TvMyPleyaSection.playlists,
            icon: Symbols.playlist_add_rounded,
            title: t.playlists.title,
            subtitle: playlists == null ? t.tvMyPleya.playlistsSubtitle : t.myPleya.playlistsCount(n: playlists),
          ),
        if (hasSeerr)
          TvMyPleyaTile(
            section: TvMyPleyaSection.requests,
            icon: Symbols.bookmark_add_rounded,
            title: t.seerr.title,
            subtitle: t.myPleya.requestsSubtitle,
          ),
        if (showDownloads)
          TvMyPleyaTile(
            section: TvMyPleyaSection.downloads,
            icon: Symbols.download_rounded,
            title: t.navigation.downloads,
            subtitle: t.myPleya.downloadsSubtitle,
            count: shown(downloadCount),
          ),
      ],
    ),
    TvMyPleyaGroup(
      kind: TvMyPleyaGroupKind.sources,
      label: t.tvMyPleya.groupSources,
      tiles: [
        TvMyPleyaTile(
          section: TvMyPleyaSection.libraries,
          icon: Symbols.grid_view_rounded,
          // The screen's name, not the rail's short label. In Dutch the two
          // differ ("Bibliotheken" against "Media"), and the audit of
          // 2 September 2026 counted that as one of three names on one place.
          title: t.libraries.title,
          subtitle: libraries == null ? t.myPleya.librariesSubtitle : t.myPleya.librariesCount(n: libraries),
        ),
        TvMyPleyaTile(
          section: TvMyPleyaSection.servers,
          icon: Symbols.dns_rounded,
          title: t.tvMyPleya.servers,
          subtitle: serversSubtitle,
        ),
        if (showActivity)
          TvMyPleyaTile(
            section: TvMyPleyaSection.activity,
            icon: Symbols.vital_signs_rounded,
            title: t.tvMyPleya.activity,
            subtitle: t.myPleya.activitySubtitle,
          ),
        // Fase 8: this used to hang off the Home billboard's overlaid action
        // bar, which the rounded in-page hero replaced. See
        // `TvMyPleyaSection.watchTogether` for why it landed here.
        TvMyPleyaTile(
          section: TvMyPleyaSection.watchTogether,
          icon: Symbols.group_rounded,
          title: t.myPleya.watchTogether,
          subtitle: t.myPleya.watchTogetherSubtitle,
        ),
      ],
    ),
    TvMyPleyaGroup(
      kind: TvMyPleyaGroupKind.pleya,
      label: t.tvMyPleya.groupPleya,
      tiles: [
        // First in the group: on TV the Big P card above Beheer, on iPhone the
        // red card under Jouw content.
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
          subtitle: t.myPleya.settingsSubtitle,
        ),
        TvMyPleyaTile(
          section: TvMyPleyaSection.logs,
          icon: Symbols.description_rounded,
          title: t.tvMyPleya.logs,
          subtitle: t.myPleya.logsSubtitle,
        ),
        TvMyPleyaTile(
          section: TvMyPleyaSection.about,
          icon: Symbols.info_rounded,
          title: t.settings.about,
          subtitle: t.myPleya.aboutSubtitle,
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
