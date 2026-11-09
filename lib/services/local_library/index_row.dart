import '../../media/media_item.dart';
import '../../media/media_kind.dart';

bool _listRowOnly(MediaItem item) => item.kind == MediaKind.episode || item.kind == MediaKind.season;

/// What the offline index stores for [item] (DEC-196). Seasons and episodes
/// are 15 of every 16 rows and are only ever shown in a list, so they lose
/// cast and versions. Movies keep their versions for the resolution sort and
/// grouping; movies and shows keep their cast for offline search and detail.
MediaItem indexRow(MediaItem item) => _listRowOnly(item) ? item.copyWith(roles: null, mediaVersions: null) : item;

/// The posters the index keeps for [item]. An episode's own still is left out:
/// offline, an episode list draws the season or show poster instead.
Iterable<String> indexedPosterPaths(MediaItem item) => [
  if (item.kind != MediaKind.episode) ?item.thumbPath,
  ?item.parentThumbPath,
  ?item.grandparentThumbPath,
];
