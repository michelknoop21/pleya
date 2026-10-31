/// Restarts that overlap. A library joining restarts the merge on the query it
/// had, and the screen then sets the query that fits the new set, so two
/// restarts run into each other in the ordinary case. Only the newest may load.
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
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/unified_catalog_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/media_server_http_client.dart';

import '../test_helpers/prefs.dart';

class _Client implements MediaServerClient {
  final fetched = <String>[];
  Duration idDelay = const Duration(milliseconds: 5);
  Completer<void>? pageGate;

  @override
  ServerId get serverId => ServerId('nas');

  @override
  String? get serverName => 'nas';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  void close() {}

  /// Every library holds the same 120 titles, so two of them collide on identity
  /// and the merge has to ask for external ids.
  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    fetched.add('$libraryId@${query.offset}');
    final gate = pageGate;
    if (gate != null) await gate.future;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final all = [
      for (var i = 0; i < 120; i++)
        MediaItem(
          id: '$libraryId$i',
          backend: MediaBackend.plex,
          kind: MediaKind.movie,
          title: 'T ${i.toString().padLeft(3, '0')}',
          year: 2000,
          serverId: 'nas',
          serverName: 'nas',
        ),
    ];
    final end = (query.offset + query.limit).clamp(0, all.length);
    return LibraryPage<MediaItem>(
      items: all.sublist(query.offset.clamp(0, all.length), end),
      totalCount: all.length,
      offset: query.offset,
    );
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async {
    await Future<void>.delayed(idDelay);
    return const ExternalIds();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaLibrary _library(String id) => MediaLibrary(
  id: id,
  backend: MediaBackend.plex,
  title: id,
  kind: MediaKind.movie,
  serverId: 'nas',
  serverName: 'nas',
);

const _up = UnifiedCatalogQuery(kind: MediaKind.movie);
const _down = UnifiedCatalogQuery(kind: MediaKind.movie, sortDirection: LibrarySortDirection.descending);

void main() {
  late _Client client;
  late LibrariesProvider libraries;
  late UnifiedCatalogProvider catalog;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    client = _Client();
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    libraries = LibrariesProvider()..debugSetLibraries([_library('a')]);
    catalog = UnifiedCatalogProvider(
      multiServer: multiServer,
      libraries: libraries,
      hiddenLibraries: HiddenLibrariesProvider(),
      kind: MediaKind.movie,
    );
    addTearDown(catalog.dispose);
    await catalog.ensureStarted();
  });

  /// What a screen does: answer the notification of a restart with the query
  /// that fits the new set.
  void reactWith(UnifiedCatalogQuery query) => catalog.addListener(() {
    if (catalog.query != query) unawaited(catalog.setQuery(query));
  });

  List<String?> titles() => [for (final g in catalog.snapshot.groups) g.representativeSource.item.title];

  Future<void> settle() async {
    final done = Completer<void>();
    void check() {
      if (!catalog.isInitialLoading && !done.isCompleted) done.complete();
    }

    catalog.addListener(check);
    await Future<void>.delayed(const Duration(milliseconds: 1));
    check();
    await done.future.timeout(const Duration(seconds: 5));
    catalog.removeListener(check);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  test('a library joining while the screen sets a new query: one load, on the new order', () async {
    await catalog.setQuery(_down);
    client.fetched.clear();
    reactWith(_up);

    libraries.debugSetLibraries([_library('a'), _library('b')]);
    await settle();

    expect(catalog.query, _up);
    expect(client.fetched.where((f) => f == 'a@0'), hasLength(1), reason: 'the overtaken restart loads nothing');
    expect(catalog.loadFailed, isFalse);
    expect(titles().first, 'T 000');
  });

  test('duplicate titles and slow external ids: never the error page', () async {
    client.idDelay = const Duration(milliseconds: 40);
    await catalog.setQuery(_down);
    final seen = <bool>[];
    catalog.addListener(() => seen.add(catalog.loadFailed));
    reactWith(_up);

    libraries.debugSetLibraries([_library('a'), _library('b')]);
    await settle();

    expect(seen, isNot(contains(true)));
    expect(catalog.loadFailed, isFalse);
    expect(titles().first, 'T 000');
    expect(titles(), [...titles()]..sort((a, b) => a!.compareTo(b!)), reason: 'each library in order, no gap');
  });

  test('an overtaken restart does not call the page loaded while the newest still loads', () async {
    final oldGate = Completer<void>();
    final newGate = Completer<void>();
    client.pageGate = oldGate;

    final old = catalog.setQuery(_down);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    client.pageGate = newGate;
    final newest = catalog.setQuery(_up);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    oldGate.complete();
    await old;
    expect(catalog.isInitialLoading, isTrue, reason: 'the newest restart has not answered yet');

    newGate.complete();
    client.pageGate = null;
    await newest;
    expect(catalog.isInitialLoading, isFalse);
    expect(catalog.query, _up);
    expect(titles().first, 'T 000');
  });

  test('the grid asking for more during a restart joins that round', () async {
    client.idDelay = const Duration(milliseconds: 20);
    libraries.debugSetLibraries([_library('a'), _library('b')]);
    await settle();

    final restart = catalog.refresh();
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await Future.wait([restart, catalog.loadMore()]);

    expect(catalog.loadFailed, isFalse);
    expect(titles().first, 'T 000');
    expect(titles(), [...titles()]..sort((a, b) => a!.compareTo(b!)));
  });
}
