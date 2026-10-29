import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/providers/local_library_provider.dart';
import 'package:pleya/services/local_library/local_library_store.dart';
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
  var wifi = false;
  var visible = true;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('pleya-local-provider-test-');
    changes = ChangeNotifier();
    wifi = false;
    visible = true;
    provider = LocalLibraryProvider(
      profileId: 'a',
      directory: root,
      librariesForSync: () => [library],
      clientFor: (_) => Client(),
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
    provider.dispose();
    changes.dispose();
    await root.delete(recursive: true);
  });

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
      MediaItem pleya(String id, Map<String, Object?> ids) => MediaItem(
        id: id,
        backend: MediaBackend.pleyaServer,
        kind: MediaKind.movie,
        title: id,
        serverId: 'one',
        libraryId: 'films',
        raw: {'pleyaLocalExternalIds': ids},
      );
      await store.saveLibrary(library, [
        pleya('proven', {'tmdb': 5}),
        pleya('empty', {}),
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
      expect(provider.externalIds('one', 'empty'), isNull, reason: 'not proof of nothing: ask the server');
      expect(
        provider.externalIds('one', 'plex-empty'),
        isNotNull,
        reason: 'Plex and Jellyfin keep their stored answer',
      );
      expect(provider.externalIds('one', 'unknown'), isNull);
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
    visible = false;
    changes.notifyListeners();
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
    await until(provider, () => provider.revision > revision);
    expect(provider.items.map((i) => i.id), ['b']);
    expect(provider.posterPath('one', '/shared-poster'), isNotNull);
    final after = provider.revision;
    DeletionNotifier().notifyDeletedItem(item: film('b'));
    await until(provider, () => provider.revision > after);
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
}
