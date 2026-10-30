/// The episodes of one series per source, addressed by season and episode
/// number: the only identity an episode has across servers (hoofdstuk 11.8 of
/// docs/tvos-unified-experience.md, besluit 1 of DEC-XXX "Eén titel over
/// servers heen").
///
/// Rating keys are per server, so the page's episode list cannot name another
/// server's copy. A series belongs to a group because grouping proved it, and
/// inside a proven series the two numbers are enough.
library;

import 'dart:async';

import '../../media/media_item.dart';
import '../../media/media_item_types.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/unified_media_source.dart';
import '../../utils/app_logger.dart';
import '../../utils/media_server_timeouts.dart';

typedef EpisodeCoordinate = ({int season, int episode});

/// The coordinate of [item]. Null for anything but an episode with both
/// numbers: an episode without them has no identity outside its own server.
EpisodeCoordinate? episodeCoordinateOf(MediaItem item) {
  final season = item.parentIndex;
  final episode = item.index;
  if (!item.isEpisode || season == null || episode == null) return null;
  return (season: season, episode: episode);
}

/// One source's episodes. A coordinate held by two rows is left out: a double
/// code without stronger proof names nothing (hoofdstuk 11.8).
class SourceEpisodes {
  SourceEpisodes(Iterable<MediaItem> episodes) {
    final doubled = <EpisodeCoordinate>{};
    for (final episode in episodes) {
      final coordinate = episodeCoordinateOf(episode);
      if (coordinate == null) continue;
      if (_byCoordinate.containsKey(coordinate)) doubled.add(coordinate);
      _byCoordinate[coordinate] = episode;
    }
    doubled.forEach(_byCoordinate.remove);
  }

  final Map<EpisodeCoordinate, MediaItem> _byCoordinate = {};

  MediaItem? at(EpisodeCoordinate coordinate) => _byCoordinate[coordinate];

  Iterable<MediaItem> get all => _byCoordinate.values;
}

/// The series id of [source]: its own for a series, the parent's for an
/// episode group out of Verder kijken.
String? seriesIdOf(UnifiedMediaSource source) => source.item.isShow ? source.item.id : source.item.grandparentId;

/// Loads and keeps [SourceEpisodes] for the sources of one title.
///
/// A list is fetched once and shared between the page and the player of that
/// title. [invalidate] forgets it, so the next read sees the watch state a play
/// left behind. The last good list stays readable through [loaded]: a server
/// that went away during the play can still be addressed for a queued write.
class SourceEpisodeIndex {
  SourceEpisodeIndex({this.timeout = MediaServerTimeouts.interactive});

  /// Ceiling per server. A slow second server must not hold up a play that
  /// could have started from the first.
  final Duration timeout;

  final Map<String, Future<SourceEpisodes?>> _inFlight = {};
  final Map<String, SourceEpisodes> _loaded = {};

  SourceEpisodes? loaded(UnifiedMediaSource source) => _loaded[source.sourceKey];

  /// The episodes of [source] through [client]. Null when it cannot answer,
  /// which is not the same as answering with nothing.
  Future<SourceEpisodes?> of(UnifiedMediaSource source, MediaServerClient client) {
    final seriesId = seriesIdOf(source);
    if (seriesId == null) return Future.value();
    return _inFlight[source.sourceKey] ??= _fetch(source, client, seriesId);
  }

  Future<SourceEpisodes?> _fetch(UnifiedMediaSource source, MediaServerClient client, String seriesId) async {
    try {
      final episodes = await client.fetchPlayableDescendants(seriesId).timeout(timeout);
      final list = SourceEpisodes([
        for (final episode in episodes)
          episode.copyWith(
            serverId: source.serverId.value,
            serverName: episode.serverName ?? source.serverName,
            libraryId: episode.libraryId ?? source.libraryId,
            libraryTitle: episode.libraryTitle ?? source.libraryTitle,
          ),
      ]);
      _loaded[source.sourceKey] = list;
      return list;
    } catch (e, st) {
      appLogger.d('Episodes of ${source.sourceKey} could not be read', error: e, stackTrace: st);
      // Not kept: the next read asks again. After the microtask, because a
      // client that throws before its first await lands here before [of] has
      // stored this future.
      scheduleMicrotask(() => _inFlight.remove(source.sourceKey));
      return _loaded[source.sourceKey];
    }
  }

  void invalidate() => _inFlight.clear();
}
