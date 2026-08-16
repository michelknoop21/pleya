import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/watchlist_key.dart';
import 'package:pleya/utils/external_ids.dart';

MediaItem item({String? guid, String id = '12345', String? serverId, MediaBackend backend = MediaBackend.plex}) {
  return MediaItem(id: id, backend: backend, kind: MediaKind.movie, guid: guid, title: 'Sintel', serverId: serverId);
}

void main() {
  group('discoverRatingKeyFromGuid', () {
    test('takes the tail of a plex guid', () {
      expect(discoverRatingKeyFromGuid('plex://movie/5d776be17a53e9001e732ab9'), '5d776be17a53e9001e732ab9');
      expect(discoverRatingKeyFromGuid('plex://show/5d9c11223344556677889900'), '5d9c11223344556677889900');
    });

    test('ignores a query string rather than folding it into the key', () {
      expect(discoverRatingKeyFromGuid('plex://movie/abc?lang=en'), 'abc');
    });

    test('returns null for anything that is not a plex guid', () {
      expect(discoverRatingKeyFromGuid(null), isNull);
      expect(discoverRatingKeyFromGuid(''), isNull);
      expect(discoverRatingKeyFromGuid('plex://movie/'), isNull);
      expect(discoverRatingKeyFromGuid('plex://movie'), isNull);
      expect(discoverRatingKeyFromGuid('local://movie/abc'), isNull);
      expect(discoverRatingKeyFromGuid('com.plexapp.agents.imdb://tt0111161?lang=en'), isNull);
    });
  });

  group('externalIdsFromLegacyAgentGuid', () {
    test('reads imdb, tmdb and tvdb agents', () {
      expect(externalIdsFromLegacyAgentGuid('com.plexapp.agents.imdb://tt0111161?lang=en').imdb, 'tt0111161');
      expect(externalIdsFromLegacyAgentGuid('com.plexapp.agents.themoviedb://278?lang=en').tmdb, 278);
      expect(externalIdsFromLegacyAgentGuid('com.plexapp.agents.thetvdb://73141/1/2?lang=en').tvdb, 73141);
    });

    test('returns nothing for a modern guid or an unknown agent', () {
      expect(externalIdsFromLegacyAgentGuid('plex://movie/abc').hasAny, isFalse);
      expect(externalIdsFromLegacyAgentGuid('com.plexapp.agents.none://abc').hasAny, isFalse);
      expect(externalIdsFromLegacyAgentGuid(null).hasAny, isFalse);
    });
  });

  group('watchlistKeyForItem', () {
    test('a server item and a discover item of the same title agree on the key', () {
      final onServer = item(guid: 'plex://movie/5d776be17a53e9001e732ab9', id: '4711', serverId: 'machine-1');
      final onDiscover = item(guid: 'plex://movie/5d776be17a53e9001e732ab9', id: '5d776be17a53e9001e732ab9');

      expect(watchlistKeyForItem(onServer), watchlistKeyForItem(onDiscover));
      expect(watchlistKeyForItem(onServer), 'plex:5d776be17a53e9001e732ab9');
    });

    test('the key is not the global key, so it cannot land in the server-key namespace', () {
      final onServer = item(guid: 'plex://movie/abc', id: '4711', serverId: 'machine-1');

      expect(watchlistKeyForItem(onServer), isNot(onServer.globalKey));
      expect(watchlistKeyForItem(onServer), isNot(onServer.id));
    });

    test('falls back to external ids in a fixed order', () {
      final jellyfin = item(backend: MediaBackend.jellyfin, id: 'abcd', serverId: 'jf-1');

      expect(
        watchlistKeyForItem(jellyfin, externalIds: const ExternalIds(imdb: 'tt0111161', tmdb: 278)),
        'imdb:tt0111161',
      );
      expect(watchlistKeyForItem(jellyfin, externalIds: const ExternalIds(tmdb: 278, tvdb: 73141)), 'tmdb:278');
      expect(watchlistKeyForItem(jellyfin, externalIds: const ExternalIds(tvdb: 73141)), 'tvdb:73141');
    });

    test('a plex guid outranks external ids so both sides of a merge agree', () {
      final withBoth = item(guid: 'plex://movie/abc');

      expect(watchlistKeyForItem(withBoth, externalIds: const ExternalIds(imdb: 'tt0111161')), 'plex:abc');
    });

    test('a legacy agent guid still yields a key', () {
      final legacy = item(guid: 'com.plexapp.agents.imdb://tt0111161?lang=en');

      expect(watchlistKeyForItem(legacy), 'imdb:tt0111161');
    });

    test('empty external ids fall through to the legacy guid instead of returning null', () {
      final legacy = item(guid: 'com.plexapp.agents.imdb://tt0111161?lang=en');

      expect(watchlistKeyForItem(legacy, externalIds: const ExternalIds()), 'imdb:tt0111161');
    });

    test('no identity is a real answer, not an accident', () {
      expect(watchlistKeyForItem(item()), isNull);
      expect(watchlistKeyForItem(item(guid: '')), isNull);
      expect(watchlistKeyForItem(item(), externalIds: const ExternalIds()), isNull);
    });

    test('namespaces keep lookalike ids apart', () {
      final keys = {
        watchlistKeyForIdentity(externalIds: const ExternalIds(tmdb: 278)),
        watchlistKeyForIdentity(externalIds: const ExternalIds(tvdb: 278)),
        watchlistKeyForIdentity(guid: 'plex://movie/278'),
      };

      expect(keys, hasLength(3));
    });

    test('a hostile id cannot fake a namespace boundary', () {
      final faked = watchlistKeyForIdentity(externalIds: const ExternalIds(imdb: 'x:plex:abc'));

      expect(faked, isNot('plex:abc'));
      expect(faked!.split(':').first, 'imdb');
    });
  });
}
