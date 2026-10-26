/// The `Snel naar` row of Mijn Pleya on Apple TV (A-24c, northstar
/// `docs/assets/a24c-northstars/02-Mijn-Pleya-v4`).
///
/// Pure, and apart from the widgets, for the same reason [buildTvMyPleyaGroups]
/// is: *which* tiles exist is the function mapping of `pariteit-v4.csv`, the
/// thing that has to be checked against the parity table rather than read off
/// a build method. The iPhone page keeps [buildTvMyPleyaGroups]; this row is
/// TV only.
///
/// Fixed order, and a tile that is not available is left out rather than
/// drawn disabled, so the row closes up without an empty place (`A15`).
library;

import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import 'tv_my_pleya_groups.dart';
import 'tv_my_pleya_sections.dart';

/// The dock's tiles for the given capabilities, left to right.
///
/// Samen kijken and Bibliotheken are unconditional. Downloads is not part of
/// the northstar, which draws an Apple TV, and stays absent there
/// ([showDownloads] is `!PlatformDetector.isAppleTV()` at the call site); an
/// Android TV keeps the tile it had before A-24c.
List<TvMyPleyaTile> buildTvMyPleyaDock({
  required bool hasSeerr,
  required bool showDownloads,
  required bool showActivity,
  required bool showCollections,
  required bool showPlaylists,
}) => [
  TvMyPleyaTile(
    section: TvMyPleyaSection.watchTogether,
    icon: Symbols.group_rounded,
    title: t.myPleya.watchTogether,
    subtitle: t.myPleya.watchTogetherSubtitle,
  ),
  if (showCollections)
    TvMyPleyaTile(
      section: TvMyPleyaSection.collections,
      icon: Symbols.stacks_rounded,
      title: t.collections.title,
      subtitle: t.tvMyPleya.collectionsSubtitle,
    ),
  if (showPlaylists)
    TvMyPleyaTile(
      section: TvMyPleyaSection.playlists,
      icon: Symbols.playlist_add_rounded,
      title: t.playlists.title,
      subtitle: t.tvMyPleya.playlistsSubtitle,
    ),
  if (hasSeerr)
    TvMyPleyaTile(
      section: TvMyPleyaSection.requests,
      icon: Symbols.description_rounded,
      title: t.seerr.title,
      subtitle: t.myPleya.requestsSubtitle,
    ),
  if (showDownloads)
    TvMyPleyaTile(
      section: TvMyPleyaSection.downloads,
      icon: Symbols.download_rounded,
      title: t.navigation.downloads,
      subtitle: t.myPleya.downloadsSubtitle,
    ),
  TvMyPleyaTile(
    section: TvMyPleyaSection.libraries,
    icon: Symbols.grid_view_rounded,
    // The screen's name, not the rail's short label ("Bibliotheken" against
    // "Media" in Dutch), the rule `buildTvMyPleyaGroups` documents.
    title: t.libraries.title,
    subtitle: t.myPleya.librariesSubtitle,
  ),
  if (showActivity)
    TvMyPleyaTile(
      section: TvMyPleyaSection.activity,
      icon: Symbols.vital_signs_rounded,
      title: t.tvMyPleya.activity,
      subtitle: t.myPleya.activitySubtitle,
    ),
];
