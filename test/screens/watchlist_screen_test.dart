import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/watchlist_entry.dart';
import 'package:pleya/media/watchlist_scope.dart';
import 'package:pleya/media/watchlist_source.dart';
import 'package:pleya/providers/offline_mode_provider.dart';
import 'package:pleya/providers/watchlist_provider.dart';
import 'package:pleya/screens/watchlist_screen.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/watchlist/watchlist_repository.dart';
import 'package:pleya/services/watchlist/watchlist_snapshot_store.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/focus/focusable_button.dart';
import 'package:pleya/widgets/watchlist_card.dart';

import '../test_helpers/prefs.dart';

final scope = WatchlistScopeId(profileId: 'p1', backend: MediaBackend.plex, accountId: 'a', userId: 'u');

WatchlistEntry entry({
  required String key,
  String title = 'Sintel',
  MediaKind kind = MediaKind.movie,
  int? year = 2010,
  int position = 0,
}) {
  return WatchlistEntry(
    key: key,
    kind: kind,
    item: MediaItem(id: key, backend: MediaBackend.plex, kind: kind, title: title, year: year),
    guid: 'plex://movie/$key',
    posterRef: 'https://metadata-static.plex.tv/$key.jpg',
    memberships: [WatchlistMembership(scope: scope, remoteKey: key, sourcePosition: position)],
  );
}

class _StubSource implements WatchlistSource {
  _StubSource(this.entries);

  final List<WatchlistEntry> entries;
  final removed = <WatchlistMembership>[];

  /// Counts every trip to the source, so a test can prove that a screen action
  /// did not go out over the wire.
  int fetchCount = 0;

  @override
  WatchlistScopeId get scope =>
      WatchlistScopeId(profileId: 'p1', backend: MediaBackend.plex, accountId: 'a', userId: 'u');

  @override
  bool accepts(MediaItem item) => true;

  @override
  Future<List<WatchlistEntry>> fetch() async {
    fetchCount++;
    return entries;
  }

  @override
  Future<WatchlistMembership> add(MediaItem item) async => WatchlistMembership(scope: scope, remoteKey: item.id);

  @override
  Future<void> remove(WatchlistMembership membership) async => removed.add(membership);

  @override
  Future<bool?> contains(MediaItem item) async => null;
}

/// Reports offline without dragging a MultiServerManager into a widget test.
/// The screen only ever reads [isOffline] off this provider.
class _OfflineProvider extends ChangeNotifier implements OfflineModeProvider {
  @override
  bool get isOffline => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late WatchlistProvider provider;
  late _StubSource source;

  setUp(() async {
    resetSharedPreferencesForTest();
    await SettingsService.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
  });

  tearDown(() async => db.close());

  Future<void> pumpScreen(
    WidgetTester tester,
    List<WatchlistEntry> entries, {
    bool seerrConfigured = false,
    bool offline = false,
  }) async {
    source = _StubSource(entries);
    provider = WatchlistProvider(
      snapshots: WatchlistSnapshotStore(cache: PlexApiCache.instance),
      repository: WatchlistRepository(sources: [source]),
      seerrConfigured: seerrConfigured,
    );
    // Load before pumping, and through runAsync: the snapshot store talks to a
    // real sqlite file, which the test binding's fake async never advances. The
    // screen kicks off its own load too, but by then this one has settled and
    // the spinner is gone, so the frame count stays predictable.
    await tester.runAsync(() => provider.load());
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          // Without an OfflineModeProvider the screen reads absent as online,
          // which is the state most of these tests are about.
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<WatchlistProvider>.value(value: provider),
              if (offline) ChangeNotifierProvider<OfflineModeProvider>(create: (_) => _OfflineProvider()),
            ],
            child: const WatchlistScreen(),
          ),
        ),
      ),
    );
    // Not pumpAndSettle: the loading spinner animates forever, so settling is
    // impossible until the load lands. Three pumps cover schedule, resolve and
    // rebuild.
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('renders one card per title', (tester) async {
    await pumpScreen(tester, [entry(key: 'a', title: 'Sintel'), entry(key: 'b', title: 'Big Buck Bunny')]);

    expect(find.byType(WatchlistCard), findsNWidgets(2));
    expect(find.text('Sintel'), findsOneWidget);
    expect(find.text('Big Buck Bunny'), findsOneWidget);
  });

  testWidgets('an empty watchlist and a filter that hides everything say different things', (tester) async {
    await pumpScreen(tester, []);
    expect(find.text(t.watchlist.empty), findsOneWidget);
    expect(find.text(t.watchlist.emptyBody), findsOneWidget);

    await pumpScreen(tester, [entry(key: 'a', kind: MediaKind.movie)]);
    await tester.tap(find.text(t.watchlist.filterShows));
    await tester.pump();
    await tester.pump();

    expect(find.text(t.watchlist.emptyFiltered), findsOneWidget);
    expect(find.text(t.watchlist.empty), findsNothing);
  });

  testWidgets('both empty states keep a focusable action, so a remote has somewhere to go', (tester) async {
    await pumpScreen(tester, []);
    expect(find.widgetWithText(FocusableButton, t.watchlist.retry), findsOneWidget);

    await pumpScreen(tester, [entry(key: 'a')]);
    await tester.tap(find.text(t.watchlist.filterShows));
    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(FocusableButton, t.watchlist.filterAll), findsOneWidget);
  });

  testWidgets('the type filters narrow the grid', (tester) async {
    await pumpScreen(tester, [
      entry(key: 'movie', title: 'A Movie'),
      entry(key: 'show', title: 'A Show', kind: MediaKind.show),
    ]);

    await tester.tap(find.text(t.watchlist.filterMovies));
    await tester.pump();
    await tester.pump();
    expect(find.text('A Movie'), findsOneWidget);
    expect(find.text('A Show'), findsNothing);

    await tester.tap(find.text(t.watchlist.filterShows));
    await tester.pump();
    await tester.pump();
    expect(find.text('A Show'), findsOneWidget);
    expect(find.text('A Movie'), findsNothing);
  });

  testWidgets('the grid never scrolls horizontally out of its own clip', (tester) async {
    await pumpScreen(tester, [entry(key: 'a')]);

    final scrollView = tester.widget<CustomScrollView>(find.byType(CustomScrollView).first);

    // A focused card grows past its cell; hardEdge would shear the ring off at
    // the viewport edge on TV.
    expect(scrollView.clipBehavior, Clip.none);
  });

  testWidgets('Remove in the sheet reaches the source and drops the card', (tester) async {
    await pumpScreen(tester, [entry(key: 'a', title: 'Sintel')]);

    await tester.tap(find.byType(WatchlistCard));
    await tester.pumpAndSettle();
    expect(find.text(t.watchlist.remove), findsOneWidget);

    await tester.tap(find.text(t.watchlist.remove));
    await tester.pumpAndSettle();

    expect(source.removed.single.remoteKey, 'a');
    // The grid emptying is the confirmation, which is why no snackbar follows.
    expect(find.byType(WatchlistCard), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Request in the sheet goes to Seerr, and says so when there is no id to send', (tester) async {
    final unavailable = WatchlistEntry(
      key: 'a',
      kind: MediaKind.movie,
      item: MediaItem(id: 'a', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Sintel'),
      guid: 'plex://movie/a',
      memberships: [WatchlistMembership(scope: scope, remoteKey: 'a')],
      availability: WatchlistAvailability.notFound,
      coverageComplete: true,
    );
    await pumpScreen(tester, [unavailable], seerrConfigured: true);

    await tester.tap(find.byType(WatchlistCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.seerr.request));
    await tester.pumpAndSettle();

    // No TMDB id on the entry, so the request cannot be filed and the screen
    // says that rather than opening an empty sheet.
    expect(find.text(t.seerr.errorGeneric), findsOneWidget);
    expect(source.removed, isEmpty);
  });

  group('sorting', () {
    List<String> cardOrder(WidgetTester tester) =>
        tester.widgetList<WatchlistCard>(find.byType(WatchlistCard)).map((card) => card.entry.key).toList();

    Future<void> pick(WidgetTester tester, String option) async {
      await tester.tap(find.text(t.libraries.sort));
      await tester.pumpAndSettle();
      await tester.tap(find.text(option));
      await tester.pumpAndSettle();
    }

    // Positions run against the alphabet on purpose: if the screen ever fell
    // back on title order, the default would still look right by accident.
    List<WatchlistEntry> threeFilms() => [
      entry(key: 'c', title: 'Cars', year: 2006, position: 0),
      entry(key: 'a', title: 'Alien', year: 1979, position: 1),
      entry(key: 'b', title: 'Blade Runner', year: 1982, position: 2),
    ];

    testWidgets('the default is the order the list was added in', (tester) async {
      await pumpScreen(tester, threeFilms());

      expect(cardOrder(tester), ['c', 'a', 'b']);
    });

    testWidgets('title and year reorder the grid without going back to the source', (tester) async {
      await pumpScreen(tester, threeFilms());
      final fetchesAfterLoad = source.fetchCount;

      await pick(tester, t.watchlist.sortTitle);
      expect(cardOrder(tester), ['a', 'b', 'c']);

      await pick(tester, t.watchlist.sortYear);
      expect(cardOrder(tester), ['c', 'b', 'a']);

      await pick(tester, t.watchlist.sortRecentlyAdded);
      expect(cardOrder(tester), ['c', 'a', 'b']);

      // Order is a property of the list already in memory. Fetching again to
      // answer it would be a round trip for something the app knows.
      expect(source.fetchCount, fetchesAfterLoad);
    });

    testWidgets('sorting applies to what a type filter left over', (tester) async {
      await pumpScreen(tester, [
        entry(key: 'c', title: 'Cars', year: 2006, position: 0),
        entry(key: 'show', title: 'Andor', year: 2022, kind: MediaKind.show, position: 1),
        entry(key: 'a', title: 'Alien', year: 1979, position: 2),
      ]);

      await tester.tap(find.text(t.watchlist.filterMovies));
      await tester.pumpAndSettle();
      await pick(tester, t.watchlist.sortTitle);

      expect(cardOrder(tester), ['a', 'c'], reason: 'the show is filtered out and the two films are sorted');
    });

    testWidgets('at 360dp the bar stays one row: the chips scroll and the button holds its place', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpScreen(tester, threeFilms());

      // A Row that did not fit would throw here rather than reflow, so simply
      // arriving with the button on screen is the assertion.
      final button = find.text(t.libraries.sort);
      expect(button, findsOneWidget);
      expect(tester.getTopRight(button).dx, lessThanOrEqualTo(360));

      // The chips share the row with the button instead of pushing it off.
      expect(tester.getTopRight(find.text(t.watchlist.filterAll)).dx, lessThan(tester.getTopLeft(button).dx));
    });

    testWidgets('offline the order can still be changed, but Available cannot be picked', (tester) async {
      await pumpScreen(tester, threeFilms(), offline: true);

      // Availability needs live servers; order does not.
      expect(find.text(t.watchlist.filterAvailable), findsNothing);
      expect(find.text(t.libraries.sort), findsOneWidget);

      await pick(tester, t.watchlist.sortTitle);

      expect(cardOrder(tester), ['a', 'b', 'c']);
    });
  });
}
