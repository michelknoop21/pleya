/// Covers hoofdstuk 16.1/16.2: "Dune (2021) — 3 bronnen" instead of one row
/// per server, collections and playlists staying source-concrete, and the
/// standing bias that a false merge costs more than a false negative.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/unified_catalog/search_projection.dart';
import 'package:pleya/utils/external_ids.dart';

MediaItem _item(
  String id, {
  required MediaKind kind,
  required String serverId,
  String? title,
  int? year,
  String? guid,
  String? show,
  String? showId,
  int? season,
  int? episode,
}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: kind,
  title: title,
  year: year,
  guid: guid,
  grandparentId: showId,
  grandparentTitle: show,
  parentIndex: season,
  index: episode,
  serverId: serverId,
  serverName: serverId,
);

Future<ExternalIds> Function(String, String) _ids([Map<String, ExternalIds> byKey = const {}]) =>
    (serverId, targetId) async => byKey['$serverId:$targetId'] ?? const ExternalIds();

void main() {
  group('searchProjection — unified sections', () {
    test('one film on three servers is one result carrying three sources', () async {
      final results = [
        for (final server in ['a', 'b', 'c'])
          _item('$server-1', kind: MediaKind.movie, serverId: server, title: 'Dune', year: 2021),
      ];

      final projection = await searchProjection(
        results,
        fetchExternalIds: _ids({
          'a:a-1': const ExternalIds(tmdb: 438631),
          'b:b-1': const ExternalIds(tmdb: 438631),
          'c:c-1': const ExternalIds(tmdb: 438631),
        }),
      );

      expect(projection.movies, hasLength(1));
      expect(projection.movies.single.sources, hasLength(3));
      expect(projection.movies.single.hasMultipleSources, isTrue);
    });

    test('two films sharing only a title stay two results', () async {
      final results = [
        _item('a-1', kind: MediaKind.movie, serverId: 'a', title: 'Dune', year: 2021),
        _item('b-1', kind: MediaKind.movie, serverId: 'b', title: 'Dune', year: 1984),
      ];

      final projection = await searchProjection(results, fetchExternalIds: _ids());

      expect(projection.movies, hasLength(2));
      expect(projection.movies.every((group) => group.sources.length == 1), isTrue);
    });

    test('conflicting strong ids never merge, however alike the titles read', () async {
      final results = [
        _item('a-1', kind: MediaKind.movie, serverId: 'a', title: 'Dune', year: 2021),
        _item('b-1', kind: MediaKind.movie, serverId: 'b', title: 'Dune', year: 2021),
      ];

      final projection = await searchProjection(
        results,
        fetchExternalIds: _ids({'a:a-1': const ExternalIds(tmdb: 438631), 'b:b-1': const ExternalIds(tmdb: 841)}),
      );

      expect(projection.movies, hasLength(2));
    });

    test('films and series are separate sections, never merged into each other', () async {
      final results = [
        _item('a-1', kind: MediaKind.movie, serverId: 'a', title: 'Dune', year: 2021),
        _item('a-2', kind: MediaKind.show, serverId: 'a', title: 'Dune', year: 2021),
      ];

      final projection = await searchProjection(results, fetchExternalIds: _ids());

      expect(projection.movies, hasLength(1));
      expect(projection.shows, hasLength(1));
    });

    test('relevance order survives grouping', () async {
      final results = [
        _item('a-1', kind: MediaKind.movie, serverId: 'a', title: 'Dune', year: 2021),
        _item('a-2', kind: MediaKind.movie, serverId: 'a', title: 'Dune: Part Two', year: 2024),
        _item('a-3', kind: MediaKind.movie, serverId: 'a', title: 'Dune Messiah', year: 2027),
      ];

      final projection = await searchProjection(results, fetchExternalIds: _ids());

      expect([for (final group in projection.movies) group.representativeSource.item.id], ['a-1', 'a-2', 'a-3']);
    });
  });

  group('searchProjection — episodes', () {
    test('two different episodes of one series never fuse into one result', () async {
      // The trap: a backend asked for an episode's external ids answers with
      // the show's. Both episodes would then carry the same strong token.
      final results = [
        _item(
          'a-e3',
          kind: MediaKind.episode,
          serverId: 'a',
          title: 'Ep 3',
          show: 'Severance',
          showId: 's1',
          season: 1,
          episode: 3,
        ),
        _item(
          'a-e7',
          kind: MediaKind.episode,
          serverId: 'a',
          title: 'Ep 7',
          show: 'Severance',
          showId: 's1',
          season: 1,
          episode: 7,
        ),
      ];

      final projection = await searchProjection(
        results,
        fetchExternalIds: (serverId, targetId) async => const ExternalIds(tmdb: 95396),
      );

      expect(projection.episodes, hasLength(2));
    });

    test('an episode is never enriched, so it can only merge on its own stable guid', () async {
      final fetched = <String>[];
      final results = [
        _item(
          'a-e3',
          kind: MediaKind.episode,
          serverId: 'a',
          title: 'Ep 3',
          guid: 'plex://episode/abc',
          show: 'Severance',
          showId: 's1',
          season: 1,
          episode: 3,
        ),
        _item(
          'b-e3',
          kind: MediaKind.episode,
          serverId: 'b',
          title: 'Ep 3',
          guid: 'plex://episode/abc',
          show: 'Severance',
          showId: 's1',
          season: 1,
          episode: 3,
        ),
      ];

      final projection = await searchProjection(
        results,
        fetchExternalIds: (serverId, targetId) async {
          fetched.add('$serverId:$targetId');
          return const ExternalIds(tmdb: 95396);
        },
      );

      expect(fetched, isEmpty);
      expect(projection.episodes, hasLength(1));
      expect(projection.episodes.single.sources, hasLength(2));
    });

    test('an episode missing its indices is left on its own', () async {
      final results = [
        _item('a-e', kind: MediaKind.episode, serverId: 'a', title: 'Ep', show: 'Severance', showId: 's1'),
        _item('b-e', kind: MediaKind.episode, serverId: 'b', title: 'Ep', show: 'Severance', showId: 's1'),
      ];

      final projection = await searchProjection(results, fetchExternalIds: _ids());

      expect(projection.episodes, hasLength(2));
    });
  });

  group('searchProjection — source-concrete sections', () {
    test('collections and playlists keep one entry per server', () async {
      final results = [
        _item('a-c', kind: MediaKind.collection, serverId: 'a', title: 'Marvel', guid: 'plex://collection/1'),
        _item('b-c', kind: MediaKind.collection, serverId: 'b', title: 'Marvel', guid: 'plex://collection/1'),
        _item('a-p', kind: MediaKind.playlist, serverId: 'a', title: 'Saturday night'),
      ];

      final projection = await searchProjection(results, fetchExternalIds: _ids());

      expect(projection.collections.map((item) => item.id), ['a-c', 'b-c']);
      expect(projection.playlists.map((item) => item.id), ['a-p']);
    });

    test('people pass straight through, and every section is preserved', () async {
      final person = _item('p-1', kind: MediaKind.unknown, serverId: 'a', title: 'Denis Villeneuve');
      final results = [
        _item('a-1', kind: MediaKind.movie, serverId: 'a', title: 'Dune', year: 2021),
        _item('a-2', kind: MediaKind.show, serverId: 'a', title: 'Severance', year: 2022),
        _item(
          'a-e3',
          kind: MediaKind.episode,
          serverId: 'a',
          title: 'Ep 3',
          show: 'Severance',
          showId: 's1',
          season: 1,
          episode: 3,
        ),
        _item('a-c', kind: MediaKind.collection, serverId: 'a', title: 'Marvel'),
        _item('a-p', kind: MediaKind.playlist, serverId: 'a', title: 'Saturday night'),
        _item('a-t', kind: MediaKind.track, serverId: 'a', title: 'Paul\'s Dream'),
      ];

      final projection = await searchProjection(results, fetchExternalIds: _ids(), people: [person]);

      expect(projection.movies, hasLength(1));
      expect(projection.shows, hasLength(1));
      expect(projection.episodes, hasLength(1));
      expect(projection.collections, hasLength(1));
      expect(projection.playlists, hasLength(1));
      expect(projection.people.single.title, 'Denis Villeneuve');
      expect(projection.other.map((item) => item.id), ['a-t']);
      expect(projection.isNotEmpty, isTrue);
    });
  });

  group('searchProjection — degraded input', () {
    test('no results at all projects to an empty projection', () async {
      final projection = await searchProjection(const [], fetchExternalIds: _ids());

      expect(projection.isEmpty, isTrue);
    });

    test('a result with no serverId is dropped rather than throwing', () async {
      final results = [
        MediaItem(id: 'orphan', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Dune', year: 2021),
        _item('a-1', kind: MediaKind.movie, serverId: 'a', title: 'Dune', year: 2021),
      ];

      final projection = await searchProjection(results, fetchExternalIds: _ids());

      expect(projection.movies, hasLength(1));
      expect(projection.movies.single.representativeSource.item.id, 'a-1');
    });

    test('a failing external-id fetch degrades the evidence, not the search', () async {
      final results = [
        _item('a-1', kind: MediaKind.movie, serverId: 'a', title: 'Dune', year: 2021),
        _item('b-1', kind: MediaKind.movie, serverId: 'b', title: 'Dune', year: 2021),
      ];

      final projection = await searchProjection(
        results,
        fetchExternalIds: (serverId, targetId) async => throw StateError('offline'),
      );

      // With the strong ids gone, hoofdstuk 11.6's title+year fallback is
      // what is left, and it applies: same kind, same normalized title, both
      // years known and equal, one candidate per server, nothing conflicting.
      // The point of the test is that the results still arrive.
      expect(projection.movies, hasLength(1));
      expect(projection.movies.single.sources.map((s) => s.item.id), ['a-1', 'b-1']);
    });

    test('a year missing on one side makes the fallback ambiguous, so no merge', () async {
      final results = [
        _item('a-1', kind: MediaKind.movie, serverId: 'a', title: 'Dune', year: 2021),
        _item('b-1', kind: MediaKind.movie, serverId: 'b', title: 'Dune'),
      ];

      final projection = await searchProjection(
        results,
        fetchExternalIds: (serverId, targetId) async => throw StateError('offline'),
      );

      expect(projection.movies, hasLength(2));
    });
  });
}
