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
import 'package:pleya/providers/local_library_provider.dart';
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
  Completer<void>? pageEntered;
  Completer<void>? gatedPageEntered;
  int? gatedOffset;
  bool failPages = false;
  List<MediaItem>? rows;

  @override
  ServerId get serverId => ServerId('nas');

  @override
  String? get serverName => 'nas';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  void close() {}

  /// Every library holds the same 120 titles, so two of them collide on identity
  /// and the merge has to ask for external ids. The order follows the query.
  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    fetched.add('$libraryId@${query.offset}');
    if (pageEntered?.isCompleted == false) pageEntered!.complete();
    final gate = pageGate;
    if (gate != null && (gatedOffset == null || query.offset >= gatedOffset!)) {
      if (gatedPageEntered?.isCompleted == false) gatedPageEntered!.complete();
      await gate.future;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (failPages) throw StateError('fixture offline');
    final ascending =
        rows ??
        [
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
    // Real servers sort: an overtaken restart on the other direction shows.
    final all = query.sort?.direction == LibrarySortDirection.descending ? ascending.reversed.toList() : ascending;
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

// A controlled dependency notification; the page work still uses the real merge.
class _LocalLibrary extends LocalLibraryProvider {
  _LocalLibrary()
    : super(
        profileId: null,
        librariesForSync: () => [],
        clientFor: (_) => null,
        mayReadServer: (_) => true,
        mayReadLibrary: (_) => true,
        networkConnected: () => false,
        wifiConnected: () => false,
        changes: LibrariesProvider(),
      );

  int boundary = 0;
  @override
  int get readBoundaryRevision => boundary;

  void publish({bool hard = false}) {
    revision++;
    if (hard) boundary++;
    notifyListeners();
  }
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
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Client client;
  late LibrariesProvider libraries;
  late UnifiedCatalogProvider catalog;
  late _LocalLibrary local;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    client = _Client();
    local = _LocalLibrary();
    await local.ready;
    addTearDown(local.dispose);
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    libraries = LibrariesProvider()..debugSetLibraries([_library('a')]);
    catalog = UnifiedCatalogProvider(
      multiServer: multiServer,
      libraries: libraries,
      hiddenLibraries: HiddenLibrariesProvider(),
      kind: MediaKind.movie,
      localLibrary: local,
    );
    addTearDown(() {
      if (!catalog.isDisposed) catalog.dispose();
    });
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
      if (!catalog.isInitialLoading && !catalog.isLoadingMore && !done.isCompleted) done.complete();
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
    expect(titles().first, 'T 119', reason: 'the fake follows the order');
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
    expect(titles().first, 'T 119', reason: 'the fake follows the order');
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

  test('unchanged background content refresh retains every loaded group while blocked', () async {
    await catalog.loadMore();
    final before = catalog.snapshot;
    final seen = <int>[];
    catalog.addListener(() => seen.add(catalog.snapshot.groups.length));
    final gate = Completer<void>();
    client.pageGate = gate;
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    client.pageEntered = Completer<void>();

    local.publish();
    await client.pageEntered!.future.timeout(const Duration(seconds: 2));
    expect(catalog.snapshot.groups, before.groups);
    expect(catalog.isInitialLoading, isFalse);
    final more = catalog.loadMore();
    expect(catalog.snapshot.groups, before.groups);
    gate.complete();
    await more;
    await settle();

    expect(catalog.snapshot.groups.map((g) => g.groupId), before.groups.map((g) => g.groupId));
    expect(seen, everyElement(greaterThanOrEqualTo(before.groups.length)));
  });

  test('failed background refresh retains authorized groups without automatic retry', () async {
    final before = catalog.snapshot;
    client.fetched.clear();
    client.failPages = true;
    local.publish();
    await settle();
    expect(catalog.snapshot.groups, before.groups);
    expect(client.fetched, ['a@0']);
    expect(catalog.snapshot.totalGroupCount, isNull);
  });

  test('background append keeps visible group positions until explicit refresh', () async {
    final before = titles();
    client.rows = [
      MediaItem(
        id: 'new',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'A new title',
        year: 2000,
        serverId: 'nas',
      ),
      for (var i = 0; i < 120; i++)
        MediaItem(
          id: 'a$i',
          backend: MediaBackend.plex,
          kind: MediaKind.movie,
          title: 'T ${i.toString().padLeft(3, '0')}',
          year: 2000,
          serverId: 'nas',
        ),
    ];
    local.publish();
    await settle();
    expect(titles().take(before.length), before);
    await catalog.loadMore();
    expect(titles().take(before.length), before);
    await catalog.refresh();
    expect(titles().first, 'A new title', reason: 'explicit refresh is the sanctioned reorder');
  });

  for (final boundary in [
    'query',
    'source filter',
    'revoke with equal library keys',
    'clear',
    'confirmed delete',
    'profile switch',
  ]) {
    test('$boundary retracts immediately and rejects late page/item completion', () async {
      final item = catalog.snapshot.groups.first.representativeSource.item;
      final itemGate = Completer<MediaItem?>();
      addTearDown(() {
        if (!itemGate.isCompleted) itemGate.complete(null);
      });
      final pendingItem = catalog.refreshItem(item.globalKey, () => itemGate.future);
      final gate = Completer<void>();
      client.pageGate = gate;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      client.pageEntered = Completer<void>();
      local.publish();
      await client.pageEntered!.future.timeout(const Duration(seconds: 2));
      final pendingMore = catalog.loadMore();
      if (boundary == 'query') {
        unawaited(catalog.setQuery(_down));
      } else if (boundary == 'source filter') {
        unawaited(catalog.setQuery(_up, librarySelector: (_) => false));
      } else if (boundary == 'profile switch') {
        catalog.dispose();
      } else {
        local.publish(hard: true);
      }
      expect(catalog.snapshot.groups, isEmpty, reason: 'hard boundaries never retain the old viewport');
      gate.complete();
      await pendingMore;
      if (!catalog.isDisposed) await settle();
      itemGate.complete(item.copyWith(title: 'late unauthorized item'));
      expect(await pendingItem, isFalse);
      expect(titles(), isNot(contains('late unauthorized item')));
      if (boundary == 'profile switch' || boundary == 'source filter') {
        expect(catalog.snapshot.groups, isEmpty);
      }
    });
  }

  test('sort metadata changes update the card without moving its session key', () async {
    final first = catalog.snapshot.groups.first;
    client.rows = [
      for (var i = 1; i <= 5; i++)
        MediaItem(
          id: 'a$i',
          backend: MediaBackend.plex,
          kind: MediaKind.movie,
          title: 'T ${i.toString().padLeft(3, '0')}',
          year: 2000,
          serverId: 'nas',
        ),
      first.representativeSource.item.copyWith(title: 'T 005z'),
      for (var i = 6; i < 120; i++)
        MediaItem(
          id: 'a$i',
          backend: MediaBackend.plex,
          kind: MediaKind.movie,
          title: 'T ${i.toString().padLeft(3, '0')}',
          year: 2000,
          serverId: 'nas',
        ),
    ];
    local.publish();
    await settle();
    expect(catalog.snapshot.groups.first.groupId, first.groupId);
    expect(catalog.snapshot.groups.first.representativeSource.item.title, 'T 005z');
    await catalog.refresh();
    expect(titles().first, 'T 001', reason: 'explicit refresh applies changed sort data');
  });

  test('a late loadMore after profile disposal cannot republish its page', () async {
    final gate = Completer<void>();
    client.pageGate = gate;
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final entered = Completer<void>();
    client.pageEntered = entered;
    // Let buffered rounds settle until one actually starts a page fetch.
    // Page sizes and grouping may overshoot a round's target.
    Future<void>? pending;
    for (var round = 0; round < 10 && !entered.isCompleted; round++) {
      pending = catalog.loadMore();
      await Future.any([pending, entered.future]).timeout(const Duration(seconds: 2));
    }
    expect(entered.isCompleted, isTrue, reason: 'the fake page must really be in flight');
    catalog.dispose();
    expect(catalog.snapshot.groups, isEmpty);
    gate.complete();
    await pending!;
    expect(catalog.snapshot.groups, isEmpty);
  });

  group('review membership regressions', () {
    MediaItem source(String id, String title, {String guid = 'plex://movie/shared'}) => MediaItem(
      id: id,
      backend: MediaBackend.plex,
      kind: MediaKind.movie,
      title: title,
      guid: guid,
      year: 2020,
      serverId: 'nas',
      durationMs: 100000,
    );

    List<MediaItem> fillers() => [
      for (var i = 0; i < 120; i++)
        source('filler$i', 'M ${i.toString().padLeft(3, '0')}', guid: 'plex://movie/filler$i'),
    ];

    Future<({MediaItem a, MediaItem b})> loadPair() async {
      final a = source('source-a', 'A Film');
      final b = source(
        'source-b',
        'A Film',
      ).copyWith(summary: 'Richer metadata', thumbPath: '/poster-b', viewOffsetMs: 30000, lastViewedAt: 1000);
      client.rows = [a, b, ...fillers()];
      await catalog.refresh();
      final group = catalog.snapshot.groups.first;
      expect(group.sources.map((s) => s.sourceKey), [a.globalKey, b.globalKey]);
      expect(group.representativeSourceKey, b.globalKey);
      expect(group.watchState.representativeSourceKey, b.globalKey);
      return (a: a, b: b);
    }

    test('partial refresh retains unobserved late B and recomputes representation and watch state', () async {
      final pair = await loadPair();
      final oldGroupId = catalog.snapshot.groups.first.groupId;
      client.rows = [pair.a, ...fillers(), pair.b.copyWith(title: 'Z Film')];
      final gate = Completer<void>();
      client.pageGate = gate;
      client.gatedOffset = 50;
      final entered = Completer<void>();
      client.gatedPageEntered = entered;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });

      local.publish();
      await settle();
      expect(entered.isCompleted, isFalse, reason: 'background rebuild only reads the visible prefix');
      expect(catalog.snapshot.isComplete, isFalse);
      final retained = catalog.snapshot.groups.firstWhere((g) => g.groupId == oldGroupId);
      expect(retained.sources.map((s) => s.sourceKey), [pair.a.globalKey, pair.b.globalKey]);
      expect(retained.representativeSourceKey, pair.b.globalKey);
      expect(retained.watchState.representativeSourceKey, pair.b.globalKey);
      expect(retained.watchState.hasActiveProgress, isTrue);
      expect(retained.resumeCarriedTo(pair.a.globalKey), const Duration(milliseconds: 30000));

      Future<void>? pending;
      for (var round = 0; round < 10 && !entered.isCompleted; round++) {
        pending = catalog.loadMore();
        await Future.any([pending, entered.future]).timeout(const Duration(seconds: 2));
      }
      expect(entered.isCompleted, isTrue);
      gate.complete();
      await pending;
      for (var round = 0; round < 10 && !catalog.snapshot.isComplete; round++) {
        await catalog.loadMore();
      }
      expect(catalog.snapshot.isComplete, isTrue);
      final observed = catalog.snapshot.groups.firstWhere((g) => g.groupId == oldGroupId);
      expect(observed.sources.map((s) => s.sourceKey), [pair.a.globalKey, pair.b.globalKey]);
      expect(observed.itemOf(pair.b.globalKey).title, 'Z Film');
      expect(
        catalog.snapshot.groups.expand((g) => g.sources).where((s) => s.sourceKey == pair.b.globalKey),
        hasLength(1),
      );
    });

    test('split control never retains B in its old group once B is observed elsewhere', () async {
      final pair = await loadPair();
      client.rows = [pair.a, pair.b.copyWith(title: 'B Rematched', guid: 'plex://movie/rematched'), ...fillers()];
      local.publish();
      await settle();
      expect(catalog.snapshot.isComplete, isFalse);
      final a = catalog.snapshot.groups.firstWhere((g) => g.sources.any((s) => s.sourceKey == pair.a.globalKey));
      final b = catalog.snapshot.groups.firstWhere((g) => g.sources.any((s) => s.sourceKey == pair.b.globalKey));
      expect(a.sources.map((s) => s.sourceKey), [pair.a.globalKey]);
      expect(a.representativeSourceKey, pair.a.globalKey);
      expect(a.watchState.hasActiveProgress, isFalse);
      expect(b.sources.map((s) => s.sourceKey), [pair.b.globalKey]);
      expect(b.watchState.hasActiveProgress, isTrue);
      expect(
        catalog.snapshot.groups.expand((g) => g.sources).where((s) => s.sourceKey == pair.b.globalKey),
        hasLength(1),
      );
    });

    test('asymmetric split keeps unobserved A in X while observed B moves to Y', () async {
      final pair = await loadPair();
      final identityX = catalog.snapshot.groups.first.identity;
      final groupX = catalog.snapshot.groups.first.groupId;
      client.rows = [
        pair.b.copyWith(title: 'B Rematched', guid: 'plex://movie/rematched'),
        ...fillers(),
        pair.a.copyWith(title: 'Z Film'),
      ];
      local.publish();
      await settle();
      expect(catalog.snapshot.isComplete, isFalse);
      final a = catalog.snapshot.groups.firstWhere((g) => g.sources.any((s) => s.sourceKey == pair.a.globalKey));
      final b = catalog.snapshot.groups.firstWhere((g) => g.sources.any((s) => s.sourceKey == pair.b.globalKey));
      expect(a.groupId, groupX);
      expect(a.identity, identityX, reason: 'an unobserved sibling must not inherit a rematch');
      expect(a.sources.map((s) => s.sourceKey), [pair.a.globalKey]);
      expect(a.watchState.hasActiveProgress, isFalse);
      expect(a.representativeSourceKey, pair.a.globalKey);
      expect(b.identity, isNot(identityX));
      expect(b.sources.map((s) => s.sourceKey), [pair.b.globalKey]);
      expect(b.watchState.hasActiveProgress, isTrue);
      expect(
        catalog.snapshot.groups.expand((g) => g.sources).where((s) => s.sourceKey == pair.b.globalKey),
        hasLength(1),
      );
    });

    test('two weak ambiguous editions survive refresh and retain the exact final total', () async {
      final theatrical = source('edition-theatrical', 'Collision', guid: '');
      final directors = source('edition-directors', 'Collision', guid: '');
      client.rows = [theatrical, directors];
      await catalog.refresh();
      expect(catalog.snapshot.groups, hasLength(2));
      expect(catalog.snapshot.groups.map((g) => g.groupId).toSet(), hasLength(1), reason: 'groupId is not unique');
      local.publish();
      await settle();
      expect(catalog.snapshot.groups, hasLength(2));
      expect(catalog.snapshot.groups.expand((g) => g.sources).map((s) => s.sourceKey), [
        theatrical.globalKey,
        directors.globalKey,
      ]);
      expect(catalog.snapshot.isComplete, isTrue);
      expect(catalog.snapshot.totalGroupCount, 2);
      await catalog.loadMore();
      expect(catalog.snapshot.totalGroupCount, 2);
    });
  });
}
