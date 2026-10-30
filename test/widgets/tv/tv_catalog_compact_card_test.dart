/// A-06c: what the compact card says under and on its poster. The second line
/// follows the sort, and the corner keeps its marks apart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_version.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/formatters.dart';
import 'package:pleya/utils/rating_utils.dart';
import 'package:pleya/widgets/media_rating_badge.dart';
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

    test('title and year sorts read the year', () {
      for (final sort in [
        UnifiedCatalogSort.titleAsc,
        UnifiedCatalogSort.titleDesc,
        UnifiedCatalogSort.yearNewest,
        UnifiedCatalogSort.yearOldest,
      ]) {
        expect(tvCatalogSortedMetaLine(item, sort: sort), '1999', reason: sort.name);
      }
    });

    test('every other field reads its own fact', () {
      final full = fakeMovie(4, year: 1999).copyWith(
        originallyAvailableAt: '1999-03-31',
        durationMs: 5400000,
        viewOffsetMs: 2700000,
        viewCount: 3,
        contentRating: 'gb/12',
        mediaVersions: [MediaVersion(id: 'v', videoResolution: '4k', height: 2160)],
      );
      String line(UnifiedCatalogSort sort) => tvCatalogSortedMetaLine(full, sort: sort);
      expect(line(UnifiedCatalogSort.newestRelease), 'Mar 31, 1999');
      expect(line(UnifiedCatalogSort.longest), formatDurationTextual(5400000));
      expect(line(UnifiedCatalogSort.mostProgress), formatDurationTextual(2700000));
      expect(line(UnifiedCatalogSort.mostPlayed), '3 plays');
      expect(line(UnifiedCatalogSort.contentRatingYoungest), '12');
      expect(line(UnifiedCatalogSort.highestResolution), '4K');
    });

    test('a score is a badge, not text, and carries its source', () {
      const plex = PlexMediaItem(
        id: 'p',
        kind: MediaKind.movie,
        rating: 9.6,
        ratingImage: 'rottentomatoes://image.rating.ripe',
      );
      expect(tvCatalogSortedMetaLine(plex, sort: UnifiedCatalogSort.criticHighest), '');
      final score = tvCatalogSortScore(plex, UnifiedCatalogSort.criticHighest)!;
      expect(parseRatingImage(score.imageUri, score.tenPointValue)!.formattedValue, '96%');
      expect(parseRatingImage(score.imageUri, score.tenPointValue)!.assetPath, 'assets/rating_icons/rt_fresh.svg');
    });

    test('the card reads the source that put the group where it stands', () {
      final group = tvGoldenGroup('g', [
        const PlexMediaItem(id: 'low', kind: MediaKind.movie, title: 'X', rating: 6, serverId: 'a'),
        const PlexMediaItem(id: 'high', kind: MediaKind.movie, title: 'X', rating: 9, serverId: 'b'),
      ]);
      expect(tvCatalogSortValueItem(group, UnifiedCatalogSort.criticHighest).id, 'high');
      expect(tvCatalogSortValueItem(group, UnifiedCatalogSort.criticLowest).id, 'low');
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

    test('no value leaves the line empty, on every field', () {
      final bare = fakeMovie(3);
      for (final sort in UnifiedCatalogSort.values) {
        expect(tvCatalogSortedMetaLine(bare, sort: sort), '', reason: sort.name);
        expect(tvCatalogSortScore(bare, sort), isNull, reason: sort.name);
      }
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

    testWidgets('a score, a text line and an empty line keep one footer and one baseline', (tester) async {
      const scored = PlexMediaItem(
        id: 'p',
        kind: MediaKind.movie,
        title: 'Scored',
        serverId: 'nas',
        rating: 9.6,
        ratingImage: 'rottentomatoes://image.rating.ripe',
      );
      Future<(double, Offset)> measure(MediaItem item, UnifiedCatalogSort sort, String title) async {
        tester.view.physicalSize = const Size(1038, 584);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: monoTheme(dark: true),
            home: Material(
              child: Align(
                alignment: Alignment.topLeft,
                child: TvUnifiedMediaCard(
                  group: _group(item),
                  width: 145,
                  onSelect: () {},
                  compact: true,
                  activeSort: sort,
                ),
              ),
            ),
          ),
        );
        return (tester.getSize(find.byType(TvUnifiedMediaCard)).height, tester.getTopLeft(find.text(title)));
      }

      final score = await measure(scored, UnifiedCatalogSort.criticHighest, 'Scored');
      expect(find.byType(MediaRatingBadge), findsOneWidget);
      expect(find.text('96%'), findsOneWidget);
      final text = await measure(scored.copyWith(year: 2024), UnifiedCatalogSort.yearNewest, 'Scored');
      final empty = await measure(
        const PlexMediaItem(id: 'e', kind: MediaKind.movie, title: 'Scored', serverId: 'nas'),
        UnifiedCatalogSort.criticHighest,
        'Scored',
      );
      expect(find.byType(MediaRatingBadge), findsNothing);
      expect(text.$1, score.$1);
      expect(empty.$1, score.$1);
      expect(text.$2, score.$2);
      expect(empty.$2, score.$2);
    });

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
