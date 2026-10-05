import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/watchlist_entry.dart';
import 'package:pleya/media/watchlist_scope.dart';
import 'package:pleya/media/watchlist_source.dart';
import 'package:pleya/models/livetv_channel.dart';
import 'package:pleya/models/livetv_hub_result.dart';
import 'package:pleya/models/livetv_program.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/home_extra_rows_provider.dart';
import 'package:pleya/providers/home_layout_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/watchlist_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/unified_catalog/home_projection_service.dart';
import 'package:pleya/services/unified_catalog/home_row_layout.dart';
import 'package:pleya/services/watchlist/watchlist_repository.dart';
import 'package:pleya/services/watchlist/watchlist_snapshot_store.dart';
import 'package:pleya/utils/external_ids.dart';

import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';

final _scope = WatchlistScopeId(profileId: 'p1', backend: MediaBackend.plex, accountId: 'a', userId: 'u');

WatchlistEntry _entry(String id, {bool matched = true}) => WatchlistEntry(
  key: 'plex:$id',
  kind: MediaKind.movie,
  item: MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: id),
  guid: 'plex://movie/$id',
  memberships: [WatchlistMembership(scope: _scope, remoteKey: id)],
  availability: matched ? WatchlistAvailability.available : WatchlistAvailability.notFound,
  lastKnownMatch: matched
      ? MediaItem(
          id: 'lib-$id',
          backend: MediaBackend.plex,
          kind: MediaKind.movie,
          title: id,
          serverId: 'srv',
          libraryId: id == 'c' ? 'kids' : 'films',
        )
      : null,
);

class _Source implements WatchlistSource {
  _Source(this.entries);

  final List<WatchlistEntry> entries;
  int fetches = 0;

  @override
  WatchlistScopeId get scope => _scope;

  @override
  bool accepts(MediaItem item) => true;

  @override
  Future<List<WatchlistEntry>> fetch() async {
    fetches++;
    // A real source answers over the network; the tests must not rely on it
    // answering within a fixed number of microtask turns.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return entries;
  }

  @override
  Future<WatchlistMembership> add(MediaItem item) async => WatchlistMembership(scope: scope, remoteKey: item.id);

  @override
  Future<void> remove(WatchlistMembership membership) async {}

  @override
  Future<bool?> contains(MediaItem item) async => null;
}

class _LiveMultiServer extends MultiServerProvider {
  _LiveMultiServer(super.manager, super.aggregation);

  @override
  List<LiveTvServerInfo> get liveTvServers => [LiveTvServerInfo(serverId: 'srv', dvrKey: 'dvr')];
}

LiveTvHubEntry _airing(String id, {required String channel, bool now = true}) {
  final t = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return LiveTvHubEntry(
    metadata: MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.episode, title: id, serverId: 'srv'),
    program: LiveTvProgram(
      title: id,
      beginsAt: now ? t - 600 : t + 600,
      endsAt: now ? t + 600 : t + 1200,
      channelIdentifier: channel,
    ),
  );
}

void main() {
  late AppDatabase db;
  late HomeLayoutProvider layout;
  late _Source source;
  late WatchlistProvider watchlist;
  late MultiServerProvider multiServer;
  int liveLoads = 0;

  final projection = HomeProjectionService(fetchExternalIds: (_, _) async => const ExternalIds());

  HomeExtraRowsProvider build({
    MultiServerProvider? servers,
    List<LiveTvHubEntry> live = const [],
    HiddenLibrariesProvider? hiddenLibraries,
  }) => HomeExtraRowsProvider(
    layout: layout,
    hiddenLibraries: hiddenLibraries,
    multiServer: servers ?? multiServer,
    watchlist: watchlist,
    watchlistTitle: 'Kijklijst',
    liveTvTitle: 'Nu op tv',
    watchlistProjection: projection,
    loadLiveTv: () async {
      liveLoads++;
      return (
        entries: live,
        channels: [
          LiveTvChannel(key: 'ch1'),
          LiveTvChannel(key: 'ch2'),
        ],
      );
    },
  );

  /// Lets the source, the snapshot store (a database executor) and the
  /// projection finish. Real timers: microtask turns are not enough once a
  /// fetch or a database write is involved, and CI machines are slower.
  Future<void> settle() async {
    for (var i = 0; i < 15; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  setUp(() async {
    resetSharedPreferencesForTest();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    layout = HomeLayoutProvider();
    await layout.ensureInitialized();
    source = _Source([_entry('a'), _entry('b', matched: false), _entry('c')]);
    watchlist = WatchlistProvider(
      snapshots: WatchlistSnapshotStore(cache: PlexApiCache.instance),
      repository: WatchlistRepository(sources: [source]),
    );
    final manager = MultiServerManager();
    multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    liveLoads = 0;
  });

  tearDown(() async => db.close());

  test('Kijklijst is on by default and holds only titles that resolve to a library item', () async {
    final subject = build();
    await settle();

    final rows = subject.visibleRows();
    expect(rows, hasLength(1));
    expect(homeLayoutIdsOf(rows.single), [homeWatchlistRowId]);
    expect([for (final g in rows.single.groups) g.representativeSource.item.id], ['lib-a', 'lib-c']);
    subject.dispose();
  });

  test('a match in a hidden library stays off Home, and returns when the library is shown again', () async {
    final hiddenLibraries = HiddenLibrariesProvider();
    await hiddenLibraries.ensureInitialized();
    await hiddenLibraries.hideLibrary('srv:kids');
    final subject = build(hiddenLibraries: hiddenLibraries);
    await settle();
    expect([for (final g in subject.visibleRows().single.groups) g.representativeSource.item.id], ['lib-a']);

    await hiddenLibraries.unhideLibrary('srv:kids');
    await settle();
    expect([for (final g in subject.visibleRows().single.groups) g.representativeSource.item.id], ['lib-a', 'lib-c']);
    subject.dispose();
    hiddenLibraries.dispose();
  });

  test('a hidden Kijklijst row fetches nothing, and loads when it is turned back on', () async {
    await layout.setRowHidden(homeWatchlistRowId, true);
    final subject = build();
    await settle();
    expect(source.fetches, 0);
    expect(subject.visibleRows(), isEmpty);

    await layout.setRowHidden(homeWatchlistRowId, false);
    await settle();
    expect(source.fetches, 1);
    expect(subject.visibleRows(), hasLength(1));
    subject.dispose();
  });

  testWidgets('created lazily during a build, it does not notify the kijklijst inside that build', (tester) async {
    // What Home does: the provider is lazy, so the first `watch` constructs it
    // in the middle of a build, while other widgets already listen to the
    // kijklijst. Loading the kijklijst from the constructor notified those
    // listeners mid-build and took Home down with it (PR #165, ios-sim).
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WatchlistProvider>.value(value: watchlist),
          ChangeNotifierProvider<HomeExtraRowsProvider>(create: (_) => build(), lazy: true),
        ],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              Consumer<WatchlistProvider>(builder: (_, w, _) => Text('loading=${w.isLoading}')),
              Builder(
                builder: (context) => Text('rows=${context.watch<HomeExtraRowsProvider>().visibleRows().length}'),
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(tester.takeException(), isNull);
    // Let the source's answer arrive, so no timer outlives the test.
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });

  test('Nu op tv is off until the viewer turns it on, and costs nothing while off', () async {
    final manager = MultiServerManager();
    final live = _LiveMultiServer(manager, DataAggregationService(manager));
    final subject = build(
      servers: live,
      live: [
        _airing('news', channel: 'ch1'),
        _airing('later', channel: 'ch2', now: false),
        _airing('x', channel: 'gone'),
      ],
    );
    await settle();
    expect(liveLoads, 0);
    expect(layout.isRowHidden(homeLiveTvRowId), isTrue);
    // Still listed for the surfaces that let the viewer turn it on.
    expect(subject.allRows().expand(homeLayoutIdsOf), contains(homeLiveTvRowId));
    expect(subject.visibleRows().expand(homeLayoutIdsOf), isNot(contains(homeLiveTvRowId)));

    await layout.setRowHidden(homeLiveTvRowId, false);
    await settle();
    expect(liveLoads, 1);
    final row = subject.visibleRows().firstWhere((r) => homeLayoutIdsOf(r).contains(homeLiveTvRowId));
    // Only what is on now, on a channel that can be tuned.
    expect([for (final g in row.groups) g.representativeSource.item.id], ['news']);
    expect(subject.isLiveTv(row.groups.single), isTrue);

    await layout.setRowHidden(homeLiveTvRowId, true);
    await settle();
    expect(subject.visibleRows().expand(homeLayoutIdsOf), isNot(contains(homeLiveTvRowId)));
    subject.dispose();
  });
}
