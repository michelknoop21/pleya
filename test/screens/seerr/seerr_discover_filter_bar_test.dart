import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/widgets/library_header_bar.dart';
import 'package:pleya/screens/seerr/seerr_discover_filter_bar.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/focusable_filter_chip.dart';
import 'package:pleya/widgets/focusable_tab_chip.dart';
import 'package:pleya/widgets/overlay_sheet.dart';

/// The discover filter bar used to be a Wrap of outlined pills over a 52px strip
/// of more outlined pills. These tests hold the replacement to the library
/// header's vocabulary — one 42px line, underline tabs, genres behind a header
/// action — and to a bar that stays out of the way of the posters.
void main() {
  setUp(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  const genres = <SeerrDiscoverGenre>[
    (id: 28, name: 'Action & Adventure'),
    (id: 16, name: 'Animation'),
    (id: 99, name: 'Documentary'),
    (id: 18, name: 'Drama'),
    (id: 878, name: 'Science Fiction'),
  ];

  Widget host({
    SeerrDiscoverType type = SeerrDiscoverType.all,
    List<SeerrDiscoverGenre> genreList = const [],
    int? genreId,
    ValueChanged<SeerrDiscoverType>? onTypeSelected,
    ValueChanged<int?>? onGenreSelected,
    Size size = const Size(390, 844),
    double textScale = 1.0,
  }) {
    return MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
      child: MaterialApp(
        theme: monoTheme(dark: true),
        home: OverlaySheetHost(
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SeerrDiscoverFilterBar(
                type: type,
                genres: genreList,
                genreId: genreId,
                onTypeSelected: onTypeSelected ?? (_) {},
                onGenreSelected: onGenreSelected ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the bar is a library header line, not a strip of pills', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.byType(LibraryHeaderBar), findsOneWidget);
    expect(find.byType(FocusableFilterChip), findsNothing, reason: 'the outlined pills are gone');
    for (final chip in tester.widgetList<FocusableTabChip>(find.byType(FocusableTabChip))) {
      expect(chip.style, TabChipStyle.underline, reason: 'same tab as Aanbevolen/Bladeren on a library page');
    }
    expect(find.text(t.seerr.filterAll), findsOneWidget);
    expect(find.text(t.seerr.filterMovies), findsOneWidget);
    expect(find.text(t.seerr.filterShows), findsOneWidget);
  });

  testWidgets('each tab reports itself, including All', (tester) async {
    final picked = <SeerrDiscoverType>[];
    await tester.pumpWidget(host(type: SeerrDiscoverType.movies, onTypeSelected: picked.add));
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.seerr.filterMovies));
    await tester.tap(find.text(t.seerr.filterShows));
    await tester.tap(find.text(t.seerr.filterAll));
    await tester.pumpAndSettle();

    expect(picked, [SeerrDiscoverType.movies, SeerrDiscoverType.tv, SeerrDiscoverType.all]);
  });

  group('genre action', () {
    testWidgets('appears only once a type narrows the view and genres exist', (tester) async {
      final label = t.libraries.filterCategories.genre;

      await tester.pumpWidget(host(type: SeerrDiscoverType.all, genreList: genres));
      await tester.pumpAndSettle();
      expect(find.text(label), findsNothing, reason: 'no single genre list applies to All');

      await tester.pumpWidget(host(type: SeerrDiscoverType.movies));
      await tester.pumpAndSettle();
      expect(find.text(label), findsNothing, reason: 'no genres loaded yet');

      await tester.pumpWidget(host(type: SeerrDiscoverType.movies, genreList: genres));
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
    });

    testWidgets('shows the active genre next to its label', (tester) async {
      await tester.pumpWidget(host(type: SeerrDiscoverType.movies, genreList: genres, genreId: 16));
      await tester.pumpAndSettle();

      expect(find.text('Animation'), findsOneWidget, reason: 'the pick is readable without opening the panel');
    });

    testWidgets('opens a panel and reports the picked genre', (tester) async {
      int? picked = -1;
      await tester.pumpWidget(
        host(type: SeerrDiscoverType.movies, genreList: genres, onGenreSelected: (id) => picked = id),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(t.libraries.filterCategories.genre));
      await tester.pumpAndSettle();
      expect(find.text('Documentary'), findsOneWidget, reason: 'panel lists the genres');

      await tester.tap(find.text('Documentary'));
      await tester.pumpAndSettle();

      expect(picked, 99);
      expect(find.text('Science Fiction'), findsNothing, reason: 'panel closed after picking');
    });

    testWidgets('the first row clears the genre', (tester) async {
      int? picked = -1;
      await tester.pumpWidget(
        host(type: SeerrDiscoverType.movies, genreList: genres, genreId: 99, onGenreSelected: (id) => picked = id),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(t.libraries.filterCategories.genre));
      await tester.pumpAndSettle();
      // "All" is also a type tab; scope to the panel's list.
      await tester.tap(find.descendant(of: find.byType(ListView), matching: find.text(t.libraries.all)));
      await tester.pumpAndSettle();

      expect(picked, isNull);
    });
  });

  testWidgets('the bar stays one compact line and does not overflow a phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(type: SeerrDiscoverType.movies, genreList: genres));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The pill version measured 92 here for the same controls (40 for the type
    // row, 52 for the genre strip). A bound, not a pixel: it guards the order of
    // magnitude, not the font metrics.
    expect(tester.getSize(find.byType(SeerrDiscoverFilterBar)).height, lessThan(50));
  });

  testWidgets('a 1.5x system text size neither overflows nor breaks the controls', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final picked = <SeerrDiscoverType>[];
    int? genrePick = -1;
    await tester.pumpWidget(
      host(
        type: SeerrDiscoverType.movies,
        genreList: genres,
        textScale: 1.5,
        onTypeSelected: picked.add,
        onGenreSelected: (id) => genrePick = id,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow at 1.5x');

    // At 1.5x the third tab sits past the edge of the strip; scroll it in the
    // way a user would before tapping it.
    await tester.ensureVisible(find.text(t.seerr.filterShows));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.seerr.filterShows));
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.libraries.filterCategories.genre));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drama'));
    await tester.pumpAndSettle();

    expect(picked, [SeerrDiscoverType.tv]);
    expect(genrePick, 18);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the tab row scrolls horizontally when the labels run past the edge', (tester) async {
    tester.view.physicalSize = const Size(260, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(type: SeerrDiscoverType.movies, genreList: genres, size: const Size(260, 844)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'the tabs scroll instead of overflowing');
    final before = tester.getTopLeft(find.text(t.seerr.filterAll)).dx;
    await tester.drag(find.text(t.seerr.filterAll), const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text(t.seerr.filterAll)).dx, lessThan(before));
  });
}
