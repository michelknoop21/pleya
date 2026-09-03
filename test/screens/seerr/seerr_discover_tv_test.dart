/// P7: Aanvragen on TV, at the four places it actually differed from every
/// other 10-foot surface.
///
/// The report described a screen with its own `Scaffold` and `SliverAppBar`
/// over the shell. That part is genuinely no longer true — `505e8cc` and
/// `f8c7d47` moved it onto the shared `FocusedScrollScaffold`, whose app bar is
/// already `ExcludeFocus` on TV — and nothing here re-solves it. What was left,
/// and is fixed:
///
///  * a full-width divider under the filter bar that exists on no other TV
///    screen, from a flag whose own doc says it is meant to be off there;
///  * a hardcoded `fontSize: 26` that never went through the scale clamp;
///  * three different left margins on one page, the worst of them 8 logical
///    pixels — 64 to the left of the search field above it, and inside the
///    overscan band;
///  * two inbox buttons, one of them unreachable, and no directional exit out
///    of the results grid at all.
///
/// These run against the components rather than the whole screen: mounting
/// `SeerrDiscoverScreen` needs a live `SeerrProvider` session, and the provider
/// has no test seam for one. Adding it is not this round's change, so the two
/// screen-level rules are asserted through the named functions the screen calls
/// — `seerrDiscoverAppBarActions` and `seerrRowHeaderStyle` — rather than
/// through a copy of them.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/models/seerr/seerr_media.dart';
import 'package:pleya/screens/seerr/seerr_discover_filter_bar.dart';
import 'package:pleya/screens/seerr/seerr_discover_screen.dart';
import 'package:pleya/screens/seerr/seerr_grid_sliver.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/library_header_bar.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/seerr_poster_card.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

import '../../test_helpers/prefs.dart';

const Size _canvas = Size(1038, 584);

SeerrMedia _media(int index) => SeerrMedia(tmdbId: index, mediaType: 'movie', title: 'Title $index');

void main() {
  setUp(() async {
    // `buildSeerrGridSliver` reads `SettingsService.libraryDensity` through a
    // `SettingsBuilder`, which throws on an uninitialised service.
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  group('on TV', () {
    setUp(() => TvDetectionService.debugSetAppleTVOverride(true));
    tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

    Future<void> pumpGrid(
      WidgetTester tester, {
      int count = 12,
      VoidCallback? onExitLeft,
      VoidCallback? onExitTop,
      FocusNode? firstItemFocusNode,
    }) async {
      tester.view.physicalSize = _canvas;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: InputModeTracker(
              child: Scaffold(
                body: CustomScrollView(
                  slivers: [
                    buildSeerrGridSliver(
                      items: [for (var i = 0; i < count; i++) _media(i)],
                      onTap: (_) {},
                      firstItemFocusNode: firstItemFocusNode,
                      onExitLeft: onExitLeft,
                      onExitTop: onExitTop,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the filter bar draws no divider', (tester) async {
      // `showDivider`'s own doc: "Off for the TV backdrop, where a rule would
      // cut across the artwork." This call site never set it, so it took the
      // `true` default — `libraries_screen` passes `false` for the same reason.
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: OverlaySheetHost(
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topCenter,
                  child: SeerrDiscoverFilterBar(
                    type: SeerrDiscoverType.all,
                    genres: const [],
                    genreId: null,
                    onTypeSelected: (_) {},
                    onGenreSelected: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bar = tester.widget<LibraryHeaderBar>(find.byType(LibraryHeaderBar));
      expect(bar.showDivider, isFalse);
    });

    testWidgets('the results grid sits on the same left margin as the page above it', (tester) async {
      await pumpGrid(tester);

      final first = tester.getRect(find.byType(SeerrPosterCard).first);
      expect(
        first.left,
        closeTo(TvLayoutConstants.horizontalInset, 0.5),
        reason: 'it used to start at 8 — 64 logical pixels left of the search field, inside the overscan band',
      );
    });

    /// The card's own focus node — a descendant of the card, not an ancestor,
    /// so `Focus.of(cardContext)` looks in the wrong direction.
    FocusNode nodeOfCard(WidgetTester tester, int index) => tester
        .widget<Focus>(find.descendant(of: find.byType(SeerrPosterCard).at(index), matching: find.byType(Focus)).first)
        .focusNode!;

    testWidgets('LEFT off the first column is a guaranteed way out', (tester) async {
      var exits = 0;
      final first = FocusNode(debugLabel: 'seerrFirstCard');
      addTearDown(first.dispose);
      await pumpGrid(tester, onExitLeft: () => exits++, firstItemFocusNode: first);

      first.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      expect(exits, 1, reason: 'the card had no directional callbacks at all, so this fell through to a guess');
    });

    testWidgets('UP off the first row reaches the filter line above', (tester) async {
      var exits = 0;
      final first = FocusNode(debugLabel: 'seerrFirstCard');
      addTearDown(first.dispose);
      await pumpGrid(tester, onExitTop: () => exits++, firstItemFocusNode: first);

      first.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      expect(exits, 1);
    });

    testWidgets('a card in the middle of the grid keeps the default traversal', (tester) async {
      // Only the edges are wired. Inside a uniform grid the geometric policy is
      // right, and overriding it there would be a second traversal model.
      var exits = 0;
      await pumpGrid(tester, onExitLeft: () => exits++, onExitTop: () => exits++);

      nodeOfCard(tester, 1).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      expect(exits, 0);
    });

    testWidgets('the app bar carries no inbox action, because nothing there is reachable', (tester) async {
      expect(
        seerrDiscoverAppBarActions(onOpenRequests: () {}),
        isEmpty,
        reason: 'the focusable one beside the search field is the one that works',
      );
    });

    testWidgets('a shelf heading is sized through the scale clamp, not hardcoded', (tester) async {
      late BuildContext captured;
      tester.view.physicalSize = _canvas;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: Builder(
              builder: (context) {
                captured = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      final style = seerrRowHeaderStyle(captured);
      final expected = TvDiscoveryLayout.sectionTitleFontSize * TvLayoutConstants.scaleOf(captured);
      expect(style!.fontSize, closeTo(expected, 0.01));
      expect(style.fontSize, isNot(26), reason: '26 logical px is ~48 reference px — a size no TV token uses');
    });
  });

  group('off TV nothing changes', () {
    testWidgets('the app bar keeps its inbox action', (tester) async {
      expect(seerrDiscoverAppBarActions(onOpenRequests: () {}), hasLength(1));
    });

    testWidgets('the grid keeps its 8px inset', (tester) async {
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  buildSeerrGridSliver(items: [for (var i = 0; i < 6; i++) _media(i)], onTap: (_) {}),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byType(SeerrPosterCard).first).left, closeTo(8, 0.5));
    });
  });
}
