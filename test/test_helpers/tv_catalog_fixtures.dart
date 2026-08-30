/// The one library the Films/Series goldens browse.
///
/// Shared rather than copied. Two golden files picture the same catalog — one
/// the page's ordinary states, one its loading, empty and error states — and
/// when each carried its own `_catalog()` the two were already drifting: the
/// state goldens showed a library of twelve science-fiction films with no
/// artwork while the main goldens showed twelve varied ones with it. Nothing
/// fails when fixtures drift; the pictures just quietly stop being about the
/// same product.
///
/// The artwork indices line up with `TvGoldenArtwork`'s palette, which is what
/// makes a card in either file the same card.
library;

import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/services/unified_catalog/source_cursor.dart';

import 'tv_catalog_artwork.dart';

MediaItem tvGoldenMovie({
  required String id,
  required String title,
  int? year = 2024,
  String? genre = 'Science fiction',
  int? viewOffsetMs,
  int? viewCount,
  String serverId = 'nas',
  String serverName = 'NAS',
  MediaBackend backend = MediaBackend.plex,
  int? artwork,
}) => MediaItem(
  id: id,
  backend: backend,
  kind: MediaKind.movie,
  title: title,
  year: year,
  durationMs: 9960000,
  viewOffsetMs: viewOffsetMs,
  viewCount: viewCount,
  genres: genre == null ? null : [genre],
  serverId: serverId,
  serverName: serverName,
  // Null renders the no-artwork panel, which is a state worth keeping
  // reachable; every catalog fixture passes an index.
  thumbPath: artwork == null ? null : TvGoldenArtwork.pathFor(artwork),
);

UnifiedMediaGroup tvGoldenGroup(String id, List<MediaItem> items, {bool watched = false, bool inProgress = false}) {
  final sources = [for (final item in items) UnifiedMediaSource.fromItem(item)];
  return UnifiedMediaGroup(
    groupId: id,
    identity: CanonicalMediaIdentity.movie(title: items.first.title, year: items.first.year),
    sources: sources,
    representativeSourceKey: sources.first.sourceKey,
    watchState: UnifiedWatchState(
      representativeSourceKey: sources.first.sourceKey,
      isWatched: watched,
      hasActiveProgress: inProgress,
      lastViewedAt: inProgress || watched ? 1 : null,
    ),
  );
}

/// A page's worth of groups: a mix of single and multi source, watched,
/// in-progress and untouched, across twelve genres and twelve palettes.
///
/// The mix is the point twice over. A grid of identical cards proves nothing
/// about whether the source badge, the watched tick and the resume bar can
/// coexist in one row; a grid of identically-coloured cards proves nothing
/// about whether Pleya's dark chrome can present a library that is not all one
/// mood.
List<UnifiedMediaGroup> tvGoldenCatalog() {
  const titles = <({String title, String genre, int sources, bool watched, bool progress, int? offset})>[
    (title: 'Paddington in Peru', genre: 'Family', sources: 2, watched: false, progress: true, offset: 2538000),
    (title: 'Dune: Part Two', genre: 'Science fiction', sources: 3, watched: true, progress: false, offset: null),
    (title: 'Inside Out 2', genre: 'Animation', sources: 1, watched: false, progress: true, offset: 6400000),
    (title: 'The Zone of Interest', genre: 'Drama', sources: 2, watched: false, progress: false, offset: null),
    (title: 'Poor Things', genre: 'Comedy', sources: 1, watched: true, progress: false, offset: null),
    (
      title: 'Everything Everywhere All at Once',
      genre: 'Adventure',
      sources: 2,
      watched: false,
      progress: false,
      offset: null,
    ),
    (title: 'Planet Earth III', genre: 'Documentary', sources: 1, watched: false, progress: false, offset: null),
    (title: 'The Batman', genre: 'Crime', sources: 2, watched: false, progress: true, offset: 3100000),
    (title: 'Lawrence of Arabia', genre: 'Epic', sources: 1, watched: true, progress: false, offset: null),
    (title: 'Past Lives', genre: 'Romance', sources: 3, watched: false, progress: false, offset: null),
    (title: 'Princess Mononoke', genre: 'Fantasy', sources: 1, watched: false, progress: false, offset: null),
    (title: 'Casablanca', genre: 'Classic', sources: 2, watched: false, progress: false, offset: null),
  ];
  return [
    for (var i = 0; i < titles.length; i++)
      tvGoldenGroup(
        'g$i',
        [
          for (var s = 0; s < titles[i].sources; s++)
            tvGoldenMovie(
              id: 'i$i-$s',
              title: titles[i].title,
              year: 2017 + (i % 8),
              genre: titles[i].genre,
              artwork: i,
              viewOffsetMs: s == 0 ? titles[i].offset : null,
              viewCount: s == 0 && titles[i].watched ? 1 : null,
              serverId: ['nas', 'attic', 'shed'][s],
              serverName: ['NAS', 'Zolder', 'Schuur'][s],
              backend: s == 1 ? MediaBackend.jellyfin : MediaBackend.plex,
            ),
        ],
        watched: titles[i].watched,
        inProgress: titles[i].progress,
      ),
  ];
}

/// Three libraries on three servers, one per backend — which is what makes the
/// filter panel's capability rule visible: the Pleya Server library is the one
/// that takes genre, year and status out of the rail.
final tvGoldenLibraries = <CatalogLibrary>[
  (serverId: ServerId('nas'), serverName: 'NAS', libraryId: '1', libraryTitle: 'Films 4K', backend: MediaBackend.plex),
  (
    serverId: ServerId('attic'),
    serverName: 'Zolder',
    libraryId: '2',
    libraryTitle: 'Movies',
    backend: MediaBackend.jellyfin,
  ),
  (
    serverId: ServerId('shed'),
    serverName: 'Schuur',
    libraryId: '3',
    libraryTitle: 'Archief',
    backend: MediaBackend.pleyaServer,
  ),
];
