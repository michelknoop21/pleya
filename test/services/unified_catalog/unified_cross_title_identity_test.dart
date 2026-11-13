/// One title under two names on two servers is still one card.
///
/// Verder kijken used to compare series numbers only inside a shared title
/// bucket, so "La Casa de Papel" on one server and "Money Heist" on the other
/// stayed two cards. A Plex library on an old agent kept its number in the
/// guid, where the carried-id path did not look. Both are covered here, plus
/// the session cache that keeps the extra lookups from repeating.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/carried_external_ids.dart';
import 'package:pleya/media/unified/identity_evidence.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/unified_catalog/grouping_service.dart';
import 'package:pleya/services/unified_catalog/identity_lookup_cache.dart';
import 'package:pleya/services/unified_catalog/identity_resolver.dart';
import 'package:pleya/utils/external_ids.dart';

MediaItem _episode(
  String id, {
  required String show,
  required String showId,
  required String server,
  int season = 1,
  int episode = 8,
  int? lastViewedAt,
  MediaBackend backend = MediaBackend.plex,
}) => MediaItem(
  id: id,
  backend: backend,
  kind: MediaKind.episode,
  title: 'Episode',
  grandparentId: showId,
  grandparentTitle: show,
  parentIndex: season,
  index: episode,
  serverId: server,
  serverName: server,
  lastViewedAt: lastViewedAt,
);

/// The Verder kijken pipeline both call sites run (`home_projection_service.dart`
/// and `data_aggregation_service.dart`), with [seriesIds] as the servers' answers.
Future<({List<UnifiedMediaGroup> groups, List<String> lookups})> _continueWatching(
  List<MediaItem> items,
  Map<String, ExternalIds> seriesIds, {
  List<String?>? lookupKeys,
}) async {
  final lookups = <String>[];
  final resolver = UnifiedIdentityResolver(
    fetchExternalIds: (serverId, targetId) async {
      lookups.add('$serverId:$targetId');
      return seriesIds['$serverId:$targetId'] ?? const ExternalIds();
    },
  );
  final keys = lookupKeys ?? continueWatchingLookupKeys(items);
  final evidence = await resolver.resolveEvidence([
    for (final (i, item) in items.indexed)
      ResolvableItem(
        item: item,
        scope: continueWatchingScope(item) ?? '',
        bucketKeyOverride: keys[i],
        externalIdTarget: continueWatchingExternalIdTarget(item),
        externalIdDiscriminator: continueWatchingOrdinal(item),
      ),
  ]);
  final bySource = <String, IdentityEvidence>{};
  final candidates = <GroupingCandidate>[];
  for (final (i, item) in items.indexed) {
    final source = UnifiedMediaSource.fromItem(item);
    bySource[source.sourceKey] = evidence[i];
    candidates.add(GroupingCandidate(source: source, evidence: evidence[i]));
  }
  return (
    groups: oneContinueWatchingCardPerSeries(groupUnifiedMediaSources(candidates, allowWeakFallback: false), bySource),
    lookups: lookups,
  );
}

class _CountingClient implements MediaServerClient {
  _CountingClient(this._serverId, this.answer);
  final String _serverId;
  Future<ExternalIds> Function(String id) answer;
  int calls = 0;

  @override
  ServerId get serverId => ServerId(_serverId);

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) {
    calls++;
    return answer(itemId);
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Verder kijken across servers with differing series titles', () {
    final plex = _episode('p-e8', show: 'La Casa de Papel', showId: 'p-show', server: 'srv-plex');
    final other = _episode(
      'j-e8',
      show: 'Money Heist',
      showId: 'j-show',
      server: 'srv-jf',
      backend: MediaBackend.jellyfin,
    );
    const sameSeries = {'srv-plex:p-show': ExternalIds(tmdb: 71446), 'srv-jf:j-show': ExternalIds(tmdb: 71446)};

    test('the same episode under two series titles is one card with two sources', () async {
      final result = await _continueWatching([plex, other], sameSeries);

      expect(result.groups, hasLength(1));
      expect(result.groups.single.sources, hasLength(2));
      expect(result.lookups, unorderedEquals(['srv-plex:p-show', 'srv-jf:j-show']));
    });

    test('negative control: the title bucket alone leaves two cards and asks nothing', () async {
      final result = await _continueWatching(
        [plex, other],
        sameSeries,
        lookupKeys: [continueWatchingBucketKey(plex), continueWatchingBucketKey(other)],
      );

      expect(result.groups, hasLength(2));
      expect(result.lookups, isEmpty);
    });

    test('two different episodes of that series keep only the most recently watched card', () async {
      final older = _episode(
        'p-e7',
        show: 'La Casa de Papel',
        showId: 'p-show',
        server: 'srv-plex',
        episode: 7,
        lastViewedAt: 100,
      );
      final newer = _episode(
        'j-e8',
        show: 'Money Heist',
        showId: 'j-show',
        server: 'srv-jf',
        backend: MediaBackend.jellyfin,
        lastViewedAt: 200,
      );

      final result = await _continueWatching([older, newer], sameSeries);

      expect(result.groups.map((g) => g.sources.single.item.id), ['j-e8']);
    });

    test('series with different numbers stay apart, whatever their titles', () async {
      final result = await _continueWatching(
        [plex, other],
        const {'srv-plex:p-show': ExternalIds(tmdb: 71446), 'srv-jf:j-show': ExternalIds(tmdb: 1399)},
      );

      expect(result.groups, hasLength(2));
    });

    test('a failed lookup keeps the two cards apart instead of guessing', () async {
      final result = await _continueWatching([plex, other], const {'srv-plex:p-show': ExternalIds(tmdb: 71446)});

      expect(result.groups, hasLength(2));
    });
  });

  group('continueWatchingLookupKeys', () {
    test('one server keeps the title bucket, so a single-server row asks nothing extra', () {
      final a = _episode('a', show: 'Harbourlight', showId: 's1', server: 'srv-plex');
      final b = _episode('b', show: 'Tidewater', showId: 's2', server: 'srv-plex');

      expect(continueWatchingLookupKeys([a, b]), [continueWatchingBucketKey(a), continueWatchingBucketKey(b)]);
    });

    test('a scope present on two servers shares one bucket per scope', () {
      final a = _episode('a', show: 'Harbourlight', showId: 's1', server: 'srv-plex');
      final b = _episode('b', show: 'Tidewater', showId: 's2', server: 'srv-jf', backend: MediaBackend.jellyfin);
      final movie = MediaItem(
        id: 'm',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'Dune',
        serverId: 'srv-plex',
      );

      expect(continueWatchingLookupKeys([a, b, movie]), ['episode:*', 'episode:*', continueWatchingBucketKey(movie)]);
    });

    test('a local source and an episode without ordinal never join the shared bucket', () {
      final a = _episode('a', show: 'Harbourlight', showId: 's1', server: 'srv-plex');
      final local = _episode('l', show: 'Harbourlight', showId: 's9', server: 'srv-local', backend: MediaBackend.local);
      final noOrdinal = MediaItem(
        id: 'n',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.episode,
        grandparentId: 's3',
        grandparentTitle: 'Harbourlight',
        serverId: 'srv-jf',
      );

      expect(continueWatchingLookupKeys([a, local, noOrdinal]), [
        continueWatchingBucketKey(a),
        continueWatchingBucketKey(local),
        null,
      ]);
    });
  });

  group('a Plex library on an old agent', () {
    MediaItem legacyPlex(String guid, {String title = 'Die Verurteilten', Map<String, Object?>? raw}) => MediaItem.plex(
      id: 'p1',
      kind: MediaKind.movie,
      title: title,
      year: 1995,
      guid: guid,
      serverId: 'srv-plex',
      serverName: 'srv-plex',
      raw: raw,
    );
    final jellyfin = MediaItem.jellyfin(
      id: 'j1',
      kind: MediaKind.movie,
      title: 'The Shawshank Redemption',
      year: 1994,
      serverId: 'srv-jf',
      serverName: 'srv-jf',
      raw: const {
        'ProviderIds': {'Imdb': 'tt0111161'},
      },
    );

    test('its guid number counts as a carried number', () {
      expect(externalIdsCarriedBy(legacyPlex('com.plexapp.agents.imdb://tt0111161?lang=de'))?.imdb, 'tt0111161');
      expect(externalIdsCarriedBy(legacyPlex('com.plexapp.agents.themoviedb://278?lang=en'))?.tmdb, 278);
    });

    test('a usable Guid array still wins over the guid', () {
      final item = legacyPlex(
        'com.plexapp.agents.imdb://tt0000001',
        raw: const {
          'Guid': [
            {'id': 'imdb://tt0111161'},
          ],
        },
      );
      expect(externalIdsCarriedBy(item)?.imdb, 'tt0111161');
    });

    test('an unmatched or modern guid carries nothing more than before', () {
      expect(externalIdsCarriedBy(legacyPlex('com.plexapp.agents.none://abc')), isNull);
      expect(
        externalIdsCarriedBy(legacyPlex('plex://movie/abc', raw: const {'Guid': <Object>[]})),
        const ExternalIds(),
      );
    });

    test('merges with the same film under another title and year, without a request', () async {
      var calls = 0;
      final resolver = UnifiedIdentityResolver(
        fetchExternalIds: (_, _) async {
          calls++;
          return const ExternalIds();
        },
      );
      final items = [legacyPlex('com.plexapp.agents.imdb://tt0111161?lang=de'), jellyfin];
      final evidence = await resolver.resolveEvidence([
        for (final item in items)
          ResolvableItem(
            item: item,
            identity: canonicalIdentityOf(item),
            scope: 'movie',
            externalIdTarget: (serverId: item.serverId!, targetId: item.id),
          ),
      ]);
      final groups = groupUnifiedMediaSources([
        for (final (i, item) in items.indexed)
          GroupingCandidate(source: UnifiedMediaSource.fromItem(item), evidence: evidence[i]),
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.sources, hasLength(2));
      expect(calls, 0);
    });
  });

  group('a caller that declines the lookup', () {
    test('still reads the numbers the item carries, so guid and number meet', () async {
      final plex = MediaItem.plex(
        id: 'p1',
        kind: MediaKind.movie,
        title: 'Léon',
        year: 1994,
        guid: 'plex://movie/5d7768296f4521001ea9c1a5',
        serverId: 'srv-plex',
        serverName: 'srv-plex',
        raw: const {
          'Guid': [
            {'id': 'tmdb://101'},
          ],
        },
      );
      final jellyfin = MediaItem.jellyfin(
        id: 'j1',
        kind: MediaKind.movie,
        title: 'Léon: The Professional',
        year: 1995,
        serverId: 'srv-jf',
        serverName: 'srv-jf',
        raw: const {
          'ProviderIds': {'Tmdb': '101'},
        },
      );
      final items = [plex, jellyfin];
      final evidence =
          await UnifiedIdentityResolver(
            fetchExternalIds: (_, _) async => fail('the numbers are on the items'),
          ).resolveEvidence([
            for (final item in items)
              // The assistant's shape: no target for an item with a stable guid.
              ResolvableItem(
                item: item,
                identity: canonicalIdentityOf(item),
                scope: 'movie',
                externalIdTarget: normalizeStableGuid(item.guid) == null
                    ? (serverId: item.serverId!, targetId: item.id)
                    : null,
              ),
          ]);
      final groups = groupUnifiedMediaSources([
        for (final (i, item) in items.indexed)
          GroupingCandidate(source: UnifiedMediaSource.fromItem(item), evidence: evidence[i]),
      ]);

      expect(groups, hasLength(1));
    });
  });

  group('fetchExternalIdsForIdentity', () {
    late MultiServerManager manager;
    late _CountingClient client;
    setUp(() {
      manager = MultiServerManager();
      addTearDown(manager.dispose);
      client = _CountingClient('srv-plex', (_) async => const ExternalIds(tmdb: 71446));
      manager.debugRegisterClientForTesting(client);
    });

    test('asks a server once per target and reuses the answer', () async {
      final first = await fetchExternalIdsForIdentity(manager, 'srv-plex', 'show-1');
      final second = await fetchExternalIdsForIdentity(manager, 'srv-plex', 'show-1');
      await fetchExternalIdsForIdentity(manager, 'srv-plex', 'show-2');

      expect(first, second);
      expect(client.calls, 2);
    });

    test('a failed lookup is not remembered', () async {
      client.answer = (_) async => throw StateError('offline');
      await expectLater(fetchExternalIdsForIdentity(manager, 'srv-plex', 'show-1'), throwsStateError);
      client.answer = (_) async => const ExternalIds(tmdb: 71446);

      expect((await fetchExternalIdsForIdentity(manager, 'srv-plex', 'show-1')).tmdb, 71446);
      expect(client.calls, 2);
    });

    test('an answer older than the ttl is asked again', () async {
      var clock = DateTime(2026, 11, 13, 20);
      await fetchExternalIdsForIdentity(manager, 'srv-plex', 'show-1', now: () => clock);
      clock = clock.add(identityLookupTtl + const Duration(seconds: 1));
      await fetchExternalIdsForIdentity(manager, 'srv-plex', 'show-1', now: () => clock);

      expect(client.calls, 2);
    });

    test('a server without a client throws, so the item degrades to its guid', () async {
      await expectLater(fetchExternalIdsForIdentity(manager, 'srv-gone', 'show-1'), throwsStateError);
    });
  });
}
