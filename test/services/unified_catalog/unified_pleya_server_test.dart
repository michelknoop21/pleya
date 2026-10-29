/// Pleya Server as a full member of the unified library (DEC-XXX).
///
/// Three layers, each answering a different question:
///
/// * grouping: which sources fold into one card, and which must not;
/// * catalog service: the same answer through paging, refresh, restart and
///   unlinking, with a real [PleyaServerClient] talking to the fixture server
///   next to fake Plex, Jellyfin and Emby clients;
/// * activation: that a merged card keeps every source usable, so one server
///   being down never hides another one.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/identity_evidence.dart';
import 'package:pleya/media/unified/source_availability.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_route_context.dart';
import 'package:pleya/services/playback_initialization_types.dart';
import 'package:pleya/services/pleya_server_client.dart';
import 'package:pleya/services/unified_catalog/catalog_service.dart';
import 'package:pleya/services/unified_catalog/grouping_service.dart';
import 'package:pleya/services/unified_catalog/home_projection_service.dart';
import 'package:pleya/services/unified_catalog/search_projection.dart';
import 'package:pleya/services/unified_catalog/source_cursor.dart';
import 'package:pleya/services/unified_catalog/source_resolver.dart' show isIdentityEligibleBackend;
import 'package:pleya/services/unified_catalog/unified_activation_coordinator.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_snapshot.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/media_server_http_client.dart';

import '../../pleya_server/pleya_fake_server.dart';

// -- Shared building blocks ----------------------------------------------------

/// The four backends the user can have linked. Emby is the Jellyfin backend
/// with the server id registered as Emby (DEC-141).
enum _Flavor { plex, jellyfin, emby, pleya }

extension on _Flavor {
  MediaBackend get backend => switch (this) {
    _Flavor.plex => MediaBackend.plex,
    _Flavor.jellyfin || _Flavor.emby => MediaBackend.jellyfin,
    _Flavor.pleya => MediaBackend.pleyaServer,
  };
}

const _allFlavors = _Flavor.values;

List<List<_Flavor>> _pairs() => [
  for (var i = 0; i < _allFlavors.length; i++)
    for (var j = i + 1; j < _allFlavors.length; j++) [_allFlavors[i], _allFlavors[j]],
];

MediaItem _item(
  _Flavor flavor, {
  required String serverId,
  required String id,
  required String title,
  int? year,
  MediaKind kind = MediaKind.movie,
  int? index,
  int? parentIndex,
  String? grandparentTitle,
  String? grandparentId,
}) {
  if (flavor == _Flavor.emby) embyServerIds.add(serverId);
  return MediaItem(
    id: id,
    backend: flavor.backend,
    kind: kind,
    title: title,
    year: year,
    index: index,
    parentIndex: parentIndex,
    grandparentTitle: grandparentTitle,
    grandparentId: grandparentId,
    serverId: serverId,
    serverName: serverId,
  );
}

GroupingCandidate _candidate(MediaItem item, {ExternalIds ids = const ExternalIds()}) {
  final identity = canonicalIdentityOf(item) ?? CanonicalMediaIdentity.opaque();
  final scope = identity.granularity.name;
  return GroupingCandidate(
    source: UnifiedMediaSource.fromItem(item, externalIds: ids),
    evidence: IdentityEvidence(
      identity: identity,
      strongTokens: {
        ...guidTokens(scope: scope, guid: item.guid, kind: item.kind),
        ...externalIdTokens(scope: scope, ids: ids),
      },
    ),
  );
}

void main() {
  tearDown(embyServerIds.clear);

  group('grouping', () {
    test('every one of the six backend pairs folds one film with a shared TMDB number into a single card', () {
      for (final pair in _pairs()) {
        final groups = groupUnifiedMediaSources([
          for (final (i, flavor) in pair.indexed)
            _candidate(
              _item(flavor, serverId: 'srv-$i', id: 'film-$i', title: 'Dune', year: 2021),
              ids: const ExternalIds(tmdb: 438631),
            ),
        ]);

        expect(groups, hasLength(1), reason: '$pair');
        expect(groups.single.sources, hasLength(2), reason: '$pair');
        expect(groups.single.sources.map((s) => s.backend).toSet(), {for (final f in pair) f.backend}, reason: '$pair');
      }
    });

    test('all four at once give one card with four sources, each still its own concrete item', () {
      final candidates = [
        for (final (i, flavor) in _allFlavors.indexed)
          _candidate(
            _item(flavor, serverId: 'srv-$i', id: 'film-$i', title: 'Dune', year: 2021),
            ids: const ExternalIds(tmdb: 438631),
          ),
      ];

      final groups = groupUnifiedMediaSources(candidates);

      expect(groups, hasLength(1));
      expect(
        groups.single.sources.map((s) => s.sourceKey),
        unorderedEquals(['srv-0:film-0', 'srv-1:film-1', 'srv-2:film-2', 'srv-3:film-3']),
      );
      expect(groups.single.sources.map((s) => s.item.id), unorderedEquals(['film-0', 'film-1', 'film-2', 'film-3']));
    });

    test('several servers of one type fold together as well, Plex twice and Pleya Server twice', () {
      final groups = groupUnifiedMediaSources([
        for (final (i, flavor) in [_Flavor.plex, _Flavor.plex, _Flavor.pleya, _Flavor.pleya].indexed)
          _candidate(
            _item(flavor, serverId: 'srv-$i', id: 'show-$i', title: 'Severance', year: 2022, kind: MediaKind.show),
            ids: const ExternalIds(tmdb: 95396),
          ),
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.sources, hasLength(4));
    });

    test('a number that disagrees keeps same-named titles apart, for every pair that includes Pleya Server', () {
      for (final other in [_Flavor.plex, _Flavor.jellyfin, _Flavor.emby, _Flavor.pleya]) {
        final groups = groupUnifiedMediaSources([
          _candidate(
            _item(_Flavor.pleya, serverId: 'srv-p', id: 'p', title: 'Same Name', year: 2020),
            ids: const ExternalIds(tmdb: 6),
          ),
          _candidate(
            _item(other, serverId: 'srv-o', id: 'o', title: 'Same Name', year: 2020),
            ids: const ExternalIds(tmdb: 5),
          ),
        ]);

        expect(groups, hasLength(2), reason: 'pleya vs $other');
      }
    });

    test('a remake with another year and another number stays a separate card', () {
      final groups = groupUnifiedMediaSources([
        _candidate(
          _item(_Flavor.plex, serverId: 'srv-a', id: 'a', title: 'Dune', year: 1984),
          ids: const ExternalIds(tmdb: 841),
        ),
        _candidate(
          _item(_Flavor.pleya, serverId: 'srv-p', id: 'p', title: 'Dune', year: 2021),
          ids: const ExternalIds(tmdb: 438631),
        ),
      ]);

      expect(groups, hasLength(2));
    });

    test('same title, same year and no proof on the Pleya Server side stays two cards, each named by its server', () {
      final groups = groupUnifiedMediaSources([
        _candidate(
          _item(_Flavor.plex, serverId: 'srv-a', id: 'a', title: 'Dune', year: 2021),
          ids: const ExternalIds(tmdb: 438631),
        ),
        _candidate(_item(_Flavor.pleya, serverId: 'srv-p', id: 'p', title: 'Dune', year: 2021)),
      ]);

      expect(groups, hasLength(2));
      expect({for (final g in groups) g.sources.single.backend}, {MediaBackend.plex, MediaBackend.pleyaServer});
    });

    test('two Pleya Servers without any proof never fold on title and year', () {
      final groups = groupUnifiedMediaSources([
        _candidate(_item(_Flavor.pleya, serverId: 'srv-1', id: 'a', title: 'Dune', year: 2021)),
        _candidate(_item(_Flavor.pleya, serverId: 'srv-2', id: 'b', title: 'Dune', year: 2021)),
      ]);

      expect(groups, hasLength(2));
    });

    test('a Pleya Server with only a TMDB number and a Plex source with only a TVDB number share no proof', () {
      final groups = groupUnifiedMediaSources([
        _candidate(
          _item(_Flavor.plex, serverId: 'srv-a', id: 'a', title: 'Dune', year: 2021),
          ids: const ExternalIds(tvdb: 7),
        ),
        _candidate(
          _item(_Flavor.pleya, serverId: 'srv-p', id: 'p', title: 'Dune', year: 2021),
          ids: const ExternalIds(tmdb: 438631),
        ),
      ]);

      expect(groups, hasLength(2));
    });

    test('Plex and Jellyfin keep their title+year fallback; the Pleya rule did not touch it', () {
      final groups = groupUnifiedMediaSources([
        _candidate(_item(_Flavor.plex, serverId: 'srv-a', id: 'a', title: 'Dune', year: 2021)),
        _candidate(_item(_Flavor.jellyfin, serverId: 'srv-j', id: 'j', title: 'Dune', year: 2021)),
      ]);

      expect(groups, hasLength(1));
    });

    test('a movie and a show that share a numeric TMDB id are different titles', () {
      final groups = groupUnifiedMediaSources([
        _candidate(
          _item(_Flavor.plex, serverId: 'srv-a', id: 'm', title: 'Twins', year: 2020),
          ids: const ExternalIds(tmdb: 1100),
        ),
        _candidate(
          _item(_Flavor.pleya, serverId: 'srv-p', id: 's', title: 'Twins', year: 2020, kind: MediaKind.show),
          ids: const ExternalIds(tmdb: 1100),
        ),
      ]);

      expect(groups, hasLength(2));
    });

    test('a chain that would join two different numbers through a bridging source falls back to separate cards', () {
      // Plex: tmdb 1 + imdb tt1. Jellyfin: imdb tt1 + tmdb 2. Pleya Server: tmdb 2.
      // The imdb number bridges Plex and Jellyfin although they disagree on tmdb.
      final groups = groupUnifiedMediaSources([
        _candidate(
          _item(_Flavor.plex, serverId: 'srv-a', id: 'a', title: 'Dune', year: 2021),
          ids: const ExternalIds(tmdb: 1, imdb: 'tt1'),
        ),
        _candidate(
          _item(_Flavor.jellyfin, serverId: 'srv-j', id: 'j', title: 'Dune', year: 2021),
          ids: const ExternalIds(tmdb: 2, imdb: 'tt1'),
        ),
        _candidate(
          _item(_Flavor.pleya, serverId: 'srv-p', id: 'p', title: 'Dune', year: 2021),
          ids: const ExternalIds(tmdb: 2),
        ),
      ]);

      expect(groups, hasLength(3));
    });

    test('a Pleya Share source (the local backend) stays on its own, even with a matching number', () {
      final groups = groupUnifiedMediaSources([
        _candidate(
          _item(_Flavor.plex, serverId: 'srv-a', id: 'a', title: 'Dune', year: 2021),
          ids: const ExternalIds(tmdb: 438631),
        ),
        _candidate(
          MediaItem(
            id: 'share-1',
            backend: MediaBackend.local,
            kind: MediaKind.movie,
            title: 'Dune',
            year: 2021,
            serverId: 'share',
            serverName: 'Share',
          ),
          ids: const ExternalIds(tmdb: 438631),
        ),
      ]);

      expect(groups, hasLength(2));
    });

    group('episodes (Continue Watching grain)', () {
      // An episode is identified by its show plus season and episode number.
      // The show's number is the evidence, the ordinal is the discriminator.
      GroupingCandidate episode(
        _Flavor flavor,
        String serverId, {
        required int season,
        required int episode,
        int tmdb = 95396,
      }) {
        final item = _item(
          flavor,
          serverId: serverId,
          id: 'ep-$serverId-$season-$episode',
          title: 'Hello, Ms. Cobel',
          kind: MediaKind.episode,
          grandparentTitle: 'Severance',
          parentIndex: season,
          index: episode,
        );
        final identity = canonicalIdentityOf(item)!;
        return GroupingCandidate(
          source: UnifiedMediaSource.fromItem(item, externalIds: ExternalIds(tmdb: tmdb)),
          evidence: IdentityEvidence(
            identity: identity,
            strongTokens: externalIdTokens(
              scope: 'episode',
              ids: ExternalIds(tmdb: tmdb),
              discriminator: 's${season}e$episode',
            ),
          ),
        );
      }

      test('the same episode of the same show on Plex and on Pleya Server is one entry', () {
        final groups = groupUnifiedMediaSources([
          episode(_Flavor.plex, 'srv-a', season: 2, episode: 4),
          episode(_Flavor.pleya, 'srv-p', season: 2, episode: 4),
        ]);

        expect(groups, hasLength(1));
        expect(groups.single.sources, hasLength(2));
      });

      test(
        'different numbering is never silently equated: S02E04 and S01E04 stay apart, and so does an absolute count',
        () {
          final groups = groupUnifiedMediaSources([
            episode(_Flavor.plex, 'srv-a', season: 2, episode: 4),
            episode(_Flavor.pleya, 'srv-p', season: 1, episode: 4),
            // A server numbering the same episode absolutely (S01E14) is not S02E04.
            episode(_Flavor.jellyfin, 'srv-j', season: 1, episode: 14),
          ]);

          expect(groups, hasLength(3));
        },
      );

      test('the same ordinal under a different show is another episode', () {
        final groups = groupUnifiedMediaSources([
          episode(_Flavor.plex, 'srv-a', season: 2, episode: 4),
          episode(_Flavor.pleya, 'srv-p', season: 2, episode: 4, tmdb: 1),
        ]);

        expect(groups, hasLength(2));
      });

      test('seasons follow the same rule: show number plus season number, nothing looser', () {
        GroupingCandidate season(_Flavor flavor, String serverId, {required int season, int? tmdb = 95396}) {
          final item = _item(
            flavor,
            serverId: serverId,
            id: 'season-$serverId-$season',
            title: 'Season $season',
            kind: MediaKind.season,
            grandparentTitle: 'Severance',
            index: season,
          ).copyWith(parentTitle: 'Severance');
          final identity = canonicalIdentityOf(item)!;
          final ids = ExternalIds(tmdb: tmdb);
          return GroupingCandidate(
            source: UnifiedMediaSource.fromItem(item, externalIds: ids),
            evidence: IdentityEvidence(
              identity: identity,
              strongTokens: tmdb == null
                  ? const {}
                  : externalIdTokens(scope: 'season', ids: ids, discriminator: 's$season'),
            ),
          );
        }

        expect(
          groupUnifiedMediaSources([
            season(_Flavor.plex, 'srv-a', season: 2),
            season(_Flavor.pleya, 'srv-p', season: 2),
          ]),
          hasLength(1),
        );
        expect(
          groupUnifiedMediaSources([
            season(_Flavor.plex, 'srv-a', season: 2),
            season(_Flavor.pleya, 'srv-p', season: 1),
          ]),
          hasLength(2),
          reason: 'a season the other server lacks is not another server\'s season 1',
        );
        expect(
          groupUnifiedMediaSources([
            season(_Flavor.plex, 'srv-a', season: 2),
            season(_Flavor.pleya, 'srv-p', season: 2, tmdb: null),
          ]),
          hasLength(2),
          reason: 'no proven show number, no fold',
        );
      });

      test('an episode without a proven show number does not fold on its title', () {
        final plexEpisode = episode(_Flavor.plex, 'srv-a', season: 2, episode: 4);
        final pleyaItem = _item(
          _Flavor.pleya,
          serverId: 'srv-p',
          id: 'ep-p',
          title: 'Hello, Ms. Cobel',
          kind: MediaKind.episode,
          grandparentTitle: 'Severance',
          parentIndex: 2,
          index: 4,
        );

        final groups = groupUnifiedMediaSources([plexEpisode, _candidate(pleyaItem)]);

        expect(groups, hasLength(2));
      });
    });
  });

  group('catalog service across Plex, Jellyfin, Emby and a real Pleya Server client', () {
    late List<PleyaServerClient> opened;

    setUp(() => opened = []);
    tearDown(() {
      for (final c in opened) {
        c.close();
      }
    });

    PleyaServerClient pleyaClient(PleyaFakeServer fake, {required String serverId}) {
      final client = PleyaServerClient.create(
        PleyaServerConnection(
          id: 'pleyaServer.$serverId',
          baseUrl: 'http://$serverId.lan:8832',
          serverId: serverId,
          serverName: serverId,
          userName: 'michel',
          refreshToken: 'rt-1',
          createdAt: DateTime.utc(2026, 8, 19),
        ),
        httpClientFactory: fake.asHttpClient,
      );
      opened.add(client);
      return client;
    }

    PleyaFakeServer pleyaServer(
      Map<String, ({String title, int year, int? tmdb})> shows, {
      bool reportsExternalIds = true,
    }) {
      final fake = PleyaFakeServer()..reportsExternalIds = reportsExternalIds;
      fake.addLibrary(id: 'lib-series', title: 'Series', kind: 'shows');
      for (final entry in shows.entries) {
        fake.addItem(
          id: entry.key,
          kind: 'show',
          title: entry.value.title,
          libraryId: 'lib-series',
          year: entry.value.year,
          externalIds: entry.value.tmdb == null ? null : {'tmdb': entry.value.tmdb},
        );
      }
      return fake;
    }

    CatalogLibrary library(String serverId, MediaBackend backend, {String libraryId = 'lib-series'}) => (
      serverId: ServerId(serverId),
      serverName: serverId,
      libraryId: libraryId,
      backend: backend,
      libraryTitle: libraryId,
    );

    Future<UnifiedCatalogSnapshot> drain(UnifiedCatalogService service) async {
      var snapshot = await service.loadMore();
      var rounds = 0;
      while (!snapshot.isComplete && rounds++ < 50) {
        snapshot = await service.loadMore();
      }
      expect(snapshot.isComplete, isTrue, reason: 'the catalog stopped paging');
      return snapshot;
    }

    Map<String, List<String>> titlesToSources(UnifiedCatalogSnapshot snapshot) => {
      for (final g in snapshot.groups)
        g.representativeSource.item.title ?? '?': [for (final s in g.sources) s.sourceKey]..sort(),
    };

    const query = UnifiedCatalogQuery(kind: MediaKind.show);

    test('Plex and Pleya Server side by side: one duplicate series, one card, both sources playable', () async {
      final plex = _FakeServerClient(
        MediaBackend.plex,
        shows: [
          _show('plex-sev', 'Severance', 2022, serverId: 'srv-plex', backend: MediaBackend.plex),
          _show('plex-only', 'Plex Only', 2019, serverId: 'srv-plex', backend: MediaBackend.plex),
        ],
        ids: {'plex-sev': const ExternalIds(tmdb: 95396, tvdb: 371980)},
      );
      final pleya = pleyaClient(
        pleyaServer({
          'ps-sev': (title: 'Severance', year: 2022, tmdb: 95396),
          'ps-only': (title: 'Pleya Only', year: 2024, tmdb: 1),
        }),
        serverId: 'srv-pleya',
      );
      await pleya.refreshCapabilities();
      final service = UnifiedCatalogService(
        query: query,
        libraries: [library('srv-plex', MediaBackend.plex), library('srv-pleya', MediaBackend.pleyaServer)],
        clientFor: (id) => id.value == 'srv-plex' ? plex : pleya,
      );

      final snapshot = await drain(service);

      expect(titlesToSources(snapshot), {
        'Severance': ['srv-plex:plex-sev', 'srv-pleya:ps-sev'],
        'Plex Only': ['srv-plex:plex-only'],
        'Pleya Only': ['srv-pleya:ps-only'],
      });
      final severance = snapshot.groups.firstWhere((g) => g.representativeSource.item.title == 'Severance');
      expect(
        severance.sources.map((s) => s.item.backend),
        unorderedEquals([MediaBackend.plex, MediaBackend.pleyaServer]),
      );
    });

    test('all four backends in one catalog: the shared series is one card with four sources', () async {
      final plex = _FakeServerClient(
        MediaBackend.plex,
        shows: [_show('plex-sev', 'Severance', 2022, serverId: 'srv-plex', backend: MediaBackend.plex)],
        ids: {'plex-sev': const ExternalIds(tmdb: 95396)},
      );
      final jellyfin = _FakeServerClient(
        MediaBackend.jellyfin,
        shows: [_show('jf-sev', 'Severance', 2022, serverId: 'srv-jf', backend: MediaBackend.jellyfin)],
        ids: {'jf-sev': const ExternalIds(tmdb: 95396)},
      );
      embyServerIds.add('srv-emby');
      final emby = _FakeServerClient(
        MediaBackend.jellyfin,
        shows: [_show('emby-sev', 'Severance', 2022, serverId: 'srv-emby', backend: MediaBackend.jellyfin)],
        ids: {'emby-sev': const ExternalIds(tmdb: 95396)},
      );
      final pleya = pleyaClient(
        pleyaServer({'ps-sev': (title: 'Severance', year: 2022, tmdb: 95396)}),
        serverId: 'srv-pleya',
      );
      await pleya.refreshCapabilities();
      final clients = <String, MediaServerClient>{
        'srv-plex': plex,
        'srv-jf': jellyfin,
        'srv-emby': emby,
        'srv-pleya': pleya,
      };
      final service = UnifiedCatalogService(
        query: query,
        libraries: [
          library('srv-plex', MediaBackend.plex),
          library('srv-jf', MediaBackend.jellyfin),
          library('srv-emby', MediaBackend.jellyfin),
          library('srv-pleya', MediaBackend.pleyaServer),
        ],
        clientFor: (id) => clients[id.value],
      );

      final snapshot = await drain(service);

      expect(snapshot.groups, hasLength(1));
      expect(snapshot.groups.single.sources, hasLength(4));
    });

    test('paging: a long mixed catalog never drops a source or shows a title twice, page after page', () async {
      final plexShows = [
        for (var i = 0; i < 9; i++)
          _show(
            'plex-$i',
            'Show ${i.toString().padLeft(2, '0')}',
            2000 + i,
            serverId: 'srv-plex',
            backend: MediaBackend.plex,
          ),
      ];
      final plex = _FakeServerClient(
        MediaBackend.plex,
        shows: plexShows,
        ids: {for (var i = 0; i < 9; i++) 'plex-$i': ExternalIds(tmdb: 100 + i)},
      );
      // Pleya Server holds every other title, plus two the Plex library lacks.
      final pleyaShows = <String, ({String title, int year, int? tmdb})>{
        for (var i = 0; i < 9; i += 2)
          'ps-$i': (title: 'Show ${i.toString().padLeft(2, '0')}', year: 2000 + i, tmdb: 100 + i),
        'ps-extra-a': (title: 'Show 09', year: 2009, tmdb: 109),
        'ps-extra-b': (title: 'Show 10', year: 2010, tmdb: 110),
      };
      final pleya = pleyaClient(pleyaServer(pleyaShows), serverId: 'srv-pleya');
      await pleya.refreshCapabilities();
      final service = UnifiedCatalogService(
        query: query,
        libraries: [library('srv-plex', MediaBackend.plex), library('srv-pleya', MediaBackend.pleyaServer)],
        clientFor: (id) => id.value == 'srv-plex' ? plex : pleya,
        pageSize: 3,
        groupsPerPage: 3,
      );

      final seenCounts = <int>[];
      var snapshot = await service.loadMore();
      seenCounts.add(snapshot.groups.length);
      while (!snapshot.isComplete && seenCounts.length < 50) {
        snapshot = await service.loadMore();
        seenCounts.add(snapshot.groups.length);
        final titles = snapshot.groups.map((g) => g.representativeSource.item.title).toList();
        expect(titles.toSet(), hasLength(titles.length), reason: 'a title showed up twice mid-paging: $titles');
      }

      expect(snapshot.isComplete, isTrue);
      expect(seenCounts.length, greaterThan(1), reason: 'the catalog should have needed several pages');
      final allSources = snapshot.groups.expand((g) => g.sources).map((s) => s.sourceKey).toSet();
      expect(allSources, hasLength(9 + pleyaShows.length), reason: 'no source may be dropped by grouping');
      final merged = snapshot.groups
          .where((g) => g.sources.length == 2)
          .map((g) => g.representativeSource.item.title)
          .toSet();
      expect(merged, {'Show 00', 'Show 02', 'Show 04', 'Show 06', 'Show 08'});
      final titles = snapshot.groups.map((g) => g.representativeSource.item.title).toList();
      expect(titles, hasLength(11), reason: '9 Plex titles plus the two only Pleya Server has');
    });

    test('refresh: a title the server matches later folds in on the next pass, and nothing else moves', () async {
      final plex = _FakeServerClient(
        MediaBackend.plex,
        shows: [_show('plex-silo', 'Silo', 2023, serverId: 'srv-plex', backend: MediaBackend.plex)],
        ids: {'plex-silo': const ExternalIds(tmdb: 125988)},
      );
      final fake = pleyaServer({'ps-silo': (title: 'Silo', year: 2023, tmdb: null)});
      final pleya = pleyaClient(fake, serverId: 'srv-pleya');
      await pleya.refreshCapabilities();
      final service = UnifiedCatalogService(
        query: query,
        libraries: [library('srv-plex', MediaBackend.plex), library('srv-pleya', MediaBackend.pleyaServer)],
        clientFor: (id) => id.value == 'srv-plex' ? plex : pleya,
      );

      final before = await drain(service);
      expect(before.groups, hasLength(2), reason: 'no proof yet: two cards, each named by its server');

      fake.items['ps-silo']!['external_ids'] = {'tmdb': 125988};
      service.refresh();
      final after = await drain(service);

      expect(after.groups, hasLength(1));
      expect(after.groups.single.sources, hasLength(2));
    });

    test('the same proven TMDB number folds even when the two servers disagree on the year', () async {
      final plex = _FakeServerClient(
        MediaBackend.plex,
        shows: [
          _show('plex-sev', 'Severance', 2022, serverId: 'srv-plex', backend: MediaBackend.plex),
          _show('plex-dune', 'Dune', 1984, serverId: 'srv-plex', backend: MediaBackend.plex),
          _show('plex-twins', 'Twins', 2020, serverId: 'srv-plex', backend: MediaBackend.plex),
        ],
        ids: {
          'plex-sev': const ExternalIds(tmdb: 95396),
          'plex-dune': const ExternalIds(tmdb: 841),
          'plex-twins': const ExternalIds(tmdb: 7),
        },
      );
      final pleya = pleyaClient(
        pleyaServer({
          'ps-sev': (title: 'Severance', year: 2021, tmdb: 95396),
          // Same title, other year, other number: a remake, not the same show.
          'ps-dune': (title: 'Dune', year: 2021, tmdb: 438631),
          // Same title, other year, same number but another kind on the Plex side is covered by the grouping tests.
          'ps-twins': (title: 'Twins', year: 2019, tmdb: 8),
        }),
        serverId: 'srv-pleya',
      );
      await pleya.refreshCapabilities();
      final service = UnifiedCatalogService(
        query: query,
        libraries: [library('srv-plex', MediaBackend.plex), library('srv-pleya', MediaBackend.pleyaServer)],
        clientFor: (id) => id.value == 'srv-plex' ? plex : pleya,
      );

      final snapshot = await drain(service);

      expect(titlesToSources(snapshot)['Severance'], ['srv-plex:plex-sev', 'srv-pleya:ps-sev']);
      expect(snapshot.groups.where((g) => g.representativeSource.item.title == 'Dune'), hasLength(2));
      expect(snapshot.groups.where((g) => g.representativeSource.item.title == 'Twins'), hasLength(2));
    });

    test('a server that predates external_ids keeps its titles as their own cards', () async {
      final plex = _FakeServerClient(
        MediaBackend.plex,
        shows: [_show('plex-sev', 'Severance', 2022, serverId: 'srv-plex', backend: MediaBackend.plex)],
        ids: {'plex-sev': const ExternalIds(tmdb: 95396)},
      );
      final pleya = pleyaClient(
        pleyaServer({'ps-sev': (title: 'Severance', year: 2022, tmdb: 95396)}, reportsExternalIds: false),
        serverId: 'srv-pleya',
      );
      await pleya.refreshCapabilities();
      final service = UnifiedCatalogService(
        query: query,
        libraries: [library('srv-plex', MediaBackend.plex), library('srv-pleya', MediaBackend.pleyaServer)],
        clientFor: (id) => id.value == 'srv-plex' ? plex : pleya,
      );

      final snapshot = await drain(service);

      expect(snapshot.groups, hasLength(2));
      expect(
        {for (final g in snapshot.groups) g.sources.single.backend},
        {MediaBackend.plex, MediaBackend.pleyaServer},
      );
    });

    test(
      'cache and restart: a second service answered from stored ids merges the same without asking the server',
      () async {
        final plex = _FakeServerClient(
          MediaBackend.plex,
          shows: [_show('plex-sev', 'Severance', 2022, serverId: 'srv-plex', backend: MediaBackend.plex)],
          ids: {'plex-sev': const ExternalIds(tmdb: 95396)},
        );
        final fake = pleyaServer({'ps-sev': (title: 'Severance', year: 2022, tmdb: 95396)});
        final pleya = pleyaClient(fake, serverId: 'srv-pleya');
        await pleya.refreshCapabilities();
        final libraries = [library('srv-plex', MediaBackend.plex), library('srv-pleya', MediaBackend.pleyaServer)];
        MediaServerClient? clientFor(ServerId id) => id.value == 'srv-plex' ? plex : pleya;

        final first = await drain(UnifiedCatalogService(query: query, libraries: libraries, clientFor: clientFor));
        expect(first.groups.single.sources, hasLength(2));
        expect(
          fake.requests.where((r) => r.contains('/items/ps-sev')),
          isNotEmpty,
          reason: 'the first run asked for the number',
        );

        fake.requests.clear();
        plex.externalIdFetches.clear();
        final stored = <String, ExternalIds>{
          'srv-plex:plex-sev': const ExternalIds(tmdb: 95396),
          'srv-pleya:ps-sev': const ExternalIds(tmdb: 95396),
        };
        final restarted = await drain(
          UnifiedCatalogService(
            query: query,
            libraries: libraries,
            clientFor: clientFor,
            cachedExternalIds: (serverId, targetId) => stored['$serverId:$targetId'],
          ),
        );

        expect(restarted.groups, hasLength(1));
        expect(restarted.groups.single.sources, hasLength(2));
        expect(fake.requests.where((r) => r.contains('/items/ps-sev')), isEmpty);
        expect(plex.externalIdFetches, isEmpty);
      },
    );

    test('unlinking: dropping one server leaves the other source on its own card and still usable', () async {
      final plex = _FakeServerClient(
        MediaBackend.plex,
        shows: [_show('plex-sev', 'Severance', 2022, serverId: 'srv-plex', backend: MediaBackend.plex)],
        ids: {'plex-sev': const ExternalIds(tmdb: 95396)},
      );
      final pleya = pleyaClient(
        pleyaServer({'ps-sev': (title: 'Severance', year: 2022, tmdb: 95396)}),
        serverId: 'srv-pleya',
      );
      await pleya.refreshCapabilities();
      final both = [library('srv-plex', MediaBackend.plex), library('srv-pleya', MediaBackend.pleyaServer)];
      MediaServerClient? clientFor(ServerId id) => id.value == 'srv-plex' ? plex : pleya;
      final service = UnifiedCatalogService(query: query, libraries: both, clientFor: clientFor);
      expect((await drain(service)).groups.single.sources, hasLength(2));

      service.updateQuery(query: query, libraries: [both.first]);
      final plexOnly = await drain(service);
      expect(plexOnly.groups.single.sources.single.serverId.value, 'srv-plex');

      service.updateQuery(query: query, libraries: [both.last]);
      final pleyaOnly = await drain(service);
      expect(pleyaOnly.groups.single.sources.single.serverId.value, 'srv-pleya');
      expect(pleyaOnly.groups.single.sources.single.item.backend, MediaBackend.pleyaServer);
    });

    test('a Plex library that fails to answer does not hide the Pleya Server source, and is retried', () async {
      final plex = _FakeServerClient(
        MediaBackend.plex,
        shows: [_show('plex-sev', 'Severance', 2022, serverId: 'srv-plex', backend: MediaBackend.plex)],
        ids: {'plex-sev': const ExternalIds(tmdb: 95396)},
      )..failLibraryOnce = true;
      final pleya = pleyaClient(
        pleyaServer({'ps-sev': (title: 'Severance', year: 2022, tmdb: 95396)}),
        serverId: 'srv-pleya',
      );
      await pleya.refreshCapabilities();
      final service = UnifiedCatalogService(
        query: query,
        libraries: [library('srv-plex', MediaBackend.plex), library('srv-pleya', MediaBackend.pleyaServer)],
        clientFor: (id) => id.value == 'srv-plex' ? plex : pleya,
      );

      final first = await service.loadMore();
      expect(first.failedLibraryIds, contains('srv-plex:lib-series'));
      expect(first.groups.single.sources.single.item.backend, MediaBackend.pleyaServer);

      final healed = await drain(service);
      expect(healed.groups.single.sources, hasLength(2));
    });
  });

  group('Verder kijken and search read the same identity', () {
    late PleyaServerClient pleya;
    late PleyaFakeServer fake;

    setUp(() async {
      fake = PleyaFakeServer(watchState: true);
      fake.addLibrary(id: 'lib-series', title: 'Series', kind: 'shows');
      fake.addItem(
        id: 'ps-sev',
        kind: 'show',
        title: 'Severance',
        libraryId: 'lib-series',
        year: 2022,
        externalIds: {'tmdb': 95396},
      );
      fake.addItem(id: 'ps-sev-s2', kind: 'season', title: 'Season 2', parentId: 'ps-sev', index: 2);
      fake.addItem(
        id: 'ps-sev-s2e4',
        kind: 'episode',
        title: 'Woe\'s Hollow',
        parentId: 'ps-sev-s2',
        index: 4,
        durationMs: 3000000,
        userState: {'position_ms': 600000, 'watched': false, 'play_count': 0, 'updated_at': '2026-10-28T20:00:00Z'},
      );
      fake.hubs['continue_watching'] = ['ps-sev-s2e4'];
      pleya = PleyaServerClient.create(
        PleyaServerConnection(
          id: 'pleyaServer.srv-pleya',
          baseUrl: 'http://srv-pleya.lan:8832',
          serverId: 'srv-pleya',
          serverName: 'srv-pleya',
          userName: 'michel',
          refreshToken: 'rt-1',
          createdAt: DateTime.utc(2026, 8, 19),
        ),
        httpClientFactory: fake.asHttpClient,
      );
      await pleya.refreshCapabilities();
    });

    tearDown(() => pleya.close());

    MediaItem plexEpisode({required int season, required int episode}) => MediaItem(
      id: 'plex-ep',
      backend: MediaBackend.plex,
      kind: MediaKind.episode,
      title: 'Woe\'s Hollow',
      grandparentTitle: 'Severance',
      grandparentId: 'plex-sev',
      parentIndex: season,
      index: episode,
      lastViewedAt: 1700000000,
      viewOffsetMs: 300000,
      serverId: 'srv-plex',
      serverName: 'srv-plex',
    );

    Future<ExternalIds> idsFor(String serverId, String targetId) async => switch ('$serverId:$targetId') {
      'srv-plex:plex-sev' => const ExternalIds(tmdb: 95396),
      'srv-pleya:ps-sev' => pleya.fetchExternalIds(targetId),
      _ => const ExternalIds(),
    };

    test('the Pleya Server episode carries its show, so Verder kijken can find the number', () async {
      final onDeck = await pleya.fetchContinueWatching();

      expect(onDeck, hasLength(1));
      expect(onDeck.single.kind, MediaKind.episode);
      expect(onDeck.single.grandparentId, 'ps-sev');
      expect(onDeck.single.parentIndex, 2);
      expect(onDeck.single.index, 4);
    });

    test(
      'the same episode on Plex and Pleya Server is one Verder kijken card with both sources and their own progress',
      () async {
        final onDeck = [plexEpisode(season: 2, episode: 4), ...await pleya.fetchContinueWatching()];

        final row = await HomeProjectionService(
          fetchExternalIds: idsFor,
        ).projectContinueWatching(onDeck, title: 'Verder kijken');

        expect(row.groups, hasLength(1));
        final sources = row.groups.single.sources;
        expect(sources.map((s) => s.backend), unorderedEquals([MediaBackend.plex, MediaBackend.pleyaServer]));
        final progressByBackend = {for (final s in sources) s.backend: s.item.viewOffsetMs};
        expect(progressByBackend[MediaBackend.plex], 300000);
        expect(progressByBackend[MediaBackend.pleyaServer], 600000, reason: 'progress stays on its own source');
      },
    );

    test('a different season or episode number is another card, never an equal by assumption', () async {
      for (final (season, episode) in [(1, 4), (2, 5), (1, 14)]) {
        final onDeck = [plexEpisode(season: season, episode: episode), ...await pleya.fetchContinueWatching()];

        final row = await HomeProjectionService(
          fetchExternalIds: idsFor,
        ).projectContinueWatching(onDeck, title: 'Verder kijken');

        expect(row.groups, hasLength(2), reason: 'S${season}E$episode');
      }
    });

    test('without a number from the server the two episodes stay two cards', () async {
      fake.items['ps-sev']!['external_ids'] = null;
      final onDeck = [plexEpisode(season: 2, episode: 4), ...await pleya.fetchContinueWatching()];

      final row = await HomeProjectionService(
        fetchExternalIds: idsFor,
      ).projectContinueWatching(onDeck, title: 'Verder kijken');

      expect(row.groups, hasLength(2));
    });

    test('search puts the duplicate series on one card and keeps the other results apart', () async {
      final results = [
        MediaItem(
          id: 'plex-sev',
          backend: MediaBackend.plex,
          kind: MediaKind.show,
          title: 'Severance',
          year: 2022,
          serverId: 'srv-plex',
          serverName: 'srv-plex',
        ),
        ...await pleya.searchItems('Severance'),
      ];

      final projection = await searchProjection(results, fetchExternalIds: idsFor);

      expect(projection.shows, hasLength(1));
      expect(
        projection.shows.single.sources.map((s) => s.backend),
        unorderedEquals([MediaBackend.plex, MediaBackend.pleyaServer]),
      );
    });
  });

  group('identity lookups', () {
    test('Pleya Server answers catalogue-identity lookups, a local folder and a Pleya Share still do not', () {
      expect(isIdentityEligibleBackend(MediaBackend.pleyaServer), isTrue);
      expect(isIdentityEligibleBackend(MediaBackend.plex), isTrue);
      expect(isIdentityEligibleBackend(MediaBackend.jellyfin), isTrue);
      expect(isIdentityEligibleBackend(MediaBackend.local), isFalse);
    });
  });

  group('activation keeps every source of a merged card usable', () {
    UnifiedMediaGroup merged() {
      final groups = groupUnifiedMediaSources([
        _candidate(
          _item(
            _Flavor.plex,
            serverId: 'srv-plex',
            id: 'plex-sev',
            title: 'Severance',
            year: 2022,
            kind: MediaKind.show,
          ),
          ids: const ExternalIds(tmdb: 95396),
        ),
        _candidate(
          _item(
            _Flavor.pleya,
            serverId: 'srv-pleya',
            id: 'ps-sev',
            title: 'Severance',
            year: 2022,
            kind: MediaKind.show,
          ),
          ids: const ExternalIds(tmdb: 95396),
        ),
      ]);
      expect(groups, hasLength(1));
      return groups.single;
    }

    SourceAvailability Function(UnifiedMediaSource) availability(Set<String> offline) =>
        (source) => offline.contains(source.serverId.value) ? SourceAvailability.offline : SourceAvailability.online;

    test('both online: the user is asked which source to use', () {
      final decision = const UnifiedActivationCoordinator().decide(
        group: merged(),
        intent: UnifiedActivationIntent.play,
        availabilityFor: availability({}),
      );

      expect(decision, isA<ShowSourcePicker>());
      expect(
        (decision as ShowSourcePicker).sources.map((s) => s.backend),
        unorderedEquals([MediaBackend.plex, MediaBackend.pleyaServer]),
      );
    });

    test('Plex offline: the Pleya Server source opens directly, nothing is lost', () {
      final decision = const UnifiedActivationCoordinator().decide(
        group: merged(),
        intent: UnifiedActivationIntent.play,
        availabilityFor: availability({'srv-plex'}),
      );

      expect(decision, isA<ActivateSourceDirectly>());
      final direct = decision as ActivateSourceDirectly;
      expect(direct.item.backend, MediaBackend.pleyaServer);
      expect(direct.item.id, 'ps-sev');
    });

    test('Pleya Server offline: the Plex source opens directly', () {
      final decision = const UnifiedActivationCoordinator().decide(
        group: merged(),
        intent: UnifiedActivationIntent.play,
        availabilityFor: availability({'srv-pleya'}),
      );

      expect(decision, isA<ActivateSourceDirectly>());
      expect((decision as ActivateSourceDirectly).item.backend, MediaBackend.plex);
    });

    test('the Pleya Server source of a merged film really plays: the chosen item resolves to a stream', () async {
      final fake = PleyaFakeServer(watchState: true);
      fake.addLibrary(id: 'lib-films', title: 'Films', kind: 'movies');
      fake.addItem(
        id: 'ps-dune',
        kind: 'movie',
        title: 'Dune',
        libraryId: 'lib-films',
        year: 2021,
        durationMs: 9300000,
        externalIds: {'tmdb': 438631},
      );
      final client = PleyaServerClient.create(
        PleyaServerConnection(
          id: 'pleyaServer.srv-pleya',
          baseUrl: 'http://srv-pleya.lan:8832',
          serverId: 'srv-pleya',
          serverName: 'srv-pleya',
          userName: 'michel',
          refreshToken: 'rt-1',
          createdAt: DateTime.utc(2026, 8, 19),
        ),
        httpClientFactory: fake.asHttpClient,
      );
      addTearDown(client.close);
      await client.refreshCapabilities();
      final pleyaDune = (await client.fetchLibraryPagedContent('lib-films', query: const LibraryQuery())).items.single;
      final groups = groupUnifiedMediaSources([
        _candidate(
          _item(_Flavor.plex, serverId: 'srv-plex', id: 'plex-dune', title: 'Dune', year: 2021),
          ids: const ExternalIds(tmdb: 438631),
        ),
        _candidate(pleyaDune, ids: await client.fetchExternalIds('ps-dune')),
      ]);
      expect(groups, hasLength(1));

      final decision = const UnifiedActivationCoordinator().decide(
        group: groups.single,
        intent: UnifiedActivationIntent.play,
        availabilityFor: availability({'srv-plex'}),
      );
      final chosen = (decision as ActivateSourceDirectly).item;
      final playback = await client.getPlaybackInitialization(
        PlaybackInitializationOptions(metadata: chosen, selectedMediaIndex: 0),
      );

      expect(chosen.backend, MediaBackend.pleyaServer);
      expect(playback.videoUrl, startsWith('http://srv-pleya.lan:8832/pleya/v1/stream/'));
      expect(playback.playMethod, 'DirectPlay');
    });

    test('both offline: nothing usable, and the picker still lists both so the user sees why', () {
      final decision = const UnifiedActivationCoordinator().decide(
        group: merged(),
        intent: UnifiedActivationIntent.play,
        availabilityFor: availability({'srv-plex', 'srv-pleya'}),
      );

      expect(decision, isA<NoUsableSource>());
      expect((decision as NoUsableSource).sources, hasLength(2));
    });
  });
}

// -- Fake non-Pleya clients ------------------------------------------------------

MediaItem _show(String id, String title, int year, {required String serverId, required MediaBackend backend}) =>
    MediaItem(
      id: id,
      backend: backend,
      kind: MediaKind.show,
      title: title,
      year: year,
      serverId: serverId,
      serverName: serverId,
    );

/// A Plex/Jellyfin/Emby stand-in: one library of shows, plus the external ids
/// the real clients would report for them.
class _FakeServerClient implements MediaServerClient {
  _FakeServerClient(this._backend, {required this.shows, this.ids = const {}});

  final MediaBackend _backend;
  final List<MediaItem> shows;
  final Map<String, ExternalIds> ids;
  final List<String> externalIdFetches = [];
  bool failLibraryOnce = false;

  @override
  MediaBackend get backend => _backend;

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    if (failLibraryOnce) {
      failLibraryOnce = false;
      throw StateError('library unavailable');
    }
    final sorted = [...shows]..sort((a, b) => (a.title ?? '').compareTo(b.title ?? ''));
    final end = (query.offset + query.limit).clamp(0, sorted.length);
    final slice = query.offset >= sorted.length ? const <MediaItem>[] : sorted.sublist(query.offset, end);
    return LibraryPage<MediaItem>(items: slice, totalCount: sorted.length, offset: query.offset);
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async {
    externalIdFetches.add(itemId);
    return ids[itemId] ?? const ExternalIds();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_FakeServerClient: ${invocation.memberName}');
}
