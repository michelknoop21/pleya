/// Covers `unified_catalog_provider.dart`'s reactive lifecycle around the
/// headless `UnifiedCatalogService` (hoofdstuk 12 and 27 fase 3 of
/// docs/tvos-unified-experience.md): lazy start, loading-state bracketing,
/// and reacting to a library-set change without doing any work before a
/// consumer has opted in.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/unified_catalog_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/media_server_http_client.dart';

import '../test_helpers/prefs.dart';

/// Serves a fixed, already-sorted item list per library and counts fetches,
/// so "no work before ensureStarted" is measured rather than assumed.
class _FakeLibraryClient implements MediaServerClient {
  _FakeLibraryClient(this.id, {this.itemsByLibrary = const {}});

  final String id;
  final Map<String, List<MediaItem>> itemsByLibrary;
  int fetchCalls = 0;

  @override
  ServerId get serverId => ServerId(id);

  @override
  String? get serverName => id;

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  /// `MultiServerManager.removeServer` closes the client it drops (A16), and
  /// a `noSuchMethod` fallthrough throws rather than returning a Future.
  @override
  void close() {}

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    fetchCalls++;
    lastAbortController = abort;
    final wait = gate;
    if (wait != null) await wait.future;
    final all = itemsByLibrary[libraryId] ?? const <MediaItem>[];
    final end = (query.offset + query.limit).clamp(0, all.length);
    final slice = query.offset >= all.length ? const <MediaItem>[] : all.sublist(query.offset, end);
    return LibraryPage<MediaItem>(items: slice, totalCount: all.length, offset: query.offset);
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  /// Set to make [fetchItem] return a specific item, for I19's refresh test.
  MediaItem? Function(String id)? fetchItemResult;

  @override
  Future<MediaItem?> fetchItem(String id) async => fetchItemResult?.call(id);

  /// E12: gates the *next* [fetchLibraryPagedContent] call so a test can
  /// dispose the provider while a request is still outstanding.
  Completer<void>? gate;
  AbortController? lastAbortController;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _movie(String id, {required String title, required String serverId}) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: title, serverId: serverId);

MediaLibrary _library(String id, {required String serverId, bool hidden = false}) => MediaLibrary(
  id: id,
  backend: MediaBackend.plex,
  title: id,
  kind: MediaKind.movie,
  serverId: serverId,
  serverName: serverId,
  hidden: hidden,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeLibraryClient client;
  late MultiServerManager manager;
  late MultiServerProvider multiServer;
  late HiddenLibrariesProvider hiddenLibraries;
  late LibrariesProvider libraries;
  late UnifiedCatalogProvider provider;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();

    client = _FakeLibraryClient(
      's1',
      itemsByLibrary: {
        'A': [_movie('a1', title: 'Alien', serverId: 's1'), _movie('a2', title: 'Dune', serverId: 's1')],
      },
    );
    manager = MultiServerManager()..debugRegisterClientForTesting(client);
    multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    hiddenLibraries = HiddenLibrariesProvider();
    libraries = LibrariesProvider()..debugSetLibraries([_library('A', serverId: 's1')]);
    provider = UnifiedCatalogProvider(
      multiServer: multiServer,
      libraries: libraries,
      hiddenLibraries: hiddenLibraries,
      kind: MediaKind.movie,
    );
  });

  tearDown(() {
    provider.dispose();
    libraries.dispose();
    hiddenLibraries.dispose();
    multiServer.dispose();
  });

  test('construction starts no load — no fetch until ensureStarted', () async {
    expect(provider.hasStarted, isFalse);
    expect(provider.isInitialLoading, isFalse);
    expect(client.fetchCalls, 0);

    // Give any accidentally-scheduled microtask a chance to run.
    await pumpEventQueue();
    expect(client.fetchCalls, 0);
  });

  test('ensureStarted loads the first page and settles into the snapshot', () async {
    await provider.ensureStarted();

    expect(provider.hasStarted, isTrue);
    expect(provider.isInitialLoading, isFalse);
    expect(provider.snapshot.groups.map((g) => g.representativeSource.item.title), ['Alien', 'Dune']);
    expect(client.fetchCalls, 1);
  });

  test('ensureStarted is a no-op once already started', () async {
    await provider.ensureStarted();
    expect(client.fetchCalls, 1);

    await provider.ensureStarted();
    expect(client.fetchCalls, 1);
  });

  test('isInitialLoading brackets ensureStarted and notifies on both edges', () async {
    final transitions = <bool>[];
    provider.addListener(() {
      if (transitions.isEmpty || transitions.last != provider.isInitialLoading) {
        transitions.add(provider.isInitialLoading);
      }
    });

    final pass = provider.ensureStarted();
    expect(provider.isInitialLoading, isTrue);
    await pass;
    expect(provider.isInitialLoading, isFalse);
    expect(transitions, [true, false]);
  });

  test('loadMore starts the merge if never started, otherwise brackets isLoadingMore', () async {
    await provider.loadMore();
    expect(provider.hasStarted, isTrue);
    expect(client.fetchCalls, 1);

    final transitions = <bool>[];
    provider.addListener(() {
      if (transitions.isEmpty || transitions.last != provider.isLoadingMore) transitions.add(provider.isLoadingMore);
    });
    await provider.loadMore();
    expect(transitions, [true, false]);
  });

  test('a hidden-library change before ensureStarted does no work', () async {
    await hiddenLibraries.hideLibrary(_library('A', serverId: 's1').globalKey);
    await pumpEventQueue();

    expect(provider.hasStarted, isFalse);
    expect(client.fetchCalls, 0);
  });

  test('a hidden-library change after starting reconciles and reloads with the library excluded', () async {
    await provider.ensureStarted();
    expect(provider.snapshot.groups, hasLength(2));

    await hiddenLibraries.hideLibrary(_library('A', serverId: 's1').globalKey);
    await pumpEventQueue();

    // The only library is now hidden, so there is nothing left to fetch —
    // the reconciliation itself is what emptied the snapshot, not a fetch.
    expect(provider.snapshot.groups, isEmpty);
  });

  test('server.hidden excludes a library from the merge, matching eligibleCatalogLibraries', () async {
    libraries.debugSetLibraries([_library('A', serverId: 's1', hidden: true)]);
    final hiddenProvider = UnifiedCatalogProvider(
      multiServer: multiServer,
      libraries: libraries,
      hiddenLibraries: hiddenLibraries,
      kind: MediaKind.movie,
    );
    addTearDown(hiddenProvider.dispose);

    await hiddenProvider.ensureStarted();

    expect(hiddenProvider.snapshot.groups, isEmpty);
    expect(client.fetchCalls, 0);
  });

  test('a late server coming online reconciles the eligible library set', () async {
    await provider.ensureStarted();
    final callsAfterStart = client.fetchCalls;

    final client2 = _FakeLibraryClient(
      's2',
      itemsByLibrary: {
        'B': [_movie('b1', title: 'Silo', serverId: 's2')],
      },
    );
    manager.debugRegisterClientForTesting(client2);
    libraries.debugSetLibraries([_library('A', serverId: 's1'), _library('B', serverId: 's2')]);
    await pumpEventQueue();

    expect(client.fetchCalls, greaterThan(callsAfterStart));
    expect(
      provider.snapshot.groups.map((g) => g.representativeSource.item.title),
      containsAll(['Alien', 'Dune', 'Silo']),
    );
  });

  test('B10: a library deleted server-side reconciles the same way a hidden one does', () async {
    client.itemsByLibrary['C'] = [_movie('c1', title: 'Foundation', serverId: 's1')];
    libraries.debugSetLibraries([_library('A', serverId: 's1'), _library('C', serverId: 's1')]);
    final twoLibraryProvider = UnifiedCatalogProvider(
      multiServer: multiServer,
      libraries: libraries,
      hiddenLibraries: hiddenLibraries,
      kind: MediaKind.movie,
    );
    addTearDown(twoLibraryProvider.dispose);

    await twoLibraryProvider.ensureStarted();
    expect(
      twoLibraryProvider.snapshot.groups.map((g) => g.representativeSource.item.title),
      containsAll(['Alien', 'Dune', 'Foundation']),
    );

    // The server removed library C entirely — LibrariesProvider now reports
    // only A, the same shape a hidden-library change produces, but from
    // deletion rather than a user toggle.
    libraries.debugSetLibraries([_library('A', serverId: 's1')]);
    await pumpEventQueue();

    expect(
      twoLibraryProvider.snapshot.groups.map((g) => g.representativeSource.item.title),
      isNot(contains('Foundation')),
    );
    expect(
      twoLibraryProvider.snapshot.groups.map((g) => g.representativeSource.item.title),
      containsAll(['Alien', 'Dune']),
    );
  });

  test('A16: a server removed from the profile takes its titles with it', () async {
    final client2 = _FakeLibraryClient(
      's2',
      itemsByLibrary: {
        'B': [_movie('b1', title: 'Silo', serverId: 's2')],
      },
    );
    manager.debugRegisterClientForTesting(client2);
    libraries.debugSetLibraries([_library('A', serverId: 's1'), _library('B', serverId: 's2')]);

    await provider.ensureStarted();
    expect(
      provider.snapshot.groups.map((g) => g.representativeSource.item.title),
      containsAll(['Alien', 'Dune', 'Silo']),
    );

    // The whole server left, not just one of its libraries: the runtime drops
    // the client and the profile's library list loses everything it carried.
    manager.removeServer(ServerId('s2'));
    libraries.debugSetLibraries([_library('A', serverId: 's1')]);
    await pumpEventQueue();

    expect(
      provider.snapshot.groups.map((g) => g.representativeSource.item.title),
      isNot(contains('Silo')),
      reason: 'a removed server keeps nothing on the wall',
    );
    expect(
      provider.snapshot.groups.map((g) => g.representativeSource.item.title),
      containsAll(['Alien', 'Dune']),
      reason: 'and takes nothing of the healthy server with it',
    );
  });

  group('E12: dispose cancels a request still in flight (hoofdstuk 22)', () {
    // A separate scoped provider in every test here, exactly like the
    // existing "dispose removes dependency listeners" test below — the
    // shared `tearDown` above always disposes `provider` once for every
    // test in this file, so a test that means to dispose *and inspect* the
    // effects needs its own instance to avoid double-disposing the shared
    // one (Flutter's ChangeNotifier asserts on that in debug mode).
    test('a fetch outstanding at dispose is aborted', () async {
      final scoped = UnifiedCatalogProvider(
        multiServer: multiServer,
        libraries: libraries,
        hiddenLibraries: hiddenLibraries,
        kind: MediaKind.movie,
      );
      client.gate = Completer<void>();
      final pending = scoped.ensureStarted();
      // Let the fetch actually start (past the async SourcePreferenceStore
      // read `_restart` does before touching the service) and hit the gate,
      // before disposing while it is genuinely in flight.
      while (client.fetchCalls == 0) {
        await Future<void>.delayed(Duration.zero);
      }

      scoped.dispose();

      expect(client.lastAbortController?.isAborted, isTrue);
      client.gate!.complete();
      await pending;
    });

    test('disposing with nothing in flight is harmless', () async {
      final scoped = UnifiedCatalogProvider(
        multiServer: multiServer,
        libraries: libraries,
        hiddenLibraries: hiddenLibraries,
        kind: MediaKind.movie,
      );
      await scoped.ensureStarted();

      expect(scoped.dispose, returnsNormally);
    });
  });

  group('I19: refreshItem re-reads one source in place', () {
    test('a fresh fetch updates the group without re-paging', () async {
      await provider.ensureStarted();
      final before = provider.snapshot.groups.singleWhere(
        (g) => g.groupId.contains('a1') || g.sources.any((s) => s.item.id == 'a1'),
      );
      expect(before.watchState.hasActiveProgress, isFalse);

      client.fetchItemResult = (id) => _movie(
        'a1',
        title: 'Alien',
        serverId: 's1',
      ).copyWith(viewOffsetMs: 60000, durationMs: 6000000, lastViewedAt: 1756000000);
      final fetchCallsBefore = client.fetchCalls;

      final applied = await provider.refreshItem('s1:a1', () => client.fetchItem('a1'));

      expect(applied, isTrue);
      expect(
        client.fetchCalls,
        fetchCallsBefore,
        reason: 'the fetch itself is the caller\'s job, not a second page load',
      );
      final after = provider.snapshot.groups.singleWhere((g) => g.sources.any((s) => s.item.id == 'a1'));
      expect(after.watchState.hasActiveProgress, isTrue);
      expect(after.sources.singleWhere((s) => s.item.id == 'a1').item.viewOffsetMs, 60000);
    });

    test('an item this merge never popped changes nothing and reports false', () async {
      await provider.ensureStarted();

      final applied = await provider.refreshItem(
        's1:not-in-this-merge',
        () async => _movie('not-in-this-merge', title: 'Elsewhere', serverId: 's1'),
      );

      expect(applied, isFalse);
    });

    test('a null fetch result is a no-op', () async {
      await provider.ensureStarted();

      final applied = await provider.refreshItem('s1:a1', () async => null);

      expect(applied, isFalse);
    });

    test('before ensureStarted there is no merge to update, so it is a no-op', () async {
      final applied = await provider.refreshItem('s1:a1', () async => _movie('a1', title: 'Alien', serverId: 's1'));

      expect(applied, isFalse);
    });

    test('notifies listeners exactly when the update actually lands', () async {
      await provider.ensureStarted();
      var notifications = 0;
      provider.addListener(() => notifications++);

      final noop = await provider.refreshItem('s1:absent', () async => null);
      expect(noop, isFalse);
      expect(notifications, 0);

      final applied = await provider.refreshItem(
        's1:a1',
        () async => _movie('a1', title: 'Alien', serverId: 's1').copyWith(viewOffsetMs: 1000, durationMs: 6000000),
      );
      expect(applied, isTrue);
      expect(notifications, 1);
    });
  });

  test('dispose removes dependency listeners — no reconciliation after teardown', () async {
    final scoped = UnifiedCatalogProvider(
      multiServer: multiServer,
      libraries: libraries,
      hiddenLibraries: hiddenLibraries,
      kind: MediaKind.movie,
    );
    await scoped.ensureStarted();
    scoped.dispose();

    // Must not throw and must not trigger a reconciliation on a disposed
    // notifier (which would assert in debug mode).
    await hiddenLibraries.hideLibrary(_library('A', serverId: 's1').globalKey);
    await pumpEventQueue();
  });
}
