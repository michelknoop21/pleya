/// A-06c: what the compact card says under and on its poster. The second line
/// follows the sort, and the corner keeps its marks apart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/new_content_badge.dart';
import 'package:pleya/widgets/tv/tv_catalog_meta.dart';
import 'package:pleya/widgets/tv/tv_unified_media_card.dart';

import '../../test_helpers/prefs.dart';
import '../../test_helpers/tv_catalog_fixtures.dart';
import '../../test_helpers/tv_full_bleed_catalog_harness.dart';

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  group('second line', () {
    final added = DateTime.utc(2024, 3, 9, 12).millisecondsSinceEpoch ~/ 1000;
    final viewed = DateTime.utc(2025, 7, 1, 12).millisecondsSinceEpoch ~/ 1000;
    final item = fakeMovie(1, year: 1999, addedAt: added, lastViewedAt: viewed);

    test('title and release sorts read the year', () {
      for (final sort in [
        UnifiedCatalogSort.titleAsc,
        UnifiedCatalogSort.titleDesc,
        UnifiedCatalogSort.newestRelease,
        UnifiedCatalogSort.oldestRelease,
      ]) {
        expect(tvCatalogSortedMetaLine(item, sort: sort), '1999', reason: sort.name);
      }
    });

    test('the added sorts read the date added', () {
      expect(tvCatalogSortedMetaLine(item, sort: UnifiedCatalogSort.recentlyAdded), 'Mar 9, 2024');
      expect(tvCatalogSortedMetaLine(item, sort: UnifiedCatalogSort.oldestAdded), 'Mar 9, 2024');
    });

    test('recently watched reads the date watched, and prefers the group over the item', () {
      expect(tvCatalogSortedMetaLine(item, sort: UnifiedCatalogSort.recentlyWatched), 'Jul 1, 2025');
      final group = DateTime.utc(2026, 1, 2, 12).millisecondsSinceEpoch ~/ 1000;
      expect(
        tvCatalogSortedMetaLine(item, sort: UnifiedCatalogSort.recentlyWatched, lastViewedAt: group),
        'Jan 2, 2026',
      );
    });

    test('a missing date falls back to the year, a missing year to nothing', () {
      expect(tvCatalogSortedMetaLine(fakeMovie(2, year: 2001), sort: UnifiedCatalogSort.recentlyAdded), '2001');
      expect(tvCatalogSortedMetaLine(fakeMovie(3), sort: UnifiedCatalogSort.recentlyWatched), '');
    });
  });

  group('corner', () {
    setUp(() async {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      await SettingsService.getInstance();
    });

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    /// On the Apple TV canvas, at the width density 1 leaves.
    Future<void> pumpCard(WidgetTester tester, UnifiedMediaGroup group, {double width = 116}) {
      tester.view.physicalSize = const Size(1038, 584);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      return tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true),
          home: Material(
            child: Align(
              alignment: Alignment.topLeft,
              child: TvUnifiedMediaCard(group: group, width: width, onSelect: () {}, compact: true),
            ),
          ),
        ),
      );
    }

    testWidgets('a new series with episodes left carries dot and count beside each other', (tester) async {
      await pumpCard(tester, _group(fakeShow(1, leaves: 1200, viewed: 3, addedAt: now)));
      final dot = tester.getRect(find.byType(NewContentDot));
      final count = tester.getRect(find.text('999+'));
      expect(dot.right, lessThanOrEqualTo(count.left), reason: 'dot and count share the tab without overlap');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the source badge, the tab and the bar keep apart on the narrowest poster', (tester) async {
      await pumpCard(tester, _group(fakeShow(1, leaves: 1200, viewed: 3, addedAt: now), sources: 2, progress: true));
      final badge = tester.getRect(find.byKey(tvUnifiedMediaCardSourceBadgeKey));
      final tab = tester.getRect(find.byKey(tvUnifiedMediaCardCornerTabKey));
      expect(badge.right, lessThanOrEqualTo(tab.left), reason: 'side by side at 116 wide');
      expect(tab.top, 0, reason: 'flush with the corner');
      expect(tab.right, 116);
    });

    testWidgets('a watched title carries the tick and no count', (tester) async {
      await pumpCard(tester, _group(fakeShow(1, leaves: 8, viewed: 8), watched: true));
      expect(find.byKey(tvUnifiedMediaCardCornerTabKey), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('nothing to say draws no tab, and the preference hides the count', (tester) async {
      await pumpCard(tester, _group(fakeMovie(1, year: 2000)));
      expect(find.byKey(tvUnifiedMediaCardCornerTabKey), findsNothing);

      await SettingsService.instance.write(SettingsService.showUnwatchedCount, false);
      await pumpCard(tester, _group(fakeShow(2, leaves: 8, viewed: 3)));
      expect(find.text('5'), findsNothing);
    });

    testWidgets('the wrapped card keeps its marks and its line', (tester) async {
      final group = _group(fakeMovie(1, year: 2000, viewCount: 1), watched: true);
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true),
          home: Material(
            child: Align(
              alignment: Alignment.topLeft,
              child: TvUnifiedMediaCard(group: group, width: 200, onSelect: () {}),
            ),
          ),
        ),
      );
      expect(find.byKey(tvUnifiedMediaCardCornerTabKey), findsNothing);
      expect(find.text(tvCatalogMetaLine(group.representativeSource.item)), findsOneWidget);
    });
  });
}

UnifiedMediaGroup _group(MediaItem item, {int sources = 1, bool watched = false, bool progress = false}) =>
    tvGoldenGroup(
      'g',
      [
        for (var i = 0; i < sources; i++)
          i == 0
              ? (progress ? item.copyWith(durationMs: 1000, viewOffsetMs: 500) : item)
              : item.copyWith(id: '${item.id}-$i', serverId: 'second'),
      ],
      watched: watched,
      inProgress: progress,
    );
