import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/exceptions/identity_lookup_exceptions.dart';
import 'package:pleya/assistant/assistant_find_route.dart';
import 'package:pleya/assistant/assistant_find_match.dart';
import 'package:pleya/assistant/assistant_plot_index.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/assistant/assistant_web_lookup.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/seerr/seerr_client.dart';
import 'package:pleya/services/seerr/seerr_session.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import '../assistant/assistant_find_fakes.dart' show FakeServer;
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/identity_evidence.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/services/unified_catalog/identity_resolver.dart';
import 'package:pleya/services/unified_catalog/unified_copy_proof.dart';
import 'package:pleya/media/media_identity.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/services/unified_catalog/catalog_service.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/providers/local_library_provider.dart';
import 'package:pleya/services/local_library/local_library_store.dart';
import 'package:pleya/utils/stored_identity_trust.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/media/unified/carried_external_ids.dart';
import 'package:pleya/services/pleya_server_client.dart';
import 'package:pleya/utils/external_ids.dart';

import 'pleya_fake_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('applied capability chooses published A instead of requested B on detail and lookup', () async {
    final fake = PleyaFakeServer();
    fake.addLibrary(id: 'films', title: 'Films', kind: 'movies');
    fake.addItem(id: 'film', kind: 'movie', title: 'Film', libraryId: 'films', externalIds: {'tmdb': 22});
    final queries = <Map<String, String>>[];
    final client = PleyaServerClient.create(
      fake.connection(),
      httpClientFactory: () => MockClient((request) async {
        if (request.url.path.endsWith('/items')) queries.add(request.url.queryParameters);
        final response = await fake.handle(request);
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          if (request.url.path.endsWith('/info')) {
            (body['capabilities'] as Map)['applied_external_identity'] = true;
          }
          void apply(Map<String, dynamic> item) {
            if (item['id'] == 'film') item['applied_external_ids'] = {'tmdb': 11};
          }

          apply(body);
          for (final item in (body['items'] as List? ?? const [])) {
            if (item is Map<String, dynamic>) apply(item);
          }
        }
        return http.Response(jsonEncode(body), response.statusCode, headers: response.headers);
      }),
    );
    addTearDown(client.close);
    await client.refreshCapabilities();
    final item = await client.fetchItem('film');
    expect(externalIdsCarriedBy(item!), const ExternalIds(tmdb: 11));
    expect(await client.fetchExternalIds('film'), const ExternalIds(tmdb: 11));
  });

  test('applied missing null or malformed never falls back to legacy intent', () async {
    for (final value in <Object?>[
      null,
      {'tmdb': '11'},
      {'tmdb': -1},
      'tmdb:11',
    ]) {
      final fake = PleyaFakeServer();
      fake.addLibrary(id: 'films', title: 'Films', kind: 'movies');
      fake.addItem(id: 'film', kind: 'movie', title: 'Film', libraryId: 'films', externalIds: {'tmdb': 22});
      final client = PleyaServerClient.create(
        fake.connection(),
        httpClientFactory: () => MockClient((request) async {
          final response = await fake.handle(request);
          final body = jsonDecode(response.body);
          if (body is Map<String, dynamic>) {
            if (request.url.path.endsWith('/info')) (body['capabilities'] as Map)['applied_external_identity'] = true;
            if (body['id'] == 'film') body['applied_external_ids'] = value;
          }
          return http.Response(jsonEncode(body), response.statusCode, headers: response.headers);
        }),
      );
      await client.refreshCapabilities();
      final answer = await client.fetchExternalIdsDetailed('film');
      expect(answer.ids.hasAny, isFalse, reason: '$value');
      expect(answer.authoritative, isFalse, reason: 'unknown applied is never a final empty answer');
      client.close();
    }
  });
  test('absent applied key is unknown even with a positive legacy identity', () async {
    final h = _AppliedHarness()..includeApplied = false;
    final client = h.client();
    addTearDown(client.close);
    await client.refreshCapabilities();
    final item = (await client.fetchItem('film'))!;
    expect(externalIdsCarriedBy(item), isNull);
    final answer = await client.fetchExternalIdsDetailed('film');
    expect(answer.ids.hasAny, isFalse);
    expect(answer.authoritative, isFalse);
  });

  test('capability transition invalidates warm legacy answer and does not downgrade on info failure', () async {
    final h = _AppliedHarness()..applied = false;
    final client = h.client();
    addTearDown(client.close);
    await client.refreshCapabilities();
    final old = (await client.fetchItem('film'))!;
    expect(await client.fetchExternalIds('film'), const ExternalIds(tmdb: 22));
    expect(client.canUseStoredExternalIds(old), isTrue);
    h.applied = true;
    await client.refreshCapabilities();
    expect(client.canUseStoredExternalIds(old), isFalse);
    expect(await client.fetchExternalIds('film'), const ExternalIds(tmdb: 11));
    h.infoFailure = true;
    expect(await client.refreshCapabilities(), isNull);
    expect(client.wireCapabilities.appliedExternalIdentity, isTrue);
    expect(client.canUseStoredExternalIds(old), isFalse);
    h.appliedValue = null;
    await client.fetchItem('film');
    final unknown = await client.fetchExternalIdsDetailed('film');
    expect(unknown.ids.hasAny, isFalse);
    expect(unknown.authoritative, isFalse);
  });

  test('applied lookup sends own filter and verifies each returned item instead of trusting ignored query', () async {
    final h = _AppliedHarness();
    final client = h.client();
    addTearDown(client.close);
    await client.refreshCapabilities();
    final a = await client.findAllByIdentity(
      const MediaIdentity(title: 'Other title', kind: MediaKind.movie, externalIds: ExternalIds(tmdb: 11)),
    );
    expect(a.map((item) => item.id), ['film']);
    expect(h.queries.last['applied_external_id'], 'tmdb:11');
    expect(h.queries.last.containsKey('external_id'), isFalse);
    final b = await client.findAllByIdentity(
      const MediaIdentity(title: 'Film', kind: MediaKind.movie, externalIds: ExternalIds(tmdb: 22)),
    );
    expect(b, isEmpty, reason: 'the fixture ignores applied filter, so response evidence must reject B');
  });

  test('actual snapshot reopening preserves applied proof and rejects legacy until explicitly old info', () async {
    final directory = await Directory.systemTemp.createTemp('pleya-applied-proof-');
    addTearDown(() => directory.delete(recursive: true));
    final h = _AppliedHarness();
    final live = h.client();
    addTearDown(live.close);
    await live.refreshCapabilities();
    final a = (await live.fetchItem('film'))!.copyWith(libraryId: 'films');
    const library = MediaLibrary(
      id: 'films',
      backend: MediaBackend.pleyaServer,
      title: 'Films',
      kind: MediaKind.movie,
      serverId: 'srv-1',
    );
    final old = a.copyWith(
      id: 'legacy',
      raw: {
        pleyaExternalIdsRawKey: {'tmdb': 22},
        pleyaExternalIdsSourceKey: 'legacy',
        'pleyaLocalExternalIds': {'tmdb': 22},
        'pleyaLocalExternalIdsFinal': true,
      },
    );
    final unqualified = a.copyWith(
      id: 'unqualified',
      raw: {
        'pleyaLocalExternalIds': {'tmdb': 22},
        'pleyaLocalExternalIdsFinal': true,
      },
    );
    final first = LocalLibraryStore(directory);
    await first.load();
    await first.saveLibrary(library, [a, old, unqualified], complete: true);
    final reopened = LocalLibraryStore(directory);
    await reopened.load();
    expect(externalIdsCarriedBy(reopened.libraryItems(library.globalKey).first), const ExternalIds(tmdb: 11));
    final unknownClient = h.client();
    addTearDown(unknownClient.close);
    final changes = ChangeNotifier();
    addTearDown(changes.dispose);
    final provider = LocalLibraryProvider(
      profileId: 'synthetic',
      directory: directory,
      librariesForSync: () => [library],
      clientFor: (_) => unknownClient,
      mayReadServer: (_) => true,
      mayReadLibrary: (_) => true,
      networkConnected: () => false,
      wifiConnected: () => false,
      changes: changes,
    );
    await provider.ready;
    addTearDown(() async {
      provider.dispose();
      await provider.pendingStoreWrites;
    });
    expect(provider.externalIds('srv-1', 'film'), const ExternalIds(tmdb: 11));
    expect(provider.externalIds('srv-1', 'legacy'), isNull);
    expect(provider.externalIds('srv-1', 'unqualified'), isNull);
    h.applied = false;
    await unknownClient.refreshCapabilities();
    expect(provider.externalIds('srv-1', 'legacy'), const ExternalIds(tmdb: 22));
    expect(provider.externalIds('srv-1', 'unqualified'), const ExternalIds(tmdb: 22));
    h.applied = true;
    await unknownClient.refreshCapabilities();
    expect(provider.externalIds('srv-1', 'legacy'), isNull);
    expect(provider.externalIds('srv-1', 'unqualified'), isNull);
    expect(canTrustStoredIdentity(a, unknownClient), isTrue);
  });

  test('resolver refuses unqualified carried and known positives by default or after capability transition', () async {
    final h = _AppliedHarness()..applied = false;
    final client = h.client();
    addTearDown(client.close);
    await client.refreshCapabilities();
    final stale = (await client.fetchItem('film'))!;
    h.applied = true;
    await client.refreshCapabilities();
    final other = MediaItem(
      id: 'other',
      backend: MediaBackend.plex,
      kind: MediaKind.movie,
      title: 'Film',
      serverId: 'plex',
    );
    final rows = [
      for (final item in [stale, other])
        ResolvableItem(
          item: item,
          identity: canonicalIdentityOf(item),
          scope: 'movie',
          externalIdTarget: (serverId: item.serverId!, targetId: item.id),
        ),
    ];
    for (final contextual in [false, true]) {
      var fetches = 0;
      final resolver = UnifiedIdentityResolver(
        trustStoredIdentity: contextual ? (item) => canTrustStoredIdentity(item, client) : storedIdentityIsSafe,
        fetchExternalIds: (server, id) async {
          fetches++;
          return const ExternalIds(tmdb: 11);
        },
      );
      final evidence = await resolver.resolveEvidence(
        rows,
        known: (_) => IdentityEvidence(
          identity: CanonicalMediaIdentity.opaque(),
          strongTokens: externalIdTokens(scope: 'movie', ids: const ExternalIds(tmdb: 22)),
        ),
      );
      expect(evidence.first.strongTokens.map((t) => t.key), contains('movie:tmdb:11'));
      expect(evidence.first.strongTokens.map((t) => t.key), isNot(contains('movie:tmdb:22')));
      expect(fetches, 1);
    }
  });

  test('copy proof cannot let source.externalIds override applied item or a new capability', () async {
    final h = _AppliedHarness()..applied = false;
    final client = h.client();
    addTearDown(client.close);
    await client.refreshCapabilities();
    final stale = (await client.fetchItem('film'))!;
    UnifiedMediaSource source(MediaItem item, int number) => UnifiedMediaSource(
      sourceKey: item.globalKey,
      item: item,
      serverId: ServerId(item.serverId!),
      serverName: 'synthetic',
      backend: item.backend,
      externalIds: ExternalIds(tmdb: number),
    );
    final plex = MediaItem(
      id: 'plex',
      backend: MediaBackend.plex,
      kind: MediaKind.movie,
      title: 'Film',
      serverId: 'plex',
    );
    final proof = UnifiedCopyProof((id) => id.value == 'srv-1' ? client : null);
    expect(await proof.sameTitle(source(stale, 22), source(plex, 22)), isTrue);
    h.applied = true;
    await client.refreshCapabilities();
    expect(await proof.sameTitle(source(stale, 22), source(plex, 22)), isFalse);
    final a = (await client.fetchItem('film'))!;
    expect(
      await proof.sameTitle(source(a, 22), source(plex, 22)),
      isFalse,
      reason: 'a stale source claim B cannot override item proof A',
    );
    expect(await proof.sameTitle(source(a, 22), source(plex, 11)), isTrue);
  });
  test('real find route revalidates its warm library callback cache after applied capability changes', () async {
    final h = _AppliedHarness()..applied = false;
    final client = h.client();
    await client.refreshCapabilities();
    final old = (await client.fetchItem('film'))!;
    final manager = MultiServerManager();
    manager.debugRegisterClientForTesting(client);
    final other = FakeServer('other', ids: {'other-film': const ExternalIds(tmdb: 22)});
    manager.debugRegisterClientForTesting(other);
    addTearDown(manager.dispose);
    var flipped = false;
    final seerr = SeerrClient(
      const SeerrSession(baseUrl: 'http://synthetic.lan', authMode: SeerrAuthMode.apiKey, apiKey: 'synthetic'),
      httpClient: MockClient((request) async {
        if (!flipped) {
          flipped = true;
          h.applied = true;
          await client.refreshCapabilities();
        }
        return http.Response('{}', 200, headers: {'content-type': 'application/json'});
      }),
    );
    final ctx = AssistantToolContext(
      servers: manager,
      requests: AssistantRequestServices(client: () => seerr),
    );
    final run = FindRun(
      ctx,
      const FindQuery(),
      const Duration(seconds: 5),
      AssistantPlotIndexCache(),
      AssistantWebCache(),
    );
    run.matches.addAll([
      FindMatch('Candidate A', kind: MediaKind.movie)..library.add(old),
      FindMatch('Candidate B', kind: MediaKind.movie)
        ..library.add(
          MediaItem(
            id: 'other-film',
            backend: MediaBackend.jellyfin,
            kind: MediaKind.movie,
            title: 'Film',
            serverId: 'other',
          ),
        ),
    ]);
    final result = await run.run(Duration.zero);
    expect(flipped, isTrue);
    expect(result.matches, hasLength(2), reason: 'cached legacy22 must not falsely merge published11 with other22');
    expect(
      h.detailReads,
      greaterThan(1),
      reason: 'the real grouping callback must revalidate rather than return its warm _knownIds',
    );
  });
  for (final mode in <bool?>[false, true, null]) {
    test('catalog refuses unqualified cachedExternalIds unless explicit old capability: $mode', () async {
      final h = _AppliedHarness();
      final client = h.client();
      addTearDown(client.close);
      if (mode != null) {
        h.applied = mode;
        await client.refreshCapabilities();
      }
      final old = MediaItem(
        id: 'film',
        backend: MediaBackend.pleyaServer,
        kind: MediaKind.movie,
        title: 'Film',
        serverId: 'srv-1',
      );
      final other = MediaItem(
        id: 'other-film',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.movie,
        title: 'Film',
        serverId: 'other',
        raw: const {
          'ProviderIds': {'Tmdb': '22'},
        },
      );
      final otherClient = FakeServer('other', ids: {'other-film': const ExternalIds(tmdb: 22)});
      final cachedServers = <String>[];
      final service = UnifiedCatalogService(
        query: const UnifiedCatalogQuery(kind: MediaKind.movie),
        libraries: [
          for (final id in ['srv-1', 'other'])
            (
              serverId: ServerId(id),
              serverName: id,
              libraryId: 'films',
              libraryTitle: 'Films',
              backend: id == 'srv-1' ? MediaBackend.pleyaServer : MediaBackend.jellyfin,
            ),
        ],
        clientFor: (id) => id.value == 'srv-1' ? client : otherClient,
        cachedPage: (library, query) => LibraryPage(
          items: query.offset == 0 ? [library.serverId.value == 'srv-1' ? old : other] : [],
          totalCount: 1,
          offset: query.offset,
        ),
        cachedExternalIds: (server, id) {
          cachedServers.add(server);
          return const ExternalIds(tmdb: 22);
        },
      );
      final snapshot = await service.loadMore();
      expect(
        snapshot.groups,
        hasLength(mode == false ? 1 : 2),
        reason: 'published11 must not falsely merge with other22 on a cached legacy claim',
      );
      expect(h.detailReads > 0, mode != false, reason: 'new or unknown capability revalidates via the real client');
      expect(cachedServers.contains('srv-1'), mode == false);
    });
  }

  for (final mode in [
    (library: MediaBackend.pleyaServer, item: MediaBackend.pleyaServer, proof: false),
    (library: MediaBackend.jellyfin, item: MediaBackend.pleyaServer, proof: false),
    (library: MediaBackend.pleyaServer, item: MediaBackend.pleyaServer, proof: true),
    (library: MediaBackend.jellyfin, item: MediaBackend.jellyfin, proof: false),
  ]) {
    test('offline catalog with no client respects source backend and applied proof: $mode', () async {
      final old = MediaItem(
        id: 'film',
        backend: mode.item,
        kind: MediaKind.movie,
        title: 'Film',
        serverId: 'srv-1',
        raw: mode.proof
            ? {
                pleyaExternalIdsSourceKey: 'applied',
                pleyaExternalIdsRawKey: {'tmdb': 11},
              }
            : null,
      );
      final other = MediaItem(
        id: 'other-film',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.movie,
        title: 'Film',
        serverId: 'other',
        raw: const {
          'ProviderIds': {'Tmdb': '22'},
        },
      );
      final cachedServers = <String>[];
      final service = UnifiedCatalogService(
        query: const UnifiedCatalogQuery(kind: MediaKind.movie),
        libraries: [
          for (final id in ['srv-1', 'other'])
            (
              serverId: ServerId(id),
              serverName: id,
              libraryId: 'films',
              libraryTitle: 'Films',
              backend: id == 'srv-1' ? mode.library : MediaBackend.jellyfin,
            ),
        ],
        clientFor: (_) => null,
        cachedPage: (library, query) => LibraryPage(
          items: query.offset == 0 ? [library.serverId.value == 'srv-1' ? old : other] : [],
          totalCount: 1,
          offset: query.offset,
        ),
        cachedExternalIds: (server, id) {
          cachedServers.add(server);
          return const ExternalIds(tmdb: 22);
        },
      );
      final snapshot = await service.loadMore();
      expect(snapshot.groups, hasLength(mode.item == MediaBackend.pleyaServer ? 2 : 1));
      expect(cachedServers.contains('srv-1'), mode.item != MediaBackend.pleyaServer);
      if (mode.proof) expect(snapshot.groups.map((group) => group.groupId), contains('group:movie:tmdb:11'));
    });
  }
  test('resolver validates entire pass before returning or caching a completed legacy answer', () async {
    final h = _AppliedHarness()..applied = false;
    final client = h.client();
    addTearDown(client.close);
    await client.refreshCapabilities();
    final old = (await client.fetchItem('film'))!.copyWith(raw: {pleyaExternalIdsSourceKey: 'legacy'});
    final other = MediaItem(
      id: 'other',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.movie,
      title: 'Film',
      serverId: 'other',
    );
    final entered = Completer<void>();
    final answer = Completer<ExternalIds>();
    final remembered = <int>[];
    final resolver = UnifiedIdentityResolver(
      trustStoredIdentity: (item) => canTrustStoredIdentity(item, client),
      fetchExternalIds: (server, id) async {
        if (server == 'srv-1') return const ExternalIds(tmdb: 22);
        entered.complete();
        return answer.future;
      },
    );
    final pending = resolver.resolveEvidence([
      for (final item in [old, other])
        ResolvableItem(
          item: item,
          identity: canonicalIdentityOf(item),
          scope: 'movie',
          externalIdTarget: (serverId: item.serverId!, targetId: item.id),
        ),
    ], onResolved: (i, _) => remembered.add(i));
    await entered.future;
    h.applied = true;
    await client.refreshCapabilities();
    answer.complete(const ExternalIds(tmdb: 22));
    final evidence = await pending;
    expect(evidence.first.strongTokens.map((token) => token.key), isNot(contains('movie:tmdb:22')));
    expect(
      remembered,
      isNot(contains(0)),
      reason: 'a completed legacy result cannot enter known cache after the pass changed mode',
    );
  });

  test('copy proof validates trust after another source delayed the completed legacy result', () async {
    final h = _AppliedHarness()..applied = false;
    final client = h.client();
    addTearDown(client.close);
    await client.refreshCapabilities();
    final old = (await client.fetchItem('film'))!.copyWith(raw: {pleyaExternalIdsSourceKey: 'legacy'});
    final held = _HeldIdsServer();
    final other = MediaItem(
      id: 'other',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.movie,
      title: 'Film',
      serverId: 'other',
    );
    UnifiedMediaSource source(MediaItem item) => UnifiedMediaSource(
      sourceKey: item.globalKey,
      item: item,
      serverId: ServerId(item.serverId!),
      serverName: 'synthetic',
      backend: item.backend,
    );
    final proof = UnifiedCopyProof((id) => id.value == 'srv-1' ? client : held);
    final pending = proof.sameTitle(source(old), source(other));
    await held.entered.future;
    h.applied = true;
    await client.refreshCapabilities();
    held.answer.complete(const ExternalIds(tmdb: 22));
    expect(await pending, isFalse);
  });
  test('an in-flight lookup crossing identity modes is unavailable rather than a definitive empty answer', () async {
    final h = _AppliedHarness()
      ..applied = false
      ..listGate = Completer<void>();
    final client = h.client();
    addTearDown(client.close);
    await client.refreshCapabilities();
    final pending = client.findAllByIdentity(
      const MediaIdentity(title: 'Film', kind: MediaKind.movie, externalIds: ExternalIds(tmdb: 22)),
    );
    final checked = expectLater(pending, throwsA(isA<IdentityLookupUnavailable>()));
    await h.listEntered.future;
    h.applied = true;
    await client.refreshCapabilities();
    h.listGate!.complete();
    await checked;
  });
  for (final mode in ['pleya-offline-legacy', 'pleya-live-legacy', 'jellyfin-offline', 'pleya-offline-applied']) {
    test('FindRun warmed cache handles source disappearance: $mode', () async {
      final applied = mode == 'pleya-offline-applied';
      final number = applied ? 11 : 22;
      final h = _AppliedHarness()..applied = applied;
      final client = h.client();
      addTearDown(client.close);
      await client.refreshCapabilities();
      final live = (await client.fetchItem('film'))!;
      final old = mode == 'jellyfin-offline'
          ? MediaItem(
              id: 'film',
              backend: MediaBackend.jellyfin,
              kind: MediaKind.movie,
              title: 'Film',
              serverId: 'srv-1',
            )
          : applied
          ? live
          : live.copyWith(raw: {pleyaExternalIdsSourceKey: 'legacy'});
      final manager = MultiServerManager();
      if (mode == 'jellyfin-offline') {
        manager.debugRegisterClientForTesting(FakeServer('srv-1', ids: {'film': ExternalIds(tmdb: number)}));
      } else {
        manager.debugRegisterClientForTesting(client);
      }
      manager.debugRegisterClientForTesting(FakeServer('other', ids: {'other-film': ExternalIds(tmdb: number)}));
      addTearDown(manager.dispose);
      var transitioned = false;
      final seerr = SeerrClient(
        const SeerrSession(baseUrl: 'http://synthetic.lan', authMode: SeerrAuthMode.apiKey, apiKey: 'synthetic'),
        httpClient: MockClient((request) async {
          if (!transitioned) {
            transitioned = true;
            if (mode != 'pleya-live-legacy') manager.removeServer(ServerId('srv-1'));
          }
          return http.Response('{}', 200, headers: {'content-type': 'application/json'});
        }),
      );
      final ctx = AssistantToolContext(
        servers: manager,
        requests: AssistantRequestServices(client: () => seerr),
      );
      final run = FindRun(
        ctx,
        const FindQuery(),
        const Duration(seconds: 5),
        AssistantPlotIndexCache(),
        AssistantWebCache(),
      );
      run.matches.addAll([
        FindMatch('Candidate A', kind: MediaKind.movie)..library.add(old),
        FindMatch('Candidate B', kind: MediaKind.movie)
          ..library.add(
            MediaItem(
              id: 'other-film',
              backend: MediaBackend.jellyfin,
              kind: MediaKind.movie,
              title: 'Film',
              serverId: 'other',
            ),
          ),
      ]);
      final result = await run.run(Duration.zero);
      expect(transitioned, isTrue);
      if (mode != 'pleya-live-legacy') expect(ctx.userClient(ServerId('srv-1')), isNull);
      expect(
        result.matches,
        hasLength(mode == 'pleya-offline-legacy' ? 2 : 1),
        reason:
            'only unproven offline Pleya legacy must lose its warmed id; other backend, explicit legacy and applied proof remain usable',
      );
    });
  }
}

class _AppliedHarness {
  _AppliedHarness() {
    fake.addLibrary(id: 'films', title: 'Films', kind: 'movies');
    fake.addItem(id: 'film', kind: 'movie', title: 'Film', libraryId: 'films', externalIds: {'tmdb': 22});
  }
  final fake = PleyaFakeServer();
  bool applied = true;
  bool includeApplied = true;
  bool infoFailure = false;
  Object? appliedValue = const {'tmdb': 11};
  final queries = <Map<String, String>>[];
  int detailReads = 0;
  Completer<void>? listGate;
  final listEntered = Completer<void>();
  PleyaServerClient client() => PleyaServerClient.create(
    fake.connection(),
    httpClientFactory: () => MockClient((request) async {
      if (request.url.path.endsWith('/items')) {
        queries.add(request.url.queryParameters);
        if (listGate != null) {
          if (!listEntered.isCompleted) listEntered.complete();
          await listGate!.future;
        }
      }
      if (request.url.path.endsWith('/items/film')) detailReads++;
      if (request.url.path.endsWith('/info') && infoFailure) return http.Response('{}', 503);
      final response = await fake.handle(request);
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        if (request.url.path.endsWith('/info')) (body['capabilities'] as Map)['applied_external_identity'] = applied;
        void apply(Map<String, dynamic> item) {
          if (item['id'] == 'film' && includeApplied) item['applied_external_ids'] = appliedValue;
        }

        apply(body);
        for (final item in body['items'] as List? ?? const []) {
          if (item is Map<String, dynamic>) apply(item);
        }
      }
      return http.Response(jsonEncode(body), response.statusCode, headers: response.headers);
    }),
  );
}

class _HeldIdsServer extends FakeServer {
  _HeldIdsServer() : super('other');
  final entered = Completer<void>();
  final answer = Completer<ExternalIds>();
  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async {
    if (!entered.isCompleted) entered.complete();
    return answer.future;
  }
}
