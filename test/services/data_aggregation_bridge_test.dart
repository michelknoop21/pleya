import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_kind.dart';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_client.dart';

JellyfinConnection _conn() => _connFor(serverId: 'srv-1', baseUrl: 'https://jf.example.com');

JellyfinConnection _connFor({required String serverId, required String baseUrl}) => JellyfinConnection(
  id: '$serverId/user-1',
  baseUrl: baseUrl,
  serverName: 'Home',
  serverMachineId: serverId,
  userId: 'user-1',
  userName: 'edde',
  accessToken: 'tok-abc',
  deviceId: 'dev-xyz',
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
);

http.Response _json(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

/// Smoke tests for the surviving cross-server aggregation surface on
/// [DataAggregationService]. Single-server passthroughs were removed in
/// favour of `context.tryGetMediaClientForServer(...).<method>()`; what's
/// left here is the multi-client fan-out, which is testable without a
/// real backend by simply asserting the empty-state behaviour.
void main() {
  late AppDatabase db;
  late MultiServerManager manager;
  late DataAggregationService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    manager = MultiServerManager();
    service = DataAggregationService(manager);
  });

  tearDown(() async {
    manager.dispose();
    await db.close();
  });

  group('DataAggregationService cross-server aggregation', () {
    test('getMediaLibrariesFromAllServers returns empty when no clients connected', () async {
      final result = await service.getMediaLibrariesFromAllServers();
      expect(result.libraries, isEmpty);
      expect(result.succeededServerIds, isEmpty);
    });

    test('searchAcrossServers and getOnDeckFromAllServers return empty when no clients', () async {
      expect((await service.searchAcrossServers('hello')).items, isEmpty);
      final onDeck = await service.getOnDeckFromAllServers();
      expect(onDeck.items, isEmpty);
      expect(onDeck.succeededServerIds, isEmpty);
    });

    test('searchAcrossServers overfetches and ranks before trimming across backends', () async {
      final plexRequests = <Uri>[];
      final jellyfinRequests = <Uri>[];

      final plexClient = PlexClient.forTesting(
        config: PlexConfig(
          baseUrl: 'https://plex.example.com',
          token: 'token',
          clientIdentifier: 'client-id',
          product: 'Plezy',
          version: 'test',
        ),
        serverId: ServerId('plex-1'),
        serverName: 'Plex',
        httpClient: MockClient((req) async {
          plexRequests.add(req.url);
          if (req.url.path == '/library/search') {
            return _json({
              'MediaContainer': {
                'SearchResult': [
                  {
                    'score': 100,
                    'Metadata': {'ratingKey': 'plex-movie', 'type': 'movie', 'title': 'The Boys in the Boat'},
                  },
                ],
              },
            });
          }
          return http.Response('unexpected request', 500);
        }),
      );
      addTearDown(plexClient.close);
      manager.debugRegisterClientForTesting(plexClient);

      final jellyfinClient = JellyfinClient.forTesting(
        connection: _conn(),
        httpClient: MockClient((req) async {
          jellyfinRequests.add(req.url);
          if (req.url.path == '/Items') {
            return _json({
              'Items': [
                {'Id': 'jf-show', 'Type': 'Series', 'Name': 'The Boys'},
              ],
            });
          }
          return http.Response('unexpected request', 500);
        }),
      );
      addTearDown(jellyfinClient.close);
      manager.debugRegisterJellyfinClientForTesting(jellyfinClient);

      final results = await service.searchAcrossServers('The Boys', limit: 1);

      expect(results.items.map((item) => item.id), ['jf-show']);
      expect(results.succeededServerIds, {'plex-1', 'srv-1'});
      expect(plexRequests.single.queryParameters['limit'], '100');
      expect(plexRequests.single.queryParameters['searchTypes'], 'movies,tv');
      expect(jellyfinRequests.single.queryParameters['Limit'], '100');
    });

    test('a hanging server does not hold back the healthy ones', () {
      // FakeAsync so the per-server timeout elapses without a real 8s wait.
      fakeAsync((async) {
        final healthy = _StubSearchClient(id: 'healthy', items: [_stubItem('healthy-1', 'Healthy Result')]);
        // Never completes — the "marked online but silently dead" server.
        final hanging = _StubSearchClient(id: 'hanging', items: const [], hang: true);
        manager.debugRegisterClientForTesting(healthy);
        manager.debugRegisterClientForTesting(hanging);

        SearchAggregationResult? result;
        service.searchAcrossServers('anything').then((r) => result = r);

        // Before the budget expires the fan-out is still waiting on the hang.
        async.elapse(const Duration(seconds: 7));
        async.flushMicrotasks();
        expect(result, isNull);

        // Once it does, the healthy server's results come through and the
        // hanging server is reported as *not* succeeded.
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(result, isNotNull);
        expect(result!.items.map((i) => i.id), ['healthy-1']);
        expect(result!.succeededServerIds, {'healthy'});
      });
    });

    test('getOnDeckFromAllServers forwards preview limit to clients', () async {
      final captured = <Uri>[];

      final client = PlexClient.forTesting(
        config: PlexConfig(
          baseUrl: 'https://plex.example.com',
          token: 'token',
          clientIdentifier: 'client-id',
          product: 'Plezy',
          version: 'test',
        ),
        serverId: ServerId('plex-1'),
        serverName: 'Plex',
        httpClient: MockClient((req) async {
          captured.add(req.url);
          if (req.url.path == '/hubs') {
            return _json({
              'MediaContainer': {
                'Hub': [
                  {
                    'key': '/hubs/home/continueWatching',
                    'title': 'Continue Watching',
                    'type': 'mixed',
                    'hubIdentifier': 'home.continue',
                    'size': 1,
                    'Metadata': [
                      {'ratingKey': 'movie-1', 'type': 'movie', 'title': 'Movie 1'},
                    ],
                  },
                ],
              },
            });
          }
          return http.Response('unexpected request', 500);
        }),
      );
      addTearDown(client.close);
      manager.debugRegisterClientForTesting(client);

      final result = await service.getOnDeckFromAllServers(limit: 21);

      expect(result.items.map((item) => item.id), ['movie-1']);
      expect(result.succeededServerIds, {'plex-1'});
      expect(captured.single.path, '/hubs');
      expect(captured.single.queryParameters['count'], '21');
    });

    test('getOnDeckFromAllServers filters hidden Plex continue-watching libraries', () async {
      final client = PlexClient.forTesting(
        config: PlexConfig(
          baseUrl: 'https://plex.example.com',
          token: 'token',
          clientIdentifier: 'client-id',
          product: 'Plezy',
          version: 'test',
        ),
        serverId: ServerId('plex-1'),
        serverName: 'Plex',
        httpClient: MockClient((req) async {
          if (req.url.path == '/hubs') {
            return _json({
              'MediaContainer': {
                'Hub': [
                  {
                    'key': '/hubs/home/continueWatching',
                    'title': 'Continue Watching',
                    'type': 'mixed',
                    'hubIdentifier': 'home.continue',
                    'size': 2,
                    'Metadata': [
                      {
                        'ratingKey': 'movie-visible',
                        'type': 'movie',
                        'title': 'Visible Movie',
                        'lastViewedAt': 100,
                        'librarySectionID': 1,
                      },
                      {
                        'ratingKey': 'movie-hidden',
                        'type': 'movie',
                        'title': 'Hidden Movie',
                        'lastViewedAt': 200,
                        'librarySectionID': 2,
                      },
                    ],
                  },
                ],
              },
            });
          }
          return http.Response('unexpected request', 500);
        }),
      );
      addTearDown(client.close);
      manager.debugRegisterClientForTesting(client);

      final result = await service.getOnDeckFromAllServers(limit: 10, hiddenLibraryKeys: {'plex-1:2'});

      expect(result.items.map((item) => item.id), ['movie-visible']);
      expect(result.succeededServerIds, {'plex-1'});
    });

    test('getOnDeckFromAllServers hides duplicate show entries by stable show ids', () async {
      final client = PlexClient.forTesting(
        config: PlexConfig(
          baseUrl: 'https://plex.example.com',
          token: 'token',
          clientIdentifier: 'client-id',
          product: 'Plezy',
          version: 'test',
        ),
        serverId: ServerId('plex-1'),
        serverName: 'Plex',
        httpClient: MockClient((req) async {
          if (req.url.path == '/hubs') {
            return _json({
              'MediaContainer': {
                'Hub': [
                  {
                    'key': '/hubs/home/continueWatching',
                    'title': 'Continue Watching',
                    'type': 'mixed',
                    'hubIdentifier': 'home.continue',
                    'size': 2,
                    'Metadata': [
                      {
                        'ratingKey': 'old-episode',
                        'type': 'episode',
                        'title': 'Episode 1',
                        'grandparentRatingKey': 'old-show',
                        'grandparentTitle': 'Shared Show',
                        'guid': 'plex://episode/shared-episode-1',
                        'lastViewedAt': 100,
                        'librarySectionID': 1,
                      },
                      {
                        'ratingKey': 'new-episode',
                        'type': 'episode',
                        'title': 'Episode 2',
                        'grandparentRatingKey': 'new-show',
                        'grandparentTitle': 'Shared Show',
                        'guid': 'plex://episode/shared-episode-2',
                        'lastViewedAt': 200,
                        'librarySectionID': 2,
                      },
                    ],
                  },
                ],
              },
            });
          }
          if (req.url.path == '/library/metadata/old-show' || req.url.path == '/library/metadata/new-show') {
            return _json({
              'MediaContainer': {
                'Metadata': [
                  {
                    'ratingKey': req.url.pathSegments.last,
                    'type': 'show',
                    'title': 'Shared Show',
                    'Guid': [
                      {'id': 'tvdb://12345'},
                    ],
                  },
                ],
              },
            });
          }
          return http.Response('unexpected request', 500);
        }),
      );
      addTearDown(client.close);
      manager.debugRegisterClientForTesting(client);

      final result = await service.getOnDeckFromAllServers(limit: 10);

      expect(result.items.map((item) => item.id), ['new-episode']);
      expect(result.succeededServerIds, {'plex-1'});
    });

    test('getOnDeckFromAllServers keeps duplicate titles without stable ids', () async {
      final client = PlexClient.forTesting(
        config: PlexConfig(
          baseUrl: 'https://plex.example.com',
          token: 'token',
          clientIdentifier: 'client-id',
          product: 'Plezy',
          version: 'test',
        ),
        serverId: ServerId('plex-1'),
        serverName: 'Plex',
        httpClient: MockClient((req) async {
          if (req.url.path == '/hubs') {
            return _json({
              'MediaContainer': {
                'Hub': [
                  {
                    'key': '/hubs/home/continueWatching',
                    'title': 'Continue Watching',
                    'type': 'mixed',
                    'hubIdentifier': 'home.continue',
                    'size': 2,
                    'Metadata': [
                      {
                        'ratingKey': 'old-unmatched',
                        'type': 'episode',
                        'title': 'Episode 1',
                        'grandparentRatingKey': 'old-unmatched-show',
                        'grandparentTitle': 'Shared Show',
                        'guid': 'com.plexapp.agents.none://old-unmatched',
                        'lastViewedAt': 100,
                      },
                      {
                        'ratingKey': 'new-unmatched',
                        'type': 'episode',
                        'title': 'Episode 2',
                        'grandparentRatingKey': 'new-unmatched-show',
                        'grandparentTitle': 'Shared Show',
                        'guid': 'com.plexapp.agents.none://new-unmatched',
                        'lastViewedAt': 200,
                      },
                    ],
                  },
                ],
              },
            });
          }
          if (req.url.path == '/library/metadata/old-unmatched-show' ||
              req.url.path == '/library/metadata/new-unmatched-show') {
            return _json({
              'MediaContainer': {
                'Metadata': [
                  {'ratingKey': req.url.pathSegments.last, 'type': 'show', 'title': 'Shared Show'},
                ],
              },
            });
          }
          return http.Response('unexpected request', 500);
        }),
      );
      addTearDown(client.close);
      manager.debugRegisterClientForTesting(client);

      final result = await service.getOnDeckFromAllServers(limit: 10);

      expect(result.items.map((item) => item.id), ['new-unmatched', 'old-unmatched']);
      expect(result.succeededServerIds, {'plex-1'});
    });

    // Fase 1 (docs/DECISIONS.md#dec-063) rewires Continue Watching dedup onto
    // the shared unified-catalog identity primitives. The new
    // `grouping_service.dart` those primitives feed *does* merge on title+year
    // alone when nothing conflicts (hoofdstuk 11.6) — a real capability
    // improvement fase 3+ eventually gives Continue Watching too. This test
    // pins that Continue Watching itself does not get that behavior yet: its
    // compatibility shim in `identity_resolver.dart` only ever merges on
    // shared external ids/guid, matching every pre-fase-1 build, so this
    // scenario keeps both movies instead of silently starting to merge them.
    test(
      'getOnDeckFromAllServers never merges two movies on title+year alone, unlike the new grouping engine',
      () async {
        final client = PlexClient.forTesting(
          config: PlexConfig(
            baseUrl: 'https://plex.example.com',
            token: 'token',
            clientIdentifier: 'client-id',
            product: 'Plezy',
            version: 'test',
          ),
          serverId: ServerId('plex-1'),
          serverName: 'Plex',
          httpClient: MockClient((req) async {
            if (req.url.path == '/hubs') {
              return _json({
                'MediaContainer': {
                  'Hub': [
                    {
                      'key': '/hubs/home/continueWatching',
                      'title': 'Continue Watching',
                      'type': 'mixed',
                      'hubIdentifier': 'home.continue',
                      'size': 2,
                      'Metadata': [
                        {
                          'ratingKey': 'old-movie',
                          'type': 'movie',
                          'title': 'Shared Title',
                          'year': 2019,
                          'viewOffsetMs': 100,
                          'duration': 1000,
                          'lastViewedAt': 100,
                        },
                        {
                          'ratingKey': 'new-movie',
                          'type': 'movie',
                          'title': 'Shared Title',
                          'year': 2019,
                          'viewOffsetMs': 100,
                          'duration': 1000,
                          'lastViewedAt': 200,
                        },
                      ],
                    },
                  ],
                },
              });
            }
            if (req.url.path == '/library/metadata/old-movie' || req.url.path == '/library/metadata/new-movie') {
              return _json({
                'MediaContainer': {
                  'Metadata': [
                    {'ratingKey': req.url.pathSegments.last, 'type': 'movie', 'title': 'Shared Title'},
                  ],
                },
              });
            }
            return http.Response('unexpected request', 500);
          }),
        );
        addTearDown(client.close);
        manager.debugRegisterClientForTesting(client);

        final result = await service.getOnDeckFromAllServers(limit: 10);

        expect(result.items.map((item) => item.id), ['new-movie', 'old-movie']);
        expect(result.succeededServerIds, {'plex-1'});
      },
    );

    test('getLatestMoviesFromAllServers sorts by release date, films only, addedAt sinks the dateless', () async {
      final client = PlexClient.forTesting(
        config: PlexConfig(
          baseUrl: 'https://plex.example.com',
          token: 'token',
          clientIdentifier: 'client-id',
          product: 'Plezy',
          version: 'test',
        ),
        serverId: ServerId('plex-1'),
        serverName: 'Plex',
        httpClient: MockClient((req) async {
          if (req.url.path == '/library/recentlyAdded') {
            return _json({
              'MediaContainer': {
                'Metadata': [
                  // Added most recently but oldest release → must sort last of the dated films.
                  {
                    'ratingKey': 'old-film',
                    'type': 'movie',
                    'title': 'Old Film',
                    'originallyAvailableAt': '2010-01-01',
                    'addedAt': 900,
                  },
                  // A series must be dropped entirely (no fallback).
                  {
                    'ratingKey': 'a-show',
                    'type': 'show',
                    'title': 'A Show',
                    'originallyAvailableAt': '2025-01-01',
                    'addedAt': 800,
                  },
                  // Newest release → first.
                  {
                    'ratingKey': 'new-film',
                    'type': 'movie',
                    'title': 'New Film',
                    'originallyAvailableAt': '2024-06-01',
                    'addedAt': 100,
                  },
                  // No release date → sinks below every dated film via addedAt.
                  {'ratingKey': 'dateless', 'type': 'movie', 'title': 'Dateless', 'addedAt': 999},
                ],
              },
            });
          }
          return http.Response('unexpected request', 500);
        }),
      );
      addTearDown(client.close);
      manager.debugRegisterClientForTesting(client);

      final result = await service.getLatestMoviesFromAllServers(limit: 12);

      expect(result.items.map((item) => item.id), ['new-film', 'old-film', 'dateless']);
      expect(result.succeededServerIds, {'plex-1'});
    });

    test('getLatestShowsFromAllServers sorts by addedAt, dedupes cross-server, drops episodes', () async {
      final plex = PlexClient.forTesting(
        config: PlexConfig(
          baseUrl: 'https://plex.example.com',
          token: 'token',
          clientIdentifier: 'client-id',
          product: 'Plezy',
          version: 'test',
        ),
        serverId: ServerId('plex-1'),
        serverName: 'Plex',
        httpClient: MockClient((req) async {
          if (req.url.path == '/library/all' && req.url.queryParameters['type'] == '2') {
            return _json({
              'MediaContainer': {
                'Metadata': [
                  {'ratingKey': 'show-old', 'type': 'show', 'title': 'Old Show', 'guid': 'guid-old', 'addedAt': 100},
                  {'ratingKey': 'show-new', 'type': 'show', 'title': 'New Show', 'guid': 'guid-new', 'addedAt': 500},
                  // Episode must never reach a shows row.
                  {'ratingKey': 'ep', 'type': 'episode', 'title': 'Ep', 'addedAt': 999},
                ],
              },
            });
          }
          return http.Response('unexpected request', 500);
        }),
      );
      addTearDown(plex.close);
      manager.debugRegisterClientForTesting(plex);

      final jellyfin = JellyfinClient.forTesting(
        connection: _conn(),
        httpClient: MockClient((req) async {
          if (req.url.path == '/Users/user-1/Items/Latest') {
            // Same series as Plex's newest (shared guid) → deduped away.
            return _json([
              {'Id': 'jf-show', 'Type': 'Series', 'Name': 'New Show', 'ProviderIds': {}, 'DateCreated': null},
            ]);
          }
          return http.Response('unexpected request', 500);
        }),
      );
      addTearDown(jellyfin.close);
      manager.debugRegisterClientForTesting(jellyfin);

      final result = await service.getLatestShowsFromAllServers(limit: 12);

      expect(result.items.map((item) => item.id), ['show-new', 'show-old', 'jf-show']);
      expect(result.items.every((item) => item.kind == MediaKind.show), isTrue);
    });

    test('per-library hubs skip playback rows and fetch in bounded batches', () async {
      final captured = <Uri>[];
      var activeLatest = 0;
      var maxActiveLatest = 0;

      final client = JellyfinClient.forTesting(
        connection: _conn(),
        httpClient: MockClient((req) async {
          captured.add(req.url);
          if (req.url.path == '/Users/user-1/Views') {
            return _json({
              'Items': [
                {'Id': 'lib-1', 'Name': 'Lib 1', 'CollectionType': 'movies'},
                {'Id': 'lib-2', 'Name': 'Lib 2', 'CollectionType': 'movies'},
                {'Id': 'lib-3', 'Name': 'Lib 3', 'CollectionType': 'tvshows'},
                {'Id': 'lib-4', 'Name': 'Lib 4', 'CollectionType': 'tvshows'},
              ],
            });
          }
          if (req.url.path == '/Users/user-1/Items/Latest') {
            activeLatest++;
            if (activeLatest > maxActiveLatest) maxActiveLatest = activeLatest;
            try {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              final parentId = req.url.queryParameters['ParentId']!;
              return _json({
                'Items': [
                  {'Id': 'item-$parentId', 'Type': 'Movie', 'Name': 'Latest $parentId', 'ParentLibraryId': parentId},
                ],
              });
            } finally {
              activeLatest--;
            }
          }
          return http.Response('unexpected request', 500);
        }),
      );
      addTearDown(client.close);
      manager.debugRegisterJellyfinClientForTesting(client);

      final result = await service.getHubsFromAllServers(useGlobalHubs: false, includePlaybackHubs: false);
      final hubs = result.hubs;

      expect(result.succeededServerIds, {'srv-1'});
      expect(hubs.map((h) => h.identifier), [
        'library.lib-1.recent',
        'library.lib-2.recent',
        'library.lib-3.recent',
        'library.lib-4.recent',
      ]);
      expect(hubs.map((h) => h.items.single.id), ['item-lib-1', 'item-lib-2', 'item-lib-3', 'item-lib-4']);
      expect(maxActiveLatest, lessThanOrEqualTo(3));
      expect(captured.where((uri) => uri.path == '/UserItems/Resume' || uri.path == '/Shows/NextUp'), isEmpty);
      expect(
        captured.where((uri) => uri.path == '/Users/user-1/Items/Latest').map((uri) => uri.queryParameters['ParentId']),
        ['lib-1', 'lib-2', 'lib-3', 'lib-4'],
      );
      expect(
        captured.where((uri) => uri.path == '/Users/user-1/Items/Latest').map((uri) => uri.queryParameters['Limit']),
        everyElement(defaultHubPreviewLimit.toString()),
      );
    });

    test('global home layout falls back to per-library hubs for Jellyfin', () async {
      final captured = <Uri>[];

      final client = JellyfinClient.forTesting(
        connection: _conn(),
        httpClient: MockClient((req) async {
          captured.add(req.url);
          if (req.url.path == '/Users/user-1/Views') {
            return _json({
              'Items': [
                {'Id': 'movies', 'Name': 'Movies', 'CollectionType': 'movies'},
                {'Id': 'shows', 'Name': 'Shows', 'CollectionType': 'tvshows'},
              ],
            });
          }
          if (req.url.path == '/Users/user-1/Items/Latest') {
            final parentId = req.url.queryParameters['ParentId'];
            return switch (parentId) {
              'movies' => _json({
                'Items': [
                  {'Id': 'movie-1', 'Type': 'Movie', 'Name': 'Latest Movie', 'ParentLibraryId': 'movies'},
                ],
              }),
              'shows' => _json({
                'Items': [
                  {'Id': 'show-1', 'Type': 'Series', 'Name': 'Latest Show', 'ParentLibraryId': 'shows'},
                ],
              }),
              _ => http.Response('mixed latest should not be requested', 500),
            };
          }
          return http.Response('unexpected request', 500);
        }),
      );
      addTearDown(client.close);
      manager.debugRegisterJellyfinClientForTesting(client);

      final result = await service.getHubsFromAllServers(useGlobalHubs: true, includePlaybackHubs: false);
      final hubs = result.hubs;

      expect(result.succeededServerIds, {'srv-1'});
      expect(hubs.map((h) => h.identifier), ['library.movies.recent', 'library.shows.recent']);
      expect(hubs.map((h) => h.items.single.id), ['movie-1', 'show-1']);
      expect(captured.where((uri) => uri.path == '/Users/user-1/Views'), hasLength(1));
      expect(
        captured.where((uri) => uri.path == '/Users/user-1/Items/Latest').map((uri) => uri.queryParameters['ParentId']),
        ['movies', 'shows'],
      );
      expect(
        captured.where((uri) => uri.path == '/Users/user-1/Items/Latest').map((uri) => uri.queryParameters['Limit']),
        everyElement(defaultHubPreviewLimit.toString()),
      );
    });

    test('Plex home layout keeps promoted hubs instead of splitting by preview libraries', () async {
      final captured = <Uri>[];

      final client = PlexClient.forTesting(
        config: PlexConfig(
          baseUrl: 'https://plex.example.com',
          token: 'token',
          clientIdentifier: 'client-id',
          product: 'Plezy',
          version: 'test',
        ),
        serverId: ServerId('plex-1'),
        serverName: 'Plex',
        promotedHubKey: '/hubs/promoted',
        httpClient: MockClient((req) async {
          captured.add(req.url);
          if (req.url.path == '/hubs/promoted') {
            return _json({
              'MediaContainer': {
                'Hub': [
                  {
                    'key': '/hubs/home/recentlyAdded?type=2',
                    'title': 'Recently Added TV',
                    'type': 'mixed',
                    'hubIdentifier': 'home.television.recent',
                    'size': 7,
                    'more': true,
                    'Metadata': [
                      for (var i = 1; i <= 7; i++)
                        {
                          'ratingKey': 'show-$i',
                          'type': 'show',
                          'title': 'Show $i',
                          'librarySectionID': i,
                          'librarySectionTitle': 'Library $i',
                        },
                    ],
                  },
                ],
              },
            });
          }
          return http.Response('unexpected request', 500);
        }),
      );
      addTearDown(client.close);
      manager.debugRegisterClientForTesting(client);

      final result = await service.getHubsFromAllServers(useGlobalHubs: true, includePlaybackHubs: false);
      final hubs = result.hubs;

      expect(result.succeededServerIds, {'plex-1'});
      expect(hubs, hasLength(1));
      expect(hubs.single.title, 'Recently Added TV');
      expect(hubs.single.identifier, 'home.television.recent');
      expect(hubs.single.libraryId, isNull);
      expect(hubs.single.items, hasLength(7));
      expect(captured.map((uri) => uri.path), ['/hubs/promoted']);
      expect(captured.single.queryParameters['count'], defaultHubPreviewLimit.toString());
    });
  });

  // Fase 2 (docs/tvos-unified-experience.md hoofdstuk 27, hoofdstuk 1.1 punt 2):
  // MultiServerManager.onlineClients itself is NOT visibility-filtered — the
  // profile visibility filter lives on the manager but only MultiServerProvider
  // applied it. DataAggregationService._clientsFor() used to read onlineClients
  // directly, so a profile-hidden server's items could still reach every
  // cross-server aggregation call. This closes that gap ahead of the unified
  // fan-out (findAllByIdentity in a later phase), which must never let a
  // hidden server's items reach identity/grouping.
  group('DataAggregationService respects profile visibility', () {
    test('getMediaLibrariesFromAllServers excludes a server hidden by the active profile', () async {
      final visible = JellyfinClient.forTesting(
        connection: _connFor(serverId: 'srv-visible', baseUrl: 'https://jf-visible.example.com'),
        httpClient: MockClient((req) async {
          if (req.url.path == '/Users/user-1/Views') {
            return _json({
              'Items': [
                {'Id': 'lib-visible', 'Name': 'Visible Library', 'CollectionType': 'movies'},
              ],
            });
          }
          return http.Response('unexpected request', 500);
        }),
      );
      final hidden = JellyfinClient.forTesting(
        connection: _connFor(serverId: 'srv-hidden', baseUrl: 'https://jf-hidden.example.com'),
        httpClient: MockClient((req) async => http.Response('server should never be called', 500)),
      );
      addTearDown(visible.close);
      addTearDown(hidden.close);
      manager.debugRegisterJellyfinClientForTesting(visible);
      manager.debugRegisterJellyfinClientForTesting(hidden);
      manager.setVisibleServerIds({'srv-visible'});

      final result = await service.getMediaLibrariesFromAllServers();

      expect(result.libraries.map((l) => l.id), ['lib-visible']);
      expect(result.succeededServerIds, {'srv-visible'});
    });

    test('an explicit serverIds restriction never re-admits a profile-hidden server', () async {
      final hidden = JellyfinClient.forTesting(
        connection: _connFor(serverId: 'srv-hidden', baseUrl: 'https://jf-hidden.example.com'),
        httpClient: MockClient((req) async => http.Response('server should never be called', 500)),
      );
      addTearDown(hidden.close);
      manager.debugRegisterJellyfinClientForTesting(hidden);
      manager.setVisibleServerIds(const {});

      final result = await service.getMediaLibrariesFromAllServers(serverIds: {'srv-hidden'});

      expect(result.libraries, isEmpty);
      expect(result.succeededServerIds, isEmpty);
    });

    test('a null visibility filter (no active restriction) still sees every online server', () async {
      final client = JellyfinClient.forTesting(
        connection: _conn(),
        httpClient: MockClient((req) async {
          if (req.url.path == '/Users/user-1/Views') {
            return _json({
              'Items': [
                {'Id': 'lib-1', 'Name': 'Library 1', 'CollectionType': 'movies'},
              ],
            });
          }
          return http.Response('unexpected request', 500);
        }),
      );
      addTearDown(client.close);
      manager.debugRegisterJellyfinClientForTesting(client);
      expect(manager.visibleServerIds, isNull);

      final result = await service.getMediaLibrariesFromAllServers();

      expect(result.succeededServerIds, {'srv-1'});
    });
  });

  // Fase-0 baseline for Pleya Unified TV 2026 (docs/tvos-unified-experience.md
  // hoofdstuk 27): this group locks in the existing DataAggregationService
  // call-count behavior that fase 0 must not change before any
  // unified-catalog/pagination work (hoofdstuk 12) lands. It is a tripwire,
  // not a correctness test: if a later phase changes the fan-out shape (e.g.
  // batches libraries into one request, or adds a prefetch call), this test
  // goes red and forces an explicit decision instead of a silent drift in how
  // many requests Home/Libraries makes per server.
  group('DataAggregationService call-count baseline', () {
    test('call-count baseline: 5 libraries across 2 servers fetch in exactly 7 network calls', () async {
      var serverACalls = 0;
      var serverBCalls = 0;

      final clientA = JellyfinClient.forTesting(
        connection: _connFor(serverId: 'srv-a', baseUrl: 'https://jf-a.example.com'),
        httpClient: MockClient((req) async {
          serverACalls++;
          if (req.url.path == '/Users/user-1/Views') {
            return _json({
              'Items': [
                {'Id': 'lib-a1', 'Name': 'Movies A', 'CollectionType': 'movies'},
                {'Id': 'lib-a2', 'Name': 'Shows A', 'CollectionType': 'tvshows'},
              ],
            });
          }
          if (req.url.path == '/Users/user-1/Items/Latest') {
            final parentId = req.url.queryParameters['ParentId']!;
            return _json({
              'Items': [
                {'Id': 'item-$parentId', 'Type': 'Movie', 'Name': 'Latest $parentId', 'ParentLibraryId': parentId},
              ],
            });
          }
          return http.Response('unexpected request', 500);
        }),
      );
      final clientB = JellyfinClient.forTesting(
        connection: _connFor(serverId: 'srv-b', baseUrl: 'https://jf-b.example.com'),
        httpClient: MockClient((req) async {
          serverBCalls++;
          if (req.url.path == '/Users/user-1/Views') {
            return _json({
              'Items': [
                {'Id': 'lib-b1', 'Name': 'Movies B', 'CollectionType': 'movies'},
                {'Id': 'lib-b2', 'Name': 'Shows B', 'CollectionType': 'tvshows'},
                {'Id': 'lib-b3', 'Name': 'Docs B', 'CollectionType': 'movies'},
              ],
            });
          }
          if (req.url.path == '/Users/user-1/Items/Latest') {
            final parentId = req.url.queryParameters['ParentId']!;
            return _json({
              'Items': [
                {'Id': 'item-$parentId', 'Type': 'Movie', 'Name': 'Latest $parentId', 'ParentLibraryId': parentId},
              ],
            });
          }
          return http.Response('unexpected request', 500);
        }),
      );
      addTearDown(clientA.close);
      addTearDown(clientB.close);
      manager.debugRegisterJellyfinClientForTesting(clientA);
      manager.debugRegisterJellyfinClientForTesting(clientB);

      final result = await service.getHubsFromAllServers(useGlobalHubs: false, includePlaybackHubs: false);

      expect(result.succeededServerIds, {'srv-a', 'srv-b'});
      expect(result.hubs, hasLength(5), reason: 'one hub per library across both servers');
      // Per server: 1 library-list call ("Views") + 1 "Latest" call per
      // visible library. Server A has 2 libraries (3 calls), server B has 3
      // (4 calls). This is the exact, named baseline — not a bound — so a
      // change in fan-out shape (batching, an added prefetch, a dropped
      // library-list call) shows up as a hard failure here.
      expect(serverACalls, 3, reason: '1 Views + 2 Latest for server A (2 libraries)');
      expect(serverBCalls, 4, reason: '1 Views + 3 Latest for server B (3 libraries)');
      expect(serverACalls + serverBCalls, 7, reason: 'total network calls for 5 libraries across 2 servers');
    });
  });
}

MediaItem _stubItem(String id, String title) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title,
  serverId: 'healthy',
  serverName: 'Healthy',
);

/// Minimal search-only client. With [hang] it never answers, standing in for a
/// server that is marked online but silently unreachable.
class _StubSearchClient implements MediaServerClient {
  _StubSearchClient({required this.id, required this.items, this.hang = false});

  final String id;
  final List<MediaItem> items;
  final bool hang;

  @override
  ServerId get serverId => ServerId(id);

  @override
  String? get serverName => id;

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<List<MediaItem>> searchItems(String query, {int limit = 100}) {
    if (hang) return Completer<List<MediaItem>>().future;
    return Future.value(items);
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
