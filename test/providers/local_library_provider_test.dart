import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/providers/local_library_provider.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/services/local_library/local_library_store.dart';
import 'package:pleya/services/local_library/local_library_sync.dart';
import 'package:pleya/utils/deletion_notifier.dart';
import '../services/local_library/local_library_store_test.dart' show library, film;
import '../services/local_library/local_library_sync_test.dart' show Client;

Future<void> until(LocalLibraryProvider provider, bool Function() condition) async {
  if (condition()) return;
  final complete = Completer<void>();
  void listener() {
    if (condition() && !complete.isCompleted) complete.complete();
  }

  provider.addListener(listener);
  try {
    await complete.future.timeout(const Duration(seconds: 5));
  } finally {
    provider.removeListener(listener);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late ChangeNotifier changes;
  late LocalLibraryProvider provider;
  late Client client;
  var wifi = false;
  var visible = true;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('pleya-local-provider-test-');
    changes = ChangeNotifier();
    wifi = false;
    visible = true;
    client = Client();
    provider = LocalLibraryProvider(
      profileId: 'a',
      directory: root,
      librariesForSync: () => [library],
      clientFor: (_) => client,
      mayReadServer: (_) => visible,
      mayReadLibrary: (_) => true,
      networkConnected: () => true,
      wifiConnected: () => wifi,
      changes: changes,
      availableBytes: () async => 1024 * 1024 * 1024,
      posterLoader: (_, _) async => Uint8List.fromList([1, 2, 3]),
    );
    await provider.ready;
  });
  tearDown(() async {
    if (!provider.isDisposed) provider.dispose();
    await provider.pendingStoreWrites;
    changes.dispose();
    await root.delete(recursive: true);
  });

  for (final boundary in ['provider', 'revoke', 'clear', 'profile']) {
    test('$boundary change rejects a late poster in the actual provider', () async {
      provider.dispose();
      wifi = true;
      // Keep the dependency signature stable before the late request: client
      // identity, rather than newly populated membership, must invalidate it.
      final seeded = LocalLibraryStore(root);
      await seeded.load();
      await seeded.saveLibrary(library, client.rows, complete: true);
      final entered = Completer<void>();
      final gate = Completer<LocalPosterResult>();
      var calls = 0;
      provider = LocalLibraryProvider(
        profileId: 'a',
        directory: root,
        librariesForSync: () => [library],
        clientFor: (_) => client,
        mayReadServer: (_) => visible,
        mayReadLibrary: (_) => true,
        networkConnected: () => true,
        wifiConnected: () => wifi,
        changes: changes,
        availableBytes: () async => 1024 * 1024 * 1024,
        posterRevalidator: (_, _, _) {
          calls++;
          if (!entered.isCompleted) entered.complete();
          return gate.future;
        },
      );
      await provider.ready;
      await provider.setEnabled(true);
      await entered.future;
      final oldClient = client;
      if (boundary == 'provider') {
        client = Client();
        changes.notifyListeners();
      }
      if (boundary == 'revoke') {
        visible = false;
        changes.notifyListeners();
      }
      if (boundary == 'clear') await provider.clear();
      if (boundary == 'profile') provider.dispose();
      gate.complete(LocalPosterResult(bytes: Uint8List.fromList([99]), variant: 'v', etag: 'late'));
      if (boundary != 'profile') await until(provider, () => provider.state != LocalLibraryState.syncing);
      // Wait for the disposed sync's guarded completion as well.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(provider.posterPath('one', '/shared-poster'), isNull);
      final check = LocalLibraryStore(root);
      await check.load();
      expect(check.posterFreshness('one', '/shared-poster')['validated'], isNull);
      expect(check.posterPath('one', '/shared-poster'), isNull);
      expect(calls, 1);
      if (boundary == 'provider') expect(identical(client, oldClient), isFalse);
    });
  }

  for (final count in [450, 5000]) {
    test('query LRU holds eight keys and recomputes evicted offline results for $count items', () async {
      provider.dispose();
      final store = LocalLibraryStore(root);
      await store.load();
      await store.saveLibrary(
        library,
        List.generate(count, (i) => film('film-${i.toString().padLeft(4, '0')}')),
        complete: true,
      );
      provider = LocalLibraryProvider(
        profileId: 'a',
        directory: root,
        librariesForSync: () => [library],
        clientFor: (_) => client,
        mayReadServer: (_) => visible,
        mayReadLibrary: (_) => true,
        networkConnected: () => false,
        wifiConnected: () => false,
        changes: changes,
      );
      await provider.ready;
      // Both prefetch settings must permit complete local reads while offline.
      for (final enabled in [false, true]) {
        await provider.setEnabled(enabled);
        const all = LibraryQuery(limit: 10000);
        final original = provider.page(library.globalKey, all)!;
        final originalIds = original.items.map((item) => item.id).toList();
        expect(originalIds, hasLength(count));
        for (var i = 0; i < 7; i++) {
          provider.page(library.globalKey, LibraryQuery(search: '$i'));
        }
        expect(provider.cachedQueryKeys, hasLength(8));
        // Pagination shares a key and a hit promotes it past the oldest filter.
        final laterPage = provider.page(library.globalKey, all.copyWith(offset: count - 20, limit: 20))!;
        expect(laterPage.items.map((item) => item.id), originalIds.skip(count - 20));
        provider.page(library.globalKey, const LibraryQuery(search: '7'));
        expect(provider.cachedQueryKeys, hasLength(8));
        expect(provider.cachedQueryKeys.any((key) => key.query.search == null), isTrue);
        expect(provider.cachedQueryKeys.any((key) => key.query.search == '0'), isFalse);
        for (var i = 8; i < 16; i++) {
          provider.page(library.globalKey, LibraryQuery(search: '$i'));
          expect(provider.cachedQueryKeys, hasLength(8));
        }
        expect(provider.cachedQueryKeys.any((key) => key.query.search == null), isFalse);
        final recomputed = provider.page(library.globalKey, all)!;
        expect(recomputed.totalCount, count);
        expect(recomputed.items.map((item) => item.id), originalIds);
        expect(original.items.map((item) => item.id), originalIds, reason: 'eviction preserves held page references');
        expect(provider.cachedQueryKeys, hasLength(8));
        expect(client.entered.isCompleted, isFalse, reason: 'offline paging never requests provider metadata');
        expect(client.idLookups, 0);
        // Unsupported local queries do not consume the result budget.
        expect(provider.page(library.globalKey, const LibraryQuery(favoritesOnly: true)), isNull);
        expect(provider.cachedQueryKeys, hasLength(8));
        await provider.clear();
        expect(provider.cachedQueryKeys, isEmpty);
        expect(provider.page(library.globalKey, all), isNull);
        if (!enabled) {
          // Reopen the same complete fixture for the enabled/offline case.
          provider.dispose();
          await store.saveLibrary(
            library,
            List.generate(count, (i) => film('film-${i.toString().padLeft(4, '0')}')),
            complete: true,
          );
          provider = LocalLibraryProvider(
            profileId: 'a',
            directory: root,
            librariesForSync: () => [library],
            clientFor: (_) => client,
            mayReadServer: (_) => visible,
            mayReadLibrary: (_) => true,
            networkConnected: () => false,
            wifiConnected: () => false,
            changes: changes,
          );
          await provider.ready;
        }
      }
    });
  }

  test('known authentication rejection persists until an authoritative successful bind', () async {
    provider.dispose();
    final store = LocalLibraryStore(root);
    await store.load();
    await store.saveLibrary(library, [film('a')], complete: true);
    var access = <String, bool>{'one': false};
    LocalLibraryProvider create() => LocalLibraryProvider(
      profileId: 'a',
      directory: root,
      librariesForSync: () => [],
      clientFor: (_) => null,
      mayReadServer: (_) => true,
      mayReadLibrary: (_) => true,
      authoritativeServerAccess: () => access,
      networkConnected: () => false,
      wifiConnected: () => false,
      changes: changes,
    );
    provider = create();
    await provider.ready;
    expect(provider.items, isEmpty);
    provider.dispose();
    access = {};
    provider = create();
    await provider.ready;
    expect(provider.items, isEmpty);
    access = {'one': true};
    changes.notifyListeners();
    expect(provider.items, hasLength(1));
    await provider.setEnabled(false);
  });

  test('authoritative library revocation survives offline and cold restart', () async {
    provider.dispose();
    final store = LocalLibraryStore(root);
    await store.load();
    await store.saveLibrary(library, [film('a')], complete: true);
    var access = <String, Set<String>>{
      'one': {library.globalKey},
    };
    LocalLibraryProvider create() => LocalLibraryProvider(
      profileId: 'a',
      directory: root,
      librariesForSync: () => [],
      clientFor: (_) => null,
      mayReadServer: (_) => true,
      mayReadLibrary: (_) => true,
      authoritativeLibraries: () => access,
      networkConnected: () => false,
      wifiConnected: () => false,
      changes: changes,
    );
    provider = create();
    await provider.ready;
    expect(provider.items, hasLength(1));
    access = {'one': {}};
    changes.notifyListeners();
    expect(provider.items, isEmpty);
    // Drains serialized access persistence before simulating process restart.
    await provider.setEnabled(false);
    provider.dispose();
    access = {};
    provider = create();
    await provider.ready;
    expect(provider.items, isEmpty);
    expect(provider.posterPath('one', '/shared-poster'), isNull);
    expect(provider.page(library.globalKey, const LibraryQuery()), isNull);
  });

  test(
    'stored external ids: a Pleya Server snapshot with none sends the caller to the server, a proven one is used',
    () async {
      provider.dispose();
      final store = LocalLibraryStore(root);
      await store.load();
      MediaItem pleya(String id, Map<String, Object?> ids, {bool final_ = true}) => MediaItem(
        id: id,
        backend: MediaBackend.pleyaServer,
        kind: MediaKind.movie,
        title: id,
        serverId: 'one',
        libraryId: 'films',
        raw: {
          'pleyaLocalExternalIds': ids,
          'pleyaLocalExternalIdsFinal': final_,
          'pleyaExternalIdsSource': final_ ? 'applied' : 'unknown',
          if (final_) 'pleyaExternalIds': ids,
        },
      );
      await store.saveLibrary(library, [
        pleya('proven', {'tmdb': 5}),
        pleya('empty', {}),
        pleya('legacy-empty', {}, final_: false),
        MediaItem(
          id: 'nokey',
          backend: MediaBackend.pleyaServer,
          kind: MediaKind.movie,
          title: 'n',
          serverId: 'one',
          libraryId: 'films',
        ),
        film('plex-empty').copyWith(raw: {'pleyaLocalExternalIds': <String, Object?>{}}),
      ], complete: true);
      provider = LocalLibraryProvider(
        profileId: 'a',
        directory: root,
        librariesForSync: () => [],
        clientFor: (_) => null,
        mayReadServer: (_) => true,
        mayReadLibrary: (_) => true,
        networkConnected: () => false,
        wifiConnected: () => false,
        changes: changes,
      );
      await provider.ready;

      expect(provider.externalIds('one', 'proven')?.tmdb, 5);
      expect(
        provider.externalIds('one', 'empty'),
        const ExternalIds(),
        reason: 'a final empty answer is kept: no network per screen',
      );
      expect(provider.externalIds('one', 'legacy-empty'), isNull, reason: 'not proof of nothing: ask the server');
      expect(
        provider.externalIds('one', 'plex-empty'),
        isNotNull,
        reason: 'Plex and Jellyfin keep their stored answer',
      );
      expect(provider.externalIds('one', 'unknown'), isNull);
      // Rights: a library the profile may no longer read gives nothing, also no numbers.
      provider.dispose();
      provider = LocalLibraryProvider(
        profileId: 'a',
        directory: root,
        librariesForSync: () => [],
        clientFor: (_) => null,
        mayReadServer: (_) => true,
        mayReadLibrary: (_) => false,
        networkConnected: () => false,
        wifiConnected: () => false,
        changes: changes,
      );
      await provider.ready;
      expect(provider.externalIds('one', 'proven'), isNull, reason: 'withdrawn library: no cached identity leaks');
      await provider.setEnabled(false);
    },
  );

  test('prefetch waits for wifi unless mobile data was explicitly enabled', () async {
    await provider.setEnabled(true);
    expect(provider.state, LocalLibraryState.wifi);
    expect(provider.items, isEmpty);
    await provider.setWifiOnly(false);
    await until(provider, () => provider.state == LocalLibraryState.ready);
    expect(provider.items.map((i) => i.id), ['a', 'b']);
    expect(provider.posterPath('one', '/shared-poster'), isNotNull);
    final page = provider.page('one:films', const LibraryQuery(kind: MediaKind.movie, limit: 10));
    expect(page?.totalCount, 2);
  });

  test('revoked visibility immediately hides cached metadata and posters', () async {
    wifi = true;
    await provider.setEnabled(true);
    await until(provider, () => provider.state == LocalLibraryState.ready);
    expect(provider.page(library.globalKey, const LibraryQuery())?.totalCount, 2);
    visible = false;
    changes.notifyListeners();
    expect(provider.cachedQueryKeys, isEmpty);
    expect(provider.items, isEmpty);
    expect(provider.posterPath('one', '/shared-poster'), isNull);
    expect(provider.page('one:films', const LibraryQuery()), isNull);
  });

  test('confirmed source deletion also cleans local data with prefetch disabled', () async {
    wifi = true;
    await provider.setEnabled(true);
    await until(provider, () => provider.state == LocalLibraryState.ready);
    await provider.setEnabled(false);
    final revision = provider.revision;
    DeletionNotifier().notifyDeletedItem(item: film('a'));
    await until(provider, () => provider.revision > revision && provider.libraries.isNotEmpty);
    expect(provider.items.map((i) => i.id), ['b']);
    expect(provider.posterPath('one', '/shared-poster'), isNotNull);
    final after = provider.revision;
    DeletionNotifier().notifyDeletedItem(item: film('b'));
    await until(provider, () => provider.revision > after && provider.libraries.isNotEmpty);
    expect(provider.items, isEmpty);
    expect(provider.posterPath('one', '/shared-poster'), isNull);
  });

  test('cached sources stay separate across mixed servers when one copy is deleted', () async {
    final store = LocalLibraryStore(Directory('${root.path}/other-profile'));
    await store.load();
    final otherLibrary = library.copyWith(serverId: 'two', backend: MediaBackend.jellyfin);
    await store.saveLibrary(library, [film('same')], complete: true);
    await store.saveLibrary(otherLibrary, [
      MediaItem(
        id: 'same',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.movie,
        title: 'same',
        serverId: 'two',
        libraryId: 'films',
      ),
    ], complete: true);
    await store.removeConfirmed('one', 'same');
    expect(store.items.single.serverId, 'two');
  });

  test('clear retracts local reads before disk persistence completes', () async {
    wifi = true;
    await provider.setEnabled(true);
    await until(provider, () => provider.state == LocalLibraryState.ready);
    provider.page(library.globalKey, const LibraryQuery());
    final clear = provider.clear();
    expect(provider.cachedQueryKeys, isEmpty);
    addTearDown(() => clear);
    expect(provider.items, isEmpty);
    expect(provider.item('one', 'a'), isNull);
    expect(provider.posterPath('one', '/shared-poster'), isNull);
    expect(provider.page(library.globalKey, const LibraryQuery()), isNull);
    await clear;
    expect(provider.items, isEmpty);
  });

  test('confirmed deletion retracts local reads when the event is delivered', () async {
    wifi = true;
    await provider.setEnabled(true);
    await until(provider, () => provider.state == LocalLibraryState.ready);
    await provider.setEnabled(false);
    final delivered = DeletionNotifier().stream.first;
    addTearDown(() => provider.setEnabled(false));
    final before = provider.revision;
    DeletionNotifier().notifyDeletedItem(item: film('a'));
    await delivered;
    expect(provider.item('one', 'a'), isNull);
    expect(provider.page(library.globalKey, const LibraryQuery())?.items.map((i) => i.id), isNot(contains('a')));
    await until(provider, () => provider.revision > before && provider.items.any((i) => i.id == 'b'));
  });

  test('content sync and network changes keep the read boundary; access loss advances it', () async {
    wifi = true;
    await provider.setEnabled(true);
    await until(provider, () => provider.state == LocalLibraryState.ready);
    final boundary = provider.readBoundaryRevision;
    final revision = provider.revision;
    expect(provider.page(library.globalKey, const LibraryQuery())?.totalCount, 2);
    client.rows = [film('a'), film('b'), film('c')];
    // A library scanned moments ago is not walked again by a periodic trigger.
    await provider.synchronize();
    expect(provider.items.map((item) => item.id), ['a', 'b']);
    await provider.synchronize(force: true);
    expect(provider.cachedQueryKeys, isEmpty);
    expect(provider.page(library.globalKey, const LibraryQuery())?.totalCount, 3);
    expect(provider.items.map((item) => item.id), ['a', 'b', 'c']);
    expect(provider.revision, greaterThan(revision));
    expect(provider.readBoundaryRevision, boundary);
    wifi = false;
    changes.notifyListeners();
    expect(provider.readBoundaryRevision, boundary);
    visible = false;
    changes.notifyListeners();
    expect(provider.readBoundaryRevision, greaterThan(boundary));
    expect(provider.items, isEmpty);
  });

  group('rescan window', () {
    late DateTime now;
    late List<MediaLibrary> libraries;
    const second = MediaLibrary(
      id: 'films-2',
      backend: MediaBackend.plex,
      title: 'Films 2',
      kind: MediaKind.movie,
      serverId: 'one',
    );

    Future<void> open() async {
      provider.dispose();
      now = DateTime.now();
      libraries = [library];
      wifi = true;
      provider = LocalLibraryProvider(
        profileId: 'a',
        directory: root,
        librariesForSync: () => libraries,
        clientFor: (_) => client,
        mayReadServer: (_) => true,
        mayReadLibrary: (_) => true,
        networkConnected: () => true,
        wifiConnected: () => wifi,
        changes: changes,
        availableBytes: () async => 1024 * 1024 * 1024,
        posterLoader: (_, _) async => Uint8List.fromList([1, 2, 3]),
        clock: () => now,
      );
      await provider.ready;
      await provider.setEnabled(true);
      await until(provider, () => provider.state == LocalLibraryState.ready);
      // The store stamps the completion with the real clock.
      now = DateTime.now();
      expect(provider.page(library.globalKey, const LibraryQuery())?.totalCount, 2);
      client.rows = [film('a'), film('b'), film('c')];
    }

    int? total(MediaLibrary l) => provider.page(l.globalKey, const LibraryQuery())?.totalCount;

    test('an unchanged library is scanned again once the window has passed', () async {
      await open();
      now = now.add(LocalLibraryProvider.unchangedRescanAfter - const Duration(minutes: 1));
      await provider.synchronize();
      expect(total(library), 2);

      now = now.add(const Duration(minutes: 2));
      await provider.synchronize();
      expect(total(library), 3);
    });

    test('a library whose server updatedAt moved is scanned again inside the window', () async {
      await open();
      libraries = [library.copyWith(updatedAt: 1000)];
      changes.notifyListeners();
      await until(provider, () => total(library) == 3);
    });

    test('the updatedAt of the last complete scan survives a restart', () async {
      libraries = [library.copyWith(updatedAt: 1000)];
      final seeded = LocalLibraryStore(root);
      await seeded.load();
      await seeded.saveLibrary(libraries.single, client.rows, complete: true);
      final reopened = LocalLibraryStore(root);
      await reopened.load();
      expect(reopened.completedUpdatedAt(library.globalKey), 1000);
    });

    test('a newly eligible library is scanned while a recently scanned one is skipped', () async {
      await open();
      libraries = [library, second];
      await provider.synchronize();
      expect(total(second), 3);
      expect(total(library), 2);
    });

    test('a forced sync cut off by a dependency change stays forced in the follow-up', () async {
      await open();
      final blocked = Client()
        ..rows = [film('a'), film('b'), film('c')]
        ..gate = Completer<void>();
      client = blocked;
      final run = provider.synchronize(force: true);
      await blocked.entered.future;
      client = Client()..rows = [film('a'), film('b'), film('c')];
      changes.notifyListeners(); // a new client identity: a new generation
      blocked.gate!.complete();
      await run;
      await until(provider, () => total(library) == 3);
    });

    test('a tap on sync now while the library is off does not spin', () async {
      await open();
      await provider.setEnabled(false);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      var notifications = 0;
      void count() => notifications++;
      provider.addListener(count);
      addTearDown(() => provider.removeListener(count));
      await provider.synchronize(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(provider.state, LocalLibraryState.disabled);
      expect(notifications, lessThan(5), reason: 'no sync that reschedules itself');
    });

    test('a tap on sync now while another sync runs is not dropped', () async {
      await open();
      client = Client()
        ..rows = [film('a'), film('b'), film('c')]
        ..gate = Completer<void>();
      libraries = [library, second];
      // Skips the recent library, then waits on the new one.
      final run = provider.synchronize();
      await client.entered.future;
      await provider.synchronize(force: true);
      client.gate!.complete();
      await run;
      await until(provider, () => total(library) == 3);
    });
  });
}
