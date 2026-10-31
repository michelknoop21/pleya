import '../media/episode_collection.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';

/// What Watch in the long-press menu starts for [item]: the item itself, or for
/// a show or season the episode its detail page would start. Null when there is
/// no episode to play.
Future<MediaItem?> resolveWatchTarget(MediaServerClient client, MediaItem item) async {
  final episode = switch (item.kind) {
    MediaKind.show => await _nextEpisodeOfShow(client, item),
    MediaKind.season => await _nextEpisodeOfSeason(client, item),
    _ => item,
  };
  if (episode == null || identical(episode, item)) return episode;
  return episode.copyWith(
    serverId: item.serverId ?? episode.serverId,
    serverName: item.serverName ?? episode.serverName,
    libraryId: episode.libraryId ?? item.libraryId,
    libraryTitle: episode.libraryTitle ?? item.libraryTitle,
  );
}

/// The server's on-deck episode, or on a backend without one the first episode
/// still to watch, or the first of the show for a rewatch.
Future<MediaItem?> _nextEpisodeOfShow(MediaServerClient client, MediaItem show) async {
  final onDeck = (await client.fetchItemWithOnDeck(show.id)).onDeckEpisode;
  if (onDeck != null) return onDeck;
  final seasons = await client.fetchChildren(show.id);
  final unwatched = firstUnwatchedSeasonIndex(seasons);
  final season = unwatched == null ? defaultPlaybackSeason(seasons) : seasons[unwatched];
  return season == null ? null : _nextEpisodeOfSeason(client, season);
}

Future<MediaItem?> _nextEpisodeOfSeason(MediaServerClient client, MediaItem season) async {
  final episodes = (await client.fetchChildren(season.id)).where((item) => item.kind == MediaKind.episode).toList();
  return firstUnwatchedEpisode(episodes) ?? episodes.firstOrNull;
}
