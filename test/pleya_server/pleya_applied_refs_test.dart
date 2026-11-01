import 'dart:convert';
import 'dart:async';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/media/unified/carried_external_ids.dart';
import '../assistant/assistant_find_fakes.dart';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_title_facts.dart';
import 'package:pleya/assistant/assistant_title_facts_cache.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_identity.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/pleya_server_client.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/tmdb/tmdb_client.dart';
import 'package:pleya/services/unified_catalog/source_resolver.dart';
import 'package:pleya/utils/external_ids.dart';
import 'pleya_fake_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final twoTargets in [false, true]) {
    for (final change in ['hide', 'cap', 'fresh']) {
      test('I1 final issue rejects earlier target: twoTargets=$twoTargets change=$change', () async {
        final h = _RefsHarness();
        h.fake.items['film']!['title'] = 'Cosmic Detectives';
        h.fake.addLibrary(id: 'other', title: 'Other', kind: 'movies');
        h.fake.addItem(
          id: 'second',
          kind: 'movie',
          title: twoTargets ? 'Cosmic Detectives' : 'Lunar Explorers',
          libraryId: 'other',
          externalIds: {'tmdb': twoTargets ? 11 : 33},
        );
        h.extraValues['second'] = {'tmdb': twoTargets ? 11 : 33};
        final client = h.client();
        addTearDown(client.close);
        await client.refreshCapabilities();
        final hidden = <String>{};
        final base = findCtx([], libraries: [fakeLib('srv-1', 'films'), fakeLib('srv-1', 'other')], hidden: hidden);
        base.servers.debugRegisterClientForTesting(client);
        final entered = Completer<void>(), release = Completer<void>();
        var armed = false;
        h.before = (request) async {
          if (armed && request.url.path.endsWith('/items/second')) {
            entered.complete();
            await release.future;
          }
        };
        final ctx = AssistantToolContext(
          servers: base.servers,
          catalog: base.catalog,
          titleFacts: _CallbackFacts(() {
            client.debugForgetExternalIds();
            armed = true;
          }),
        );
        final pending = assistantTools.firstWhere((t) => t.name == 'find_title').run(ctx, null, {
          'kind': 'movie',
          'candidates': [
            {'title': 'Cosmic Detectives'},
            if (!twoTargets) {'title': 'Lunar Explorers'},
          ],
          'variants': ['Cosmic Detectives', 'Lunar Explorers'],
        });
        await entered.future;
        if (change == 'hide') hidden.add('srv-1:films');
        if (change == 'cap') {
          h.applied = false;
          await client.refreshCapabilities();
        }
        if (change == 'fresh') {
          h.value = {'tmdb': 22};
          await client.fetchItem('film');
        }
        release.complete();
        final result = await pending as AssistantToolResult;
        final cards = (result.display as AssistantTitleMatches).matches;
        expect(cards.expand((c) => c.targets).where((t) => t.item.id == 'film'), isEmpty);
        expect((result.data['matches'] as List).whereType<Map>().any((r) => r['item_id'] == 'film'), isFalse);
        expect(() => ctx.requireShownItem(ServerId('srv-1'), 'film'), throwsA(isA<AssistantToolError>()));
        if (change == 'hide' && !twoTargets) expect(cards.any((c) => c.title == 'Cosmic Detectives'), isFalse);
      });
    }
  }
  for (final historical in [false, true]) {
    test('I2 hidden-only applied positive stays unchecked after reopening: historical=$historical', () async {
      final h = _RefsHarness()..applied = !historical;
      h.fake.addLibrary(id: 'visible', title: 'Visible', kind: 'movies');
      h.fake.addItem(id: 'unknown', kind: 'movie', title: 'Unmatched', libraryId: 'visible');
      final client = h.client();
      addTearDown(client.close);
      await client.refreshCapabilities();
      final dir = await Directory.systemTemp.createTemp('task5-b2-fix-');
      var db = AppDatabase.forTesting(NativeDatabase(File('${dir.path}/db.sqlite')));
      addTearDown(() async {
        await db.close();
        await dir.delete(recursive: true);
      });
      PlexApiCache.initialize(db);
      SourceAllResolver resolver() => SourceAllResolver(
        profileId: 'profile',
        serversFor: () => [
          (
            serverId: client.serverId,
            backend: MediaBackend.pleyaServer,
            client: client,
            online: true,
            hasAuthError: false,
          ),
        ],
        cache: PlexApiCache.instance,
        hiddenLibraryKeysFor: () => {'srv-1:films'},
      );
      if (historical) {
        await resolver().resolveAllSourcesForGroup(_identity(11));
        final row = await db.select(db.apiCache).getSingle();
        final raw = jsonDecode(row.data) as Map<String, dynamic>;
        raw['identitySources'] = {'srv-1': 'pleya:applied'};
        await PlexApiCache.instance.put(
          SourceAllResolver.cacheServerId,
          row.cacheKey.substring('${SourceAllResolver.cacheServerId}:'.length),
          raw,
        );
        h.applied = true;
        await client.refreshCapabilities();
      }
      for (var round = 0; round < 2; round++) {
        final got = await resolver().resolveAllSourcesForGroup(_identity(11));
        expect(got.items, isEmpty);
        expect(got.coverage.isComplete, isFalse);
        if (!historical) expect(await db.select(db.apiCache).get(), isEmpty);
        await db.close();
        db = AppDatabase.forTesting(NativeDatabase(File('${dir.path}/db.sqlite')));
        PlexApiCache.initialize(db);
      }
    });
  }
  for (final change in ['cap', 'client']) {
    test('I3 detached external facts survive original library change: $change', () async {
      final h = _RefsHarness();
      h.fake.items['film']!['genres'] = ['Server A'];
      final client = h.client();
      addTearDown(client.close);
      await client.refreshCapabilities();
      final item = (await client.fetchItem('film'))!;
      var current = client;
      final cache = _HeldCache(heldId: 22);
      await cache.put(TmdbKind.movie, 22, 'en:off', TitleFacts.from('tmdb', genres: ['External B']));
      final service = TitleFactsService(
        cache: cache,
        clientFor: (_) => current,
        online: () => false,
        traktClientId: '',
      );
      final pending = service.factsFor([
        TitleRef(
          kind: TmdbKind.movie,
          title: 'B',
          tmdbId: 22,
          idsAreExternal: true,
          item: item,
          serverId: item.serverId,
        ),
      ]);
      await cache.entered.future;
      if (change == 'cap') {
        h.applied = false;
        await client.refreshCapabilities();
      } else {
        current = h.client();
        addTearDown(current.close);
        await current.refreshCapabilities();
      }
      cache.release.complete();
      expect((await pending).single.genres, ['External B']);
      expect((await service.factsFor([const TitleRef(kind: TmdbKind.movie, title: 'B', tmdbId: 22)])).single.genres, [
        'External B',
      ]);
    });
  }
  for (final unknown in [false, true]) {
    test('library ref cannot retain requested B before facts dedupe: unknown=$unknown', () async {
      final h = _RefsHarness()..value = unknown ? null : {'tmdb': 11};
      final client = h.client();
      addTearDown(client.close);
      await client.refreshCapabilities();
      final item = (await client.fetchItem('film'))!;
      final cache = TitleFactsCache();
      await cache.put(TmdbKind.movie, 11, 'en:off', TitleFacts.from('tmdb', genres: ['Applied A']));
      await cache.put(TmdbKind.movie, 22, 'en:off', TitleFacts.from('tmdb', genres: ['Requested B']));
      final service = TitleFactsService(cache: cache, clientFor: (_) => client, online: () => false, traktClientId: '');
      final got = await service.factsFor([
        TitleRef(kind: TmdbKind.movie, title: 'Film', tmdbId: 22, item: item, serverId: item.serverId),
        const TitleRef(kind: TmdbKind.movie, title: 'External B', tmdbId: 22),
      ]);
      expect(got[0].genres, unknown ? isEmpty : ['Applied A']);
      expect(got[1].genres, ['Requested B'], reason: 'external facts for B remain valid');
    });
  }
  test('empty applied lookup is unchecked through actual fanout, never cached as absence', () async {
    final h = _RefsHarness()..value = null;
    final client = h.client();
    addTearDown(client.close);
    await client.refreshCapabilities();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    PlexApiCache.initialize(db);
    final resolver = _resolver(client, PlexApiCache.instance);
    final got = await resolver.resolveAllSourcesForGroup(_identity(11));
    expect(got.items, isEmpty);
    expect(got.coverage.isComplete, isFalse);
    expect(await db.select(db.apiCache).get(), isEmpty, reason: 'incomplete negative must not be persisted');
  });
  for (final positive in [false, true]) {
    test('persisted unqualified ${positive ? 'positive' : 'negative'} cannot survive cap transition', () async {
      final h = _RefsHarness()..applied = false;
      final client = h.client();
      addTearDown(client.close);
      await client.refreshCapabilities();
      final dir = await Directory.systemTemp.createTemp('task5-b2-cache-');
      final file = File('${dir.path}/cache.sqlite');
      var db = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(() async {
        await db.close();
        await dir.delete(recursive: true);
      });
      PlexApiCache.initialize(db);
      final identity = _identity(positive ? 22 : 11);
      final first = await _resolver(client, PlexApiCache.instance).resolveAllSourcesForGroup(identity);
      expect(first.coverage.isComplete, isTrue);
      expect(first.items, positive ? isNotEmpty : isEmpty);
      // Historical rows had no provenance; retain the actual cache key/data.
      final row = await db.select(db.apiCache).getSingle();
      final raw = jsonDecode(row.data) as Map<String, dynamic>;
      raw.remove('identitySources');
      await PlexApiCache.instance.put(
        SourceAllResolver.cacheServerId,
        row.cacheKey.substring('${SourceAllResolver.cacheServerId}:'.length),
        raw,
      );
      await db.close();
      db = AppDatabase.forTesting(NativeDatabase(file));
      PlexApiCache.initialize(db);
      h.applied = true;
      await client.refreshCapabilities();
      final got = await _resolver(client, PlexApiCache.instance).resolveAllSourcesForGroup(identity);
      expect(got.items.map((x) => x.id).toList(), positive ? isEmpty : ['film']);
      expect(got.coverage.isComplete, !positive, reason: 'only real applied positive proves presence');
    });
  }
  for (final unknown in [false, true]) {
    test('same-cap fresh B/unknown overrides persisted A: unknown=$unknown', () async {
      final h = _RefsHarness();
      final client = h.client();
      addTearDown(client.close);
      await client.refreshCapabilities();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      PlexApiCache.initialize(db);
      final resolver = _resolver(client, PlexApiCache.instance);
      expect((await resolver.resolveAllSourcesForGroup(_identity(11))).items, hasLength(1));
      h.value = unknown ? null : {'tmdb': 22};
      final fresh = (await client.fetchItem('film'))!;
      expect(externalIdsCarriedBy(fresh)?.tmdb, unknown ? null : 22);
      final got = await resolver.resolveAllSourcesForGroup(_identity(11));
      expect(got.items, isEmpty, reason: 'current known B contradicts old applied A even with the same capability');
      expect(got.coverage.isComplete, isFalse);
    });
  }
  test('no recent contrary observation keeps qualified positive TTL without HTTP', () async {
    final h = _RefsHarness();
    final client = h.client();
    addTearDown(client.close);
    await client.refreshCapabilities();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    PlexApiCache.initialize(db);
    final resolver = _resolver(client, PlexApiCache.instance);
    expect((await resolver.resolveAllSourcesForGroup(_identity(11))).items, hasLength(1));
    client.debugForgetExternalIds();
    h.value = {'tmdb': 22}; // not observed: do not silently invent a new TTL policy.
    final reads = h.reads;
    expect((await resolver.resolveAllSourcesForGroup(_identity(11))).items, hasLength(1));
    expect(h.reads, reads);
  });
  test('qualified other backend negative cache remains valid offline', () async {
    final server = FakeServer('other');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    PlexApiCache.initialize(db);
    var online = true;
    final resolver = SourceAllResolver(
      profileId: 'p',
      cache: PlexApiCache.instance,
      serversFor: () => [
        (
          serverId: server.serverId,
          backend: online ? server.backend : MediaBackend.plex,
          client: online ? server : null,
          online: online,
          hasAuthError: false,
        ),
      ],
    );
    expect((await resolver.resolveAllSourcesForGroup(_identity(11))).coverage.isComplete, isTrue);
    online = false;
    expect((await resolver.resolveAllSourcesForGroup(_identity(11))).coverage.isComplete, isTrue);
    expect(server.identities, hasLength(1));
  });
  test('historical negative with default Plex missing-client fallback is unchecked', () async {
    final h = _RefsHarness()..applied = false;
    final client = h.client();
    addTearDown(client.close);
    await client.refreshCapabilities();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    PlexApiCache.initialize(db);
    await _resolver(client, PlexApiCache.instance).resolveAllSourcesForGroup(_identity(11));
    final row = await db.select(db.apiCache).getSingle();
    final raw = jsonDecode(row.data) as Map<String, dynamic>;
    raw.remove('identitySources');
    await PlexApiCache.instance.put(
      SourceAllResolver.cacheServerId,
      row.cacheKey.substring('${SourceAllResolver.cacheServerId}:'.length),
      raw,
    );
    final resolver = SourceAllResolver(
      profileId: 'profile',
      cache: PlexApiCache.instance,
      serversFor: () => [
        (serverId: client.serverId, backend: MediaBackend.plex, client: null, online: false, hasAuthError: false),
      ],
    );
    expect((await resolver.resolveAllSourcesForGroup(_identity(11))).coverage.isComplete, isFalse);
  });
  test('warm library future is requalified and completed result cannot outlive another held read', () async {
    final h = _RefsHarness()..applied = false;
    final client = h.client();
    addTearDown(client.close);
    await client.refreshCapabilities();
    final item = (await client.fetchItem('film'))!;
    final cache = _HeldCache();
    await cache.put(TmdbKind.movie, 11, 'en:off', TitleFacts.from('tmdb', genres: ['A']));
    await cache.put(TmdbKind.movie, 22, 'en:off', TitleFacts.from('tmdb', genres: ['B']));
    final service = TitleFactsService(cache: cache, clientFor: (_) => client, online: () => false, traktClientId: '');
    final ref = TitleRef(kind: TmdbKind.movie, title: 'Film', tmdbId: 22, item: item, serverId: item.serverId);
    expect((await service.factsFor([ref])).single.genres, ['B']);
    final pending = service.factsFor([ref, const TitleRef(kind: TmdbKind.movie, title: 'Held', tmdbId: 33)]);
    await cache.entered.future;
    await Future<void>.delayed(Duration.zero);
    h.applied = true;
    await client.refreshCapabilities();
    cache.release.complete();
    final stale = await pending;
    expect(stale[0].genres, isNot(contains('B')));
    expect((await service.factsFor([ref])).single.genres, ['A']);
    expect((await cache.get(TmdbKind.movie, 22, 'en:off'))!.genres, ['B']);
  });
  for (final offline in [false, true]) {
    for (final wrongParent in [false, true]) {
      test('real episode target uses show proof and ordinal: offline=$offline wrongParent=$wrongParent', () async {
        final h = _RefsHarness();
        h.fake.addLibrary(id: 'shows', title: 'Shows', kind: 'shows');
        h.fake.addItem(
          id: 'show',
          kind: 'show',
          title: 'Cosmic Detectives',
          libraryId: 'shows',
          externalIds: {'tmdb': 11},
        );
        h.fake.addItem(id: 'season', kind: 'season', title: 'Season 1', parentId: 'show', index: 1);
        h.fake.addItem(id: 'episode', kind: 'episode', title: 'Second', parentId: 'season', index: 2);
        if (wrongParent) {
          h.fake.addItem(id: 'unrelated-show', kind: 'show', title: 'Other show');
          h.fake.items['season']!['parent_id'] = 'unrelated-show';
        }
        h.extraValues['show'] = {'tmdb': 11};
        final client = h.client();
        addTearDown(client.close);
        await client.refreshCapabilities();
        final base = findCtx([], libraries: [fakeLib('srv-1', 'shows', kind: MediaKind.show)]);
        base.servers.debugRegisterClientForTesting(client);
        final cache = TitleFactsCache();
        await cache.put(TmdbKind.tv, 11, 'en:off', TitleFacts.from('tmdb', genres: ['Show facts']));
        final ctx = AssistantToolContext(
          servers: base.servers,
          catalog: base.catalog,
          titleFacts: _SwitchingFacts(
            cache: cache,
            clientFor: base.userClient,
            before: () async {
              if (offline) base.servers.removeServer(client.serverId);
            },
          ),
        );
        final result =
            await assistantTools.firstWhere((t) => t.name == 'find_title').run(ctx, null, {
                  'kind': 'episode',
                  'series': 'Cosmic Detectives',
                  'season': 1,
                  'episode': 2,
                  'variants': ['Second'],
                  'candidates': [
                    {'title': 'Cosmic Detectives', 'kind': 'show'},
                  ],
                })
                as AssistantToolResult;
        final row = (result.data['matches'] as List).first as Map;
        final card = (result.display as AssistantTitleMatches).matches.first;
        expect(row['in_library'], !wrongParent);
        if (wrongParent) {
          expect(card.targets, isEmpty);
          expect(result.data['partial'], isTrue);
        } else {
          expect([row['item_id'], row['season'], row['episode']], ['episode', 1, 2]);
          expect(card.targets.single.item.id, 'episode', reason: 'the show is proof, not the playable target');
          expect((row['facts'] as Map)['genres'], ['Show facts']);
        }
      });
    }
  }
  test('library hidden during facts await is absent from final cards and shown targets', () async {
    final h = _RefsHarness();
    h.fake.items['film']!['title'] = 'Cosmic Detectives';
    final client = h.client();
    addTearDown(client.close);
    await client.refreshCapabilities();
    final hidden = <String>{};
    final base = findCtx([], libraries: [fakeLib('srv-1', 'films')], hidden: hidden);
    base.servers.debugRegisterClientForTesting(client);
    final ctx = AssistantToolContext(
      servers: base.servers,
      catalog: base.catalog,
      titleFacts: _SwitchingFacts(
        cache: TitleFactsCache(),
        clientFor: base.userClient,
        before: () async {
          hidden.add('srv-1:films');
        },
      ),
    );
    final result = await runFind(ctx, {
      'kind': 'movie',
      'candidates': [
        {'title': 'Cosmic Detectives'},
      ],
      'variants': ['Cosmic Detectives'],
    });
    expect(matchesOf(result), isEmpty);
    expect(() => ctx.requireShownItem(ServerId('srv-1'), 'film'), throwsA(isA<AssistantToolError>()));
  });
  test('actual trending end card keeps external B facts but no unproven Pleya A target', () async {
    final h = _RefsHarness()..applied = false;
    final client = h.client();
    addTearDown(client.close);
    await client.refreshCapabilities();
    final seerr = FakeSeerr()
      ..details['/discover/trending'] = {
        'results': [
          {
            'id': 22,
            'mediaType': 'movie',
            'title': 'Film',
            'releaseDate': '2000-01-01',
            'originalLanguage': 'en',
            'voteCount': 1500,
          },
        ],
      };
    addTearDown(seerr.client.dispose);
    final base = findCtx([], libraries: [fakeLib('srv-1', 'films')], seerr: seerr);
    base.servers.debugRegisterClientForTesting(client);
    final facts = TitleFactsCache();
    await facts.put(TmdbKind.movie, 11, 'en:off', TitleFacts.from('tmdb', genres: ['Applied A']));
    await facts.put(TmdbKind.movie, 22, 'en:off', TitleFacts.from('tmdb', genres: ['External B']));
    final ctx = AssistantToolContext(
      servers: base.servers,
      catalog: base.catalog,
      requests: base.requests,
      titleFacts: _SwitchingFacts(
        cache: facts,
        clientFor: base.userClient,
        before: () async {
          h.applied = true;
          await client.refreshCapabilities();
        },
      ),
    );
    final outcome =
        await assistantTools.firstWhere((t) => t.name == 'trending_titles').run(ctx, null, {'kind': 'movie'})
            as AssistantToolResult;
    final row = (outcome.data['titles'] as List).single as Map;
    expect(row['in_library'], isFalse);
    expect((outcome.display as AssistantTitleMatches).matches.single.targets, isEmpty);
    expect((row['facts'] as Map)['genres'], ['External B']);
    expect(outcome.data['partial'], isTrue, reason: 'unproven copy is uncertainty, not proven absence');
  });
}

MediaIdentity _identity(int n) => MediaIdentity(
  externalIds: ExternalIds(tmdb: n),
  title: 'Film',
  kind: MediaKind.movie,
);
SourceAllResolver _resolver(PleyaServerClient client, PlexApiCache cache) => SourceAllResolver(
  profileId: 'profile',
  serversFor: () => [
    (serverId: client.serverId, backend: MediaBackend.pleyaServer, client: client, online: true, hasAuthError: false),
  ],
  cache: cache,
);

class _RefsHarness {
  _RefsHarness() {
    fake.addLibrary(id: 'films', title: 'Films', kind: 'movies');
    fake.addItem(id: 'film', kind: 'movie', title: 'Film', libraryId: 'films', externalIds: {'tmdb': 22});
  }
  final fake = PleyaFakeServer();
  bool applied = true;
  Object? value = {'tmdb': 11};
  int reads = 0;
  Future<void> Function(http.Request)? before;
  final extraValues = <String, Object?>{};
  PleyaServerClient client() => PleyaServerClient.create(
    fake.connection(),
    httpClientFactory: () => MockClient((request) async {
      reads++;
      await before?.call(request);
      final response = await fake.handle(request);
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        if (request.url.path.endsWith('/info')) (body['capabilities'] as Map)['applied_external_identity'] = applied;
        void stamp(Map<String, dynamic> item) {
          if (item['id'] == 'film') item['applied_external_ids'] = value;
          if (extraValues.containsKey(item['id'])) item['applied_external_ids'] = extraValues[item['id']];
        }

        stamp(body);
        for (final item in body['items'] as List? ?? const []) {
          if (item is Map<String, dynamic>) stamp(item);
        }
      }
      return http.Response(jsonEncode(body), response.statusCode, headers: response.headers);
    }),
  );
}

class _SwitchingFacts extends TitleFactsService {
  _SwitchingFacts({required super.cache, required super.clientFor, required this.before})
    : super(online: () => false, traktClientId: '');
  final Future<void> Function() before;
  @override
  Future<List<TitleFacts>> factsFor(List<TitleRef> refs) async {
    await before();
    return super.factsFor(refs);
  }
}

class _HeldCache extends TitleFactsCache {
  _HeldCache({this.heldId = 33});
  final int heldId;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<TitleFacts?> get(TmdbKind kind, int tmdbId, String lang) async {
    if (tmdbId == heldId) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    return super.get(kind, tmdbId, lang);
  }
}

class _CallbackFacts extends TitleFactsService {
  _CallbackFacts(this.callback) : super(cache: TitleFactsCache(), online: () => false, traktClientId: '');
  final void Function() callback;
  @override
  Future<List<TitleFacts>> factsFor(List<TitleRef> refs) async {
    callback();
    return [for (final _ in refs) const TitleFacts()];
  }
}
