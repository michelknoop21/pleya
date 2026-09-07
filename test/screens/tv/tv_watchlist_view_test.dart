/// The kijklijst's TV presentation, pumped on its own.
///
/// `watchlist_screen_test.dart` drives the whole page through a real
/// `WatchlistProvider`, which is the right harness for the journeys. Two of
/// DEC-108's contracts cannot be reached that way, because they are states the
/// stub source cannot produce: a fetch where one source did not answer (mockup
/// 34 C), and the window of titles whose availability is asked for.
///
/// The view takes finished lists and callbacks and owns no provider, which is
/// exactly what makes this possible.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/watchlist_entry.dart';
import 'package:pleya/media/watchlist_filter.dart';
import 'package:pleya/media/watchlist_scope.dart';
import 'package:pleya/screens/tv/tv_watchlist_view.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_catalog_selection_tags.dart';
import 'package:pleya/widgets/tv/tv_watchlist_card.dart';

final _scope = WatchlistScopeId(profileId: 'p1', backend: MediaBackend.plex, accountId: 'a', userId: 'u');

WatchlistEntry _entry(
  String key, {
  String? title,
  MediaKind kind = MediaKind.movie,
  WatchlistAvailability availability = WatchlistAvailability.unknown,
}) => WatchlistEntry(
  key: key,
  kind: kind,
  item: MediaItem(id: key, backend: MediaBackend.plex, kind: kind, title: title ?? 'Title $key', year: 2024),
  memberships: [WatchlistMembership(scope: _scope, remoteKey: key)],
  availability: availability,
);

void main() {
  setUp(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  Future<List<List<WatchlistEntry>>> pumpView(
    WidgetTester tester,
    List<WatchlistEntry> entries, {
    bool coverageComplete = true,
    WatchlistFilterSelection selection = WatchlistFilterSelection.none,
    WatchlistSort sort = WatchlistSort.recentlyAdded,
  }) async {
    final asked = <List<WatchlistEntry>>[];
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: TvWatchlistView(
              entries: entries,
              totalCount: entries.length,
              selection: selection,
              sort: sort,
              onSelectionChanged: (_) {},
              onSortChanged: (_) {},
              onActivate: (_) {},
              isLoading: false,
              coverageComplete: coverageComplete,
              offerAvailability: true,
              onReload: () {},
              onNeedsAvailability: asked.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return asked;
  }

  testWidgets('a fetch that missed a source says so under the heading (mockup 34 C)', (tester) async {
    await pumpView(tester, [_entry('a')], coverageComplete: false);

    expect(find.text(t.watchlist.coverageIncompleteList), findsOneWidget);
  });

  testWidgets('and says nothing when every source answered', (tester) async {
    await pumpView(tester, [_entry('a')]);

    expect(find.text(t.watchlist.coverageIncompleteList), findsNothing);
  });

  testWidgets('an empty list draws no notice either, however the fetch went', (tester) async {
    // There is nothing on screen for the line to qualify, and a warning over an
    // empty state reads as the reason it is empty, which it is not.
    await pumpView(tester, const [], coverageComplete: false);

    expect(find.text(t.watchlist.coverageIncompleteList), findsNothing);
  });

  group('availability is asked for around the cursor, not for the whole list', () {
    // The phone resolves per card as the card is built, which is viewport-driven
    // and correct there. `TvCatalogCardGrid` builds every row eagerly, so the
    // same code would fan out one lookup per title on open — the exact thing
    // `WatchlistProvider.resolveAvailability` is lazy to avoid.
    List<WatchlistEntry> many() => [for (var i = 0; i < 60; i++) _entry('k$i')];

    testWidgets('an untouched page resolves a couple of rows and no more', (tester) async {
      final asked = await pumpView(tester, many());

      final keys = {for (final batch in asked) ...batch.map((e) => e.key)};
      expect(keys, isNotEmpty, reason: 'a viewer who never presses anything still needs the badges they can see');
      expect(keys.length, lessThan(60), reason: 'sixty lookups on open is what the lazy resolver exists to prevent');
      expect(keys, contains('k0'));
    });

    testWidgets('walking down asks for the rows the remote reaches, once each', (tester) async {
      final asked = await pumpView(tester, many());
      final seeded = {for (final batch in asked) ...batch.map((e) => e.key)};

      final first = tester.widgetList<TvWatchlistCard>(find.byType(TvWatchlistCard)).first;
      first.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      for (var i = 0; i < 6; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }

      final all = [for (final batch in asked) ...batch.map((e) => e.key)];
      expect(all.toSet().length, all.length, reason: 'a title is never asked for twice');
      expect(all.toSet().length, greaterThan(seeded.length), reason: 'the walk reached rows the seed had not');
      expect(all.toSet().length, lessThan(60), reason: 'and still not the whole list');
    });

    testWidgets('a title that already has an answer is not asked about again', (tester) async {
      final asked = await pumpView(tester, [
        _entry('a', availability: WatchlistAvailability.available),
        _entry('b', availability: WatchlistAvailability.notFound),
        _entry('c'),
      ]);

      final keys = [for (final batch in asked) ...batch.map((e) => e.key)];
      expect(keys, ['c']);
    });
  });

  testWidgets('the heading names what the page is narrowed to, sort last and muted', (tester) async {
    await pumpView(
      tester,
      [_entry('a')],
      selection: const WatchlistFilterSelection(kind: WatchlistKindFilter.shows, availableOnly: true),
      sort: WatchlistSort.title,
    );

    final strip = tester.widget<TvCatalogSelectionTagStrip>(find.byType(TvCatalogSelectionTagStrip));
    expect(strip.tags.map((tag) => tag.label), [
      t.watchlist.filterAvailable,
      t.watchlist.filterShows,
      watchlistSortLabelOf(WatchlistSort.title),
    ]);
    expect(strip.tags.last.muted, isTrue, reason: 'there is no such thing as an unsorted kijklijst');
  });
}

/// The label the view uses for a sort, without importing the sheet that owns it
/// into the expectations above.
String watchlistSortLabelOf(WatchlistSort sort) => switch (sort) {
  WatchlistSort.recentlyAdded => t.watchlist.sortRecentlyAdded,
  WatchlistSort.title => t.watchlist.sortTitle,
  WatchlistSort.year => t.watchlist.sortYear,
};
