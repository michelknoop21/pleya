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

WatchlistEntry entry({required String key, String title = 'Sintel', MediaKind kind = MediaKind.movie}) {
  return WatchlistEntry(
    key: key,
    kind: kind,
    item: MediaItem(id: key, backend: MediaBackend.plex, kind: kind, title: title, year: 2010),
    guid: 'plex://movie/$key',
    posterRef: 'https://metadata-static.plex.tv/$key.jpg',
    memberships: [WatchlistMembership(scope: scope, remoteKey: key)],
  );
}

class _StubSource implements WatchlistSource {
  _StubSource(this.entries);

  final List<WatchlistEntry> entries;

  @override
  WatchlistScopeId get scope =>
      WatchlistScopeId(profileId: 'p1', backend: MediaBackend.plex, accountId: 'a', userId: 'u');

  @override
  bool accepts(MediaItem item) => true;

  @override
  Future<List<WatchlistEntry>> fetch() async => entries;

  @override
  Future<WatchlistMembership> add(MediaItem item) async => WatchlistMembership(scope: scope, remoteKey: item.id);

  @override
  Future<void> remove(WatchlistMembership membership) async {}

  @override
  Future<bool?> contains(MediaItem item) async => null;
}

void main() {
  late AppDatabase db;
  late WatchlistProvider provider;

  setUp(() async {
    resetSharedPreferencesForTest();
    await SettingsService.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
  });

  tearDown(() async => db.close());

  Future<void> pumpScreen(WidgetTester tester, List<WatchlistEntry> entries) async {
    provider = WatchlistProvider(
      snapshots: WatchlistSnapshotStore(cache: PlexApiCache.instance),
      repository: WatchlistRepository(sources: [_StubSource(entries)]),
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
          // No OfflineModeProvider: the screen reads it as nullable and
          // treats absent as online, which is the state under test here.
          home: ChangeNotifierProvider<WatchlistProvider>.value(value: provider, child: const WatchlistScreen()),
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
}
