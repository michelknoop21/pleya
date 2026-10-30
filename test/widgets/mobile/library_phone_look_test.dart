/// The card and the grid of the iPhone library look (A-06). All of it is opt-in
/// through [LibraryPhoneLook]; the second half of each group pins that a card
/// outside the scope still looks the way it did.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/media_card_grid_layout.dart';
import 'package:pleya/widgets/media_grid_delegate.dart';
import 'package:pleya/widgets/mobile/library_phone_look.dart';
import 'package:pleya/widgets/watched_indicator.dart';

import '../../test_helpers/prefs.dart';

MediaItem _watched() => MediaItem(
  id: 'm1',
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'Verity',
  viewCount: 1,
  serverId: 's1',
);

Future<MediaGridGeometry> _geometry(
  WidgetTester tester, {
  required double extent,
  bool wide = false,
  double textScale = 1,
}) async {
  late MediaGridGeometry geometry;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Builder(
        builder: (context) {
          geometry = MediaGridGeometry.phoneLibrary(
            context: context,
            crossAxisExtent: extent,
            useWideAspectRatio: wide,
          );
          return const SizedBox();
        },
      ),
    ),
  );
  return geometry;
}

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  group('phoneLibrary grid', () {
    testWidgets('three poster columns on every phone width held upright', (tester) async {
      for (final screen in const [320.0, 375.0, 402.0, 430.0]) {
        final extent = screen - LibraryPhoneMetrics.gridInsetStart - LibraryPhoneMetrics.gridInsetEnd;
        final geometry = await _geometry(tester, extent: extent);
        expect(geometry.columnCount, 3, reason: 'width $screen');
      }
    });

    testWidgets('the grid delegate lays out exactly the columns the geometry reports', (tester) async {
      final geometry = await _geometry(tester, extent: 365);
      final layout = geometry.delegate.getLayout(
        const SliverConstraints(
          axisDirection: AxisDirection.down,
          growthDirection: GrowthDirection.forward,
          userScrollDirection: ScrollDirection.idle,
          scrollOffset: 0,
          precedingScrollExtent: 0,
          overlap: 0,
          remainingPaintExtent: 800,
          crossAxisExtent: 365,
          crossAxisDirection: AxisDirection.right,
          viewportMainAxisExtent: 800,
          remainingCacheExtent: 800,
          cacheOrigin: 0,
        ),
      );
      expect((layout as SliverGridRegularTileLayout).crossAxisCount, 3);
    });

    testWidgets('the poster is 2:3 and the row gap is its own token', (tester) async {
      final geometry = await _geometry(tester, extent: 365);
      final caption = LibraryPhoneMetrics.captionGap + 37;
      expect(geometry.cellInset, 0);
      expect(geometry.itemWidth, closeTo((365 - 10) / 3, 0.01));
      expect(geometry.itemHeight - caption, closeTo(geometry.itemWidth * 1.5, 0.01));
      expect(geometry.mainAxisSpacing, LibraryPhoneMetrics.gridRowGap);
      expect(geometry.spacing, LibraryPhoneMetrics.gridColumnGap);
    });

    testWidgets('a landscape phone gets more columns, not bigger posters', (tester) async {
      final geometry = await _geometry(tester, extent: 800);
      expect(geometry.columnCount, greaterThan(3));
      expect(geometry.itemWidth, lessThanOrEqualTo(LibraryPhoneMetrics.maxPosterWidth + 30));
    });

    testWidgets('16:9 episode stills take two columns', (tester) async {
      expect((await _geometry(tester, extent: 365, wide: true)).columnCount, 2);
    });

    testWidgets('a larger text size grows the cell with it', (tester) async {
      final normal = await _geometry(tester, extent: 365);
      final large = await _geometry(tester, extent: 365, textScale: 2);
      expect(large.itemHeight, greaterThan(normal.itemHeight + 30));
    });
  });

  group('caption block', () {
    testWidgets('the shared layout follows the scope, and only inside it', (tester) async {
      late double inside;
      late double outside;
      await tester.pumpWidget(
        Column(
          children: [
            LibraryPhoneLook(
              child: Builder(
                builder: (context) {
                  inside = MediaCardGridLayout.textExtentFor(context);
                  return const SizedBox();
                },
              ),
            ),
            Builder(
              builder: (context) {
                outside = MediaCardGridLayout.textExtentFor(context);
                return const SizedBox();
              },
            ),
          ],
        ),
      );
      expect(inside, greaterThan(outside));
    });
  });

  group('watched mark', () {
    Future<void> pump(WidgetTester tester, {required bool look, WatchedIndicatorSize? size}) async {
      await tester.runAsync(SettingsService.getInstance);
      final indicator = SizedBox(
        width: 120,
        height: 180,
        child: WatchedIndicator(item: _watched(), size: size ?? WatchedIndicatorSize.standard),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true),
          home: Center(child: look ? LibraryPhoneLook(child: indicator) : indicator),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('sits in a dark plate flush with the poster corner', (tester) async {
      await pump(tester, look: true);
      final plate = find.byKey(const ValueKey('library.watched_plate'));
      expect(plate, findsOneWidget);
      final poster = tester.getRect(find.byType(WatchedIndicator));
      final rect = tester.getRect(plate);
      expect(rect.topRight, poster.topRight);
      expect(rect.size, const Size.square(LibraryPhoneMetrics.watchedPlateSize));
      final box = tester.widget<Container>(plate).decoration! as BoxDecoration;
      expect(box.color!.computeLuminance(), lessThan(0.05));
    });

    testWidgets('stays dark on the light theme too', (tester) async {
      await tester.runAsync(SettingsService.getInstance);
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: false),
          home: LibraryPhoneLook(child: WatchedIndicator(item: _watched())),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final box =
          tester.widget<Container>(find.byKey(const ValueKey('library.watched_plate'))).decoration! as BoxDecoration;
      expect(box.color!.computeLuminance(), lessThan(0.05));
    });

    testWidgets('outside the look the round tick is unchanged', (tester) async {
      await pump(tester, look: false);
      expect(find.byKey(const ValueKey('library.watched_plate')), findsNothing);
    });

    testWidgets('a compact thumbnail keeps the round tick', (tester) async {
      await pump(tester, look: true, size: WatchedIndicatorSize.compact);
      expect(find.byKey(const ValueKey('library.watched_plate')), findsNothing);
    });
  });
}
