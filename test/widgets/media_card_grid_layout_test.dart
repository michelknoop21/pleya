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
import 'package:pleya/widgets/media_card_grid_layout.dart';
import 'package:pleya/widgets/media_grid_delegate.dart';

import '../test_helpers/prefs.dart';

/// Pins the arithmetic so a later change to a font size or an inset breaks
/// here, in one line, instead of on a television.
void main() {
  Future<BuildContext> pumpContext(WidgetTester tester, {TextScaler? textScaler}) async {
    late BuildContext captured;
    Widget child = Builder(
      builder: (context) {
        captured = context;
        return const SizedBox.shrink();
      },
    );
    if (textScaler != null) {
      child = MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: child,
      );
    }
    await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: child));
    return captured;
  }

  test('the poster is 2:3 measured on the poster, not on the cell', () {
    expect(MediaCardGridLayout.posterWidthFor(120), 114);
    expect(MediaCardGridLayout.posterHeightFor(120), 171);
    expect(MediaCardGridLayout.posterHeightFor(120) / MediaCardGridLayout.posterWidthFor(120), closeTo(1.5, 0.001));
  });

  testWidgets('the caption reserve covers one title line plus one subtitle line', (tester) async {
    final context = await pumpContext(tester, textScaler: TextScaler.noScaling);

    // 13 * 1.1 + 11 * 1.1 = 26.4, rounded up so the box is never short.
    expect(MediaCardGridLayout.captionExtentFor(context), 27);
    // 3 top + 2 gap + 27 caption + 1 bottom.
    expect(MediaCardGridLayout.textExtentFor(context), 33);
    expect(MediaCardGridLayout.cardHeightFor(context, 120), 171 + 33);
  });

  testWidgets('the reserve grows with the system text size', (tester) async {
    final context = await pumpContext(tester, textScaler: const TextScaler.linear(2));

    // The poster is fixed, so unlike the app's other grids the caption cannot
    // borrow height from it. If the reserve did not scale, a large text
    // setting would put the caption back on the row below.
    expect(MediaCardGridLayout.captionExtentFor(context), 53);
    expect(MediaCardGridLayout.cardHeightFor(context, 120), 171 + 59);
  });

  testWidgets('the card height is exactly the poster plus the text reserve', (tester) async {
    final context = await pumpContext(tester);

    for (final width in [104.0, 120.0, 187.5]) {
      expect(
        MediaCardGridLayout.cardHeightFor(context, width),
        MediaCardGridLayout.posterHeightFor(width) + MediaCardGridLayout.textExtentFor(context),
      );
    }
  });

  // ============================================================
  // What a grid cell reserves: the same arithmetic, plus the room a focused
  // card grows into and the artwork's own aspect.
  // ============================================================

  test('grid spacing is a real gap', () {
    expect(GridLayoutConstants.posterGridSpacingForScale(0.85), greaterThan(0));
  });

  test('a focused card grows into its cell, not into the gap', () {
    // The inset is what keeps the distance between two cards the same wherever
    // focus lands: at [FocusTheme.focusScale] the card ends up filling the cell
    // it was handed, and never a pixel of the spacing beside it.
    for (final cellWidth in <double>[100, 148, 220, 280]) {
      final inset = MediaCardGridLayout.focusInsetFor(cellWidth);
      final grown = (cellWidth - inset * 2) * FocusTheme.focusScale;
      expect(grown, lessThanOrEqualTo(cellWidth + 0.001), reason: 'cell $cellWidth overflows its own bounds');
    }
  });

  testWidgets('a cell reserves the focus room on top of poster and caption', (tester) async {
    final context = await pumpContext(tester, textScaler: TextScaler.noScaling);
    const cellWidth = 200.0;
    final inset = MediaCardGridLayout.focusInsetFor(cellWidth);

    expect(
      MediaCardGridLayout.cellHeightFor(
        context,
        cellWidth,
        imageAspectRatio: GridLayoutConstants.fullCardPosterAspectRatio,
        focusInset: inset,
      ),
      moreOrLessEquals(
        inset * 2 +
            MediaCardGridLayout.posterWidthFor(cellWidth, focusInset: inset) * 1.5 +
            MediaCardGridLayout.textExtentFor(context),
      ),
    );
  });

  group('in a grid', () {
    setUp(() async {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      await SettingsService.getInstance();
    });

    tearDown(() {
      TvDetectionService.debugSetAppleTVOverride(null);
    });

    testWidgets('title and year fit inside the cell the grid reserves', (tester) async {
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
              final inset = MediaCardGridLayout.focusInsetFor(cellWidth);
              cellHeight = MediaCardGridLayout.cellHeightFor(
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

    testWidgets('the geometry hands the delegate the measured cell height', (tester) async {
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
              expectedHeight = MediaCardGridLayout.cellHeightFor(
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
      expect(geometry.cellInset, moreOrLessEquals(MediaCardGridLayout.focusInsetFor(geometry.itemWidth)));
      expect(geometry.delegate.crossAxisSpacing, geometry.spacing);
      expect(geometry.delegate.mainAxisSpacing, geometry.spacing);
      expect(geometry.delegate.mainAxisExtent, moreOrLessEquals(expectedHeight));
      expect(geometry.itemHeight, moreOrLessEquals(expectedHeight));
    });
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
