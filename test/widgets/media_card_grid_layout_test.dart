import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focus_theme.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/media_card.dart';
import 'package:pleya/widgets/media_card_metrics.dart';
import 'package:pleya/widgets/media_grid_delegate.dart';

import '../test_helpers/prefs.dart';

/// The grid used to size cells by one aspect ratio for poster plus caption.
/// The caption does not shrink with the column, so a narrow column pushed the
/// metadata line out of its own cell and into the row below. These tests pin
/// the measured layout that replaced it, and the gap that keeps a focused card
/// off its neighbour.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  testWidgets('cell height is padding plus poster plus caption', (tester) async {
    late double cellHeight;
    late double captionHeight;
    await tester.pumpWidget(
      _TestApp(
        child: Builder(
          builder: (context) {
            captionHeight = MediaCardMetrics.captionHeight(context);
            cellHeight = MediaCardMetrics.cellHeight(
              context,
              200,
              imageAspectRatio: GridLayoutConstants.fullCardPosterAspectRatio,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    // 200 wide, minus 3 padding on each side, at 2:3 gives a 291-high poster.
    const posterHeight = (200 - 6) * 1.5;
    expect(
      cellHeight,
      moreOrLessEquals(
        MediaCardMetrics.cardPadding.vertical + posterHeight + MediaCardMetrics.captionGap + captionHeight,
      ),
    );
  });

  testWidgets('caption height follows the OS text scale', (tester) async {
    late double plain;
    late double scaled;
    await tester.pumpWidget(
      _TestApp(
        child: Builder(
          builder: (context) {
            plain = MediaCardMetrics.captionHeight(context);
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: Builder(
                builder: (context) {
                  scaled = MediaCardMetrics.captionHeight(context);
                  return const SizedBox.shrink();
                },
              ),
            );
          },
        ),
      ),
    );

    expect(scaled, moreOrLessEquals(plain * 1.5));
  });

  test('grid spacing is a real gap', () {
    expect(GridLayoutConstants.posterGridSpacingForScale(0.85), greaterThan(0));
  });

  test('a focused card grows into its cell, not into the gap', () {
    // The inset is what keeps the distance between two cards the same wherever
    // focus lands: at [FocusTheme.focusScale] the card ends up filling the cell
    // it was handed, and never a pixel of the spacing beside it.
    for (final cellWidth in <double>[100, 148, 220, 280]) {
      final inset = MediaCardMetrics.focusInset(cellWidth);
      final grown = (cellWidth - inset * 2) * FocusTheme.focusScale;
      expect(grown, lessThanOrEqualTo(cellWidth + 0.001), reason: 'cell $cellWidth overflows its own bounds');
    }
  });

  testWidgets('title and year fit inside a cell of the height the grid reserves', (tester) async {
    final item = MediaItem(
      id: 'movie_1',
      backend: MediaBackend.plex,
      kind: MediaKind.movie,
      title: 'A title long enough that it has to be cut off with an ellipsis somewhere',
      year: 2017,
    );

    // A narrow column: the case that used to push the year out of the cell.
    const cellWidth = 120.0;
    late double cellHeight;

    await tester.pumpWidget(
      _TestApp(
        child: Builder(
          builder: (context) {
            final inset = MediaCardMetrics.focusInset(cellWidth);
            cellHeight = MediaCardMetrics.cellHeight(
              context,
              cellWidth,
              imageAspectRatio: GridLayoutConstants.fullCardPosterAspectRatio,
              focusInset: inset,
            );
            return SizedBox(
              width: cellWidth,
              height: cellHeight,
              child: Padding(
                padding: EdgeInsets.all(inset),
                child: MediaCard(item: item, forceGridMode: true, isOffline: true),
              ),
            );
          },
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('2017'), findsOneWidget);

    final card = tester.getRect(find.byType(MediaCard));
    final year = tester.getRect(find.text('2017'));
    expect(year.bottom, lessThanOrEqualTo(card.bottom));
  });

  testWidgets('grid geometry reserves the measured cell height', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    late MediaGridGeometry geometry;
    late double expectedHeight;
    await tester.pumpWidget(
      _TestApp(
        child: Builder(
          builder: (context) {
            geometry = MediaGridGeometry.resolve(
              context: context,
              crossAxisExtent: 1200,
              density: LibraryDensity.defaultValue,
            );
            expectedHeight = MediaCardMetrics.cellHeight(
              context,
              geometry.itemWidth,
              imageAspectRatio: GridLayoutConstants.fullCardPosterAspectRatio,
              focusInset: geometry.cellInset,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(geometry.spacing, greaterThan(0));
    expect(geometry.cellInset, moreOrLessEquals(MediaCardMetrics.focusInset(geometry.itemWidth)));
    expect(geometry.delegate.crossAxisSpacing, geometry.spacing);
    expect(geometry.delegate.mainAxisSpacing, geometry.spacing);
    expect(geometry.delegate.mainAxisExtent, moreOrLessEquals(expectedHeight));
    expect(geometry.itemHeight, moreOrLessEquals(expectedHeight));
  });
}

class _TestApp extends StatelessWidget {
  final Widget child;

  const _TestApp({required this.child});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: monoTheme(dark: true),
      home: Scaffold(body: Center(child: child)),
    );
  }
}
