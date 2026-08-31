/// Covers docs/qa/tvos-unified-edge-cases.md register C20/C21 and D1/D3/D4,
/// plus [UnifiedIdentityResolver]'s own I/O-orchestration contract: only
/// duplicate-bucket items ever cost a fetch, concurrency stays bounded, and
/// results are cached per (server, target) within one resolution pass.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/identity_evidence.dart';
import 'package:pleya/services/unified_catalog/identity_resolver.dart';
import 'package:pleya/utils/external_ids.dart';

MediaItem _movie(String id, {String? title = 'Dune', int? year = 2021, String serverId = 'server-a'}) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: title, year: year, serverId: serverId);

MediaItem _episode(
  String id, {
  String? show = 'Harbourlight',
  String? showId = 'show-1',
  int? season = 2,
  int? episode = 4,
  String? guid,
  String serverId = 'server-a',
}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.episode,
  title: 'Episode',
  guid: guid,
  grandparentId: showId,
  grandparentTitle: show,
  parentIndex: season,
  index: episode,
  serverId: serverId,
);

/// Exactly the shape both Continue Watching call sites build (see
/// `home_projection_service.dart` and `data_aggregation_service.dart`), so
/// what this proves about the resolver is what those two get.
ResolvableItem _continueWatching(MediaItem item) => ResolvableItem(
  item: item,
  scope: continueWatchingScope(item) ?? '',
  bucketKeyOverride: continueWatchingBucketKey(item),
  externalIdTarget: continueWatchingExternalIdTarget(item),
  externalIdDiscriminator: continueWatchingOrdinal(item),
);

Set<String> _tokenKeys(Iterable<IdentityToken> tokens) => {for (final t in tokens) t.key};

ResolvableItem _resolvable(MediaItem item) {
  final identity = canonicalIdentityOf(item)!;
  return ResolvableItem(
    item: item,
    identity: identity,
    scope: 'movie',
    externalIdTarget: (serverId: item.serverId!, targetId: item.id),
  );
}

void main() {
  group('UnifiedIdentityResolver.resolveEvidence', () {
    test('empty input resolves to no evidence without any fetch', () async {
      var calls = 0;
      final resolver = UnifiedIdentityResolver(
        fetchExternalIds: (serverId, targetId) async {
          calls++;
          return const ExternalIds();
        },
      );

      final evidence = await resolver.resolveEvidence(const []);

      expect(evidence, isEmpty);
      expect(calls, 0);
    });

    test('an item alone in its bucket never costs a fetch', () async {
      var calls = 0;
      final resolver = UnifiedIdentityResolver(
        fetchExternalIds: (serverId, targetId) async {
          calls++;
          return const ExternalIds();
        },
      );

      final evidence = await resolver.resolveEvidence([_resolvable(_movie('a'))]);

      expect(calls, 0);
      expect(evidence.single.hasStrongEvidence, isFalse);
    });

    test('only items sharing a duplicate bucket cost a fetch', () async {
      final requested = <String>[];
      final resolver = UnifiedIdentityResolver(
        fetchExternalIds: (serverId, targetId) async {
          requested.add(targetId);
          return const ExternalIds(tmdb: 1);
        },
      );

      final items = [
        _resolvable(_movie('dup-1', title: 'Dune', year: 2021)),
        _resolvable(_movie('dup-2', title: 'Dune', year: 2021)),
        _resolvable(_movie('unique', title: 'Oppenheimer', year: 2023)),
      ];

      await resolver.resolveEvidence(items);

      expect(requested, containsAll(['dup-1', 'dup-2']));
      expect(requested, isNot(contains('unique')));
    });

    test('C20: a failed fetch degrades that item to guid-only evidence instead of failing the batch', () async {
      final resolver = UnifiedIdentityResolver(
        fetchExternalIds: (serverId, targetId) async {
          if (targetId == 'fails') throw Exception('network down');
          return const ExternalIds(tmdb: 1);
        },
      );

      final items = [
        _resolvable(_movie('fails', title: 'Dune', year: 2021)),
        _resolvable(_movie('succeeds', title: 'Dune', year: 2021)),
      ];

      final evidence = await resolver.resolveEvidence(items);

      expect(evidence, hasLength(2));
      expect(evidence[0].hasStrongEvidence, isFalse);
      expect(evidence[1].hasStrongEvidence, isTrue);
    });

    test('C21: evidence reflects whatever the fetcher returns *this* call — no hidden staleness', () async {
      var version = 1;
      final resolver = UnifiedIdentityResolver(
        fetchExternalIds: (serverId, targetId) async => ExternalIds(tmdb: version),
      );
      final items = [
        _resolvable(_movie('a', title: 'Dune', year: 2021)),
        _resolvable(_movie('b', title: 'Dune', year: 2021)),
      ];

      final first = await resolver.resolveEvidence(items);
      version = 2;
      final second = await resolver.resolveEvidence(items);

      expect(first.first.strongTokens.single.value, '1');
      expect(second.first.strongTokens.single.value, '2');
    });

    test('two items targeting the same (server, target) id fetch only once', () async {
      var calls = 0;
      final resolver = UnifiedIdentityResolver(
        fetchExternalIds: (serverId, targetId) async {
          calls++;
          return const ExternalIds(tmdb: 1);
        },
      );
      final shared = (serverId: 'server-a', targetId: 'shared-target');
      final items = [
        ResolvableItem(
          item: _movie('a', title: 'Dune', year: 2021),
          identity: CanonicalMediaIdentity.movie(title: 'Dune', year: 2021),
          scope: 'movie',
          externalIdTarget: shared,
        ),
        ResolvableItem(
          item: _movie('b', title: 'Dune', year: 2021),
          identity: CanonicalMediaIdentity.movie(title: 'Dune', year: 2021),
          scope: 'movie',
          externalIdTarget: shared,
        ),
      ];

      await resolver.resolveEvidence(items);

      expect(calls, 1);
    });

    test('concurrency never exceeds maxConcurrentFetches', () async {
      var inFlight = 0;
      var maxObserved = 0;
      final resolver = UnifiedIdentityResolver(
        maxConcurrentFetches: 2,
        fetchExternalIds: (serverId, targetId) async {
          inFlight++;
          if (inFlight > maxObserved) maxObserved = inFlight;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          inFlight--;
          return const ExternalIds(tmdb: 1);
        },
      );
      final items = [for (var i = 0; i < 6; i++) _resolvable(_movie('dup-$i', title: 'Dune', year: 2021))];

      await resolver.resolveEvidence(items);

      expect(maxObserved, lessThanOrEqualTo(2));
    });
  });

  // Hoofdstuk 11.8 of docs/tvos-unified-experience.md, binding: Verder kijken
  // groups on `show identity + season + episode`, never on the series alone.
  // These prove the identity layer itself — the narrowest place that owns the
  // rule — rather than a downstream projection that happens to agree with it.
  group('Continue Watching identity (hoofdstuk 11.8)', () {
    test('an episode is scoped at episode granularity, not at its show', () {
      expect(continueWatchingScope(_episode('a')), 'episode');
      expect(continueWatchingScope(_movie('m')), 'movie');
    });

    test('the bucket key carries the season and episode, so two episodes never share one', () {
      final e4 = continueWatchingBucketKey(_episode('a', season: 2, episode: 4));
      final e5 = continueWatchingBucketKey(_episode('b', season: 2, episode: 5));
      final s1e4 = continueWatchingBucketKey(_episode('c', season: 1, episode: 4));

      expect(e4, 'episode:harbourlight:s2e4');
      expect(e4, isNot(e5));
      expect(e4, isNot(s1e4));
      expect(continueWatchingBucketKey(_episode('d', season: 2, episode: 4)), e4);
    });

    test('D6/D7: an episode with no usable ordinal has no bucket at all, so it never buys a series id', () async {
      final requested = <String>[];
      final resolver = UnifiedIdentityResolver(
        fetchExternalIds: (serverId, targetId) async {
          requested.add(targetId);
          return const ExternalIds(tmdb: 95396);
        },
      );

      final items = [
        _continueWatching(_episode('a', season: null, episode: null, serverId: 'server-a')),
        _continueWatching(_episode('b', season: null, episode: null, serverId: 'server-b')),
      ];
      final evidence = await resolver.resolveEvidence(items);

      expect(continueWatchingBucketKey(items.first.item), isNull);
      expect(requested, isEmpty, reason: 'no exact-episode bucket means no series-wide id to fold on');
      expect(evidence.every((e) => e.hasStrongEvidence), isFalse);
    });

    test('D4: a series-wide external id becomes exact-episode evidence, not series evidence', () async {
      final resolver = UnifiedIdentityResolver(fetchExternalIds: (_, _) async => const ExternalIds(tmdb: 95396));

      // Both rows are the *same* episode on two servers, so they share a
      // bucket and both resolve. The series id they come back with is the
      // same one every episode of this series would return.
      final evidence = await resolver.resolveEvidence([
        _continueWatching(_episode('a', season: 2, episode: 4, serverId: 'server-a')),
        _continueWatching(_episode('b', season: 2, episode: 4, serverId: 'server-b')),
      ]);

      expect(_tokenKeys(evidence[0].strongTokens), {'episode:tmdb:95396/s2e4'});
      expect(
        _tokenKeys(evidence[1].strongTokens),
        _tokenKeys(evidence[0].strongTokens),
        reason: 'the same episode on two servers shares one token — that is the merge',
      );
    });

    test('E: two episodes forced into one bucket still get different tokens from one series id', () async {
      // The bucket key already separates S02E04 from S02E05, so the fetch
      // normally never happens. This forces it anyway — a hand-made shared
      // bucket override — to prove the *token* is the second line of defence
      // and not just an artefact of the bucket: give both rows the identical
      // series tmdb AND tvdb and they must still disagree.
      final resolver = UnifiedIdentityResolver(
        fetchExternalIds: (_, _) async => const ExternalIds(tmdb: 95396, tvdb: 371980),
      );
      ResolvableItem forced(MediaItem item) => ResolvableItem(
        item: item,
        scope: continueWatchingScope(item) ?? '',
        bucketKeyOverride: 'forced-shared-bucket',
        externalIdTarget: continueWatchingExternalIdTarget(item),
        externalIdDiscriminator: continueWatchingOrdinal(item),
      );

      final evidence = await resolver.resolveEvidence([
        forced(_episode('a', season: 2, episode: 4, serverId: 'server-a')),
        forced(_episode('b', season: 2, episode: 5, serverId: 'server-b')),
      ]);

      expect(_tokenKeys(evidence[0].strongTokens), {'episode:tmdb:95396/s2e4', 'episode:tvdb:371980/s2e4'});
      expect(_tokenKeys(evidence[1].strongTokens), {'episode:tmdb:95396/s2e5', 'episode:tvdb:371980/s2e5'});
      expect(
        _tokenKeys(evidence[0].strongTokens).intersection(_tokenKeys(evidence[1].strongTokens)),
        isEmpty,
        reason: 'a series-wide id must never be evidence two different episodes share',
      );
    });

    test('D3: an episode guid is exact-episode evidence and contributes on its own', () async {
      final resolver = UnifiedIdentityResolver(fetchExternalIds: (_, _) async => const ExternalIds());

      final evidence = await resolver.resolveEvidence([
        _continueWatching(_episode('a', guid: 'plex://episode/5d9c08', serverId: 'server-a')),
      ]);

      expect(_tokenKeys(evidence.single.strongTokens), {'episode:guid:plex://episode/5d9c08'});
    });

    test('a season row is scoped and bucketed at its own season, not at its show', () {
      final s1 = MediaItem(
        id: 's1',
        backend: MediaBackend.plex,
        kind: MediaKind.season,
        title: 'Season 1',
        grandparentTitle: 'Harbourlight',
        index: 1,
        serverId: 'server-a',
      );
      final s2 = s1.copyWith(id: 's2', index: 2);

      expect(continueWatchingScope(s1), 'season');
      expect(continueWatchingBucketKey(s1), 'season:harbourlight:s1');
      expect(continueWatchingBucketKey(s2), isNot(continueWatchingBucketKey(s1)));
      expect(continueWatchingOrdinal(s2), 's2');
    });

    test('a movie carries no ordinal and keeps the identity it always had', () {
      final movie = _movie('m', title: 'The Long Harbour');

      expect(continueWatchingOrdinal(movie), isNull);
      expect(continueWatchingBucketKey(movie), 'movie:the long harbour');
    });
  });
}
