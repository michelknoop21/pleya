import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/settings_service.dart' show EpisodePosterMode;

/// An episode without a still of its own (a Pleya Server episode before the
/// metadata round found one) used to draw an empty tile wherever a card or row
/// asked for `thumbPath`. The fallback is the same for every backend: own
/// still, episode backdrop, show backdrop, show poster.
MediaItem _episode({
  String? thumb,
  String? art,
  String? showArt,
  String? showPoster,
  MediaBackend backend = MediaBackend.pleyaServer,
}) => MediaItem(
  id: 'e1',
  backend: backend,
  kind: MediaKind.episode,
  title: 'TBA',
  thumbPath: thumb,
  artPath: art,
  grandparentArtPath: showArt,
  grandparentThumbPath: showPoster,
  serverId: 's1',
);

void main() {
  group('rowThumbPath', () {
    test('an episode keeps its own still first, on every backend', () {
      for (final backend in [MediaBackend.plex, MediaBackend.jellyfin, MediaBackend.local, MediaBackend.pleyaServer]) {
        expect(_episode(thumb: '/still', showArt: '/show-art', backend: backend).rowThumbPath, '/still');
      }
    });

    test('without a still it falls back to backdrop, show backdrop, then show poster', () {
      expect(_episode(art: '/ep-art', showArt: '/show-art', showPoster: '/poster').rowThumbPath, '/ep-art');
      expect(_episode(showArt: '/show-art', showPoster: '/poster').rowThumbPath, '/show-art');
      expect(_episode(showPoster: '/poster').rowThumbPath, '/poster');
      expect(_episode().rowThumbPath, isNull);
    });

    test('anything that is not an episode keeps its own thumb', () {
      final movie = MediaItem(
        id: 'm',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'Alien',
        artPath: '/art',
        grandparentArtPath: '/never',
        serverId: 's1',
      );
      expect(movie.rowThumbPath, isNull);
    });
  });

  test('a hub card in episode-thumbnail mode no longer goes blank without a still', () {
    final episode = _episode(showArt: '/show-art', showPoster: '/poster');
    expect(episode.posterThumb(mode: EpisodePosterMode.episodeThumbnail), '/show-art');
    // The poster modes are unchanged.
    expect(episode.posterThumb(mode: EpisodePosterMode.seriesPoster), '/poster');
  });
}
