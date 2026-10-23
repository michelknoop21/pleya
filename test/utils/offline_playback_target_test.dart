import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/utils/offline_playback_target.dart';

void main() {
  final film = MediaItem(id: 'film', backend: .plex, kind: .movie, title: 'Film', serverId: 'one');
  final show = MediaItem(id: 'show', backend: .plex, kind: .show, title: 'Show', serverId: 'one');
  final season = MediaItem(
    id: 's2',
    backend: .plex,
    kind: .season,
    title: 'Season2',
    parentId: 'show',
    serverId: 'one',
  );
  final ep = MediaItem(
    id: 'ep',
    backend: .plex,
    kind: .episode,
    title: 'Episode',
    parentId: 's2',
    grandparentId: 'show',
    parentIndex: 2,
    index: 1,
    serverId: 'one',
  );
  test('metadata alone never creates an offline play target', () {
    expect(offlinePlaybackTarget(film, []), isNull);
    expect(offlinePlaybackTarget(show, []), isNull);
  });
  test('completed downloads stay playable without mixing identical IDs on another server', () {
    expect(offlinePlaybackTarget(film, [film]), film);
    expect(offlinePlaybackTarget(film, [film.copyWith(serverId: 'two')]), isNull);
    expect(offlinePlaybackTarget(show, [ep]), ep);
    expect(offlinePlaybackTarget(season, [ep]), ep);
    expect(offlinePlaybackTarget(show, [ep.copyWith(serverId: 'two')]), isNull);
    expect(offlinePlaybackTarget(season.copyWith(id: 's1'), [ep]), isNull);
  });
  test('a cached on-deck episode cannot override actual downloaded availability', () {
    expect(offlinePlaybackTarget(show, [ep], preferred: ep.copyWith(id: 'missing')), ep);
  });
}
