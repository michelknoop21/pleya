import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focus_theme.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_catalog_header_bar.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';
import 'package:pleya/widgets/tv/tv_unified_media_card.dart';
import 'package:pleya/widgets/tv/tv_unified_media_grid.dart';

import '../../test_helpers/golden.dart';

/// CAT10: waar de focusring van de eerste rij staat ten opzichte van het
/// **scherm**, niet ten opzichte van het scrollgebied.
///
/// `tv_unified_media_grid_test.dart` bewaakt de tweede vraag en beantwoordt hem
/// met gelijkheid: `ring.top == viewport.top`, de ring raakt de rand van zijn
/// eigen scrollgebied precies. Dat is de bedoeling van
/// [TvCatalogGrid.scrollPadding], die de groei van een gefocuste kaart aan de
/// bovenkant reserveert en verder niets.
///
/// Wat die padding aan de bovenkant *niet* reserveert is de overscanband. Onder
/// de laatste rij staat hij er wel (`bottomSafeMargin + growth`), boven de
/// eerste niet (alleen `growth`), en [TvCatalogLayout.bottomSafeInset] schrijft
/// op waarom dat mag: aan de bovenkant betaalt de paginakop de marge. Deze test
/// is de controle op dat argument. Hij meet de ring tegen hoofdstuk 8.1's band
/// — "geen tekst of focusring binnen de buitenste 56 pixels" — met de echte kop
/// erboven, en hij doet dat nadat de afstandsbediening de pagina heeft laten
/// scrollen, want dat is het geval waarin de kop niet meer boven de eerste rij
/// staat.
UnifiedMediaGroup _group(int index) {
  final item = MediaItem(
    id: 'i$index',
    backend: MediaBackend.jellyfin,
    kind: MediaKind.movie,
    title: 'Title $index',
    thumbPath: 'https://jf.test/Items/$index/Images/Primary',
    serverId: 'nas',
    serverName: 'NAS',
  );
  final source = UnifiedMediaSource.fromItem(item);
  return UnifiedMediaGroup(
    groupId: 'g$index',
    identity: CanonicalMediaIdentity.movie(title: 'Title $index', year: 2010),
    sources: [source],
    representativeSourceKey: source.sourceKey,
    watchState: UnifiedWatchState(representativeSourceKey: source.sourceKey, isWatched: false),
  );
}

void main() {
  setUpAll(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));

  /// The page as `TvUnifiedCatalogScreen` lays it out: the real heading, and the
  /// grid filling what is left. The screen itself needs a live
  /// `UnifiedCatalogProvider`; this is the geometry of it, which is all the
  /// question is about.
  Future<void> pumpPage(WidgetTester tester, {required Size surfaceSize, int count = 40}) async {
    setGoldenSurfaceSize(tester, size: surfaceSize);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: InputModeTracker(
            child: Scaffold(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TvCatalogHeaderBar(title: t.unifiedCatalog.moviesTitle),
                  Expanded(
                    child: TvUnifiedMediaGrid(
                      groups: [for (var i = 0; i < count; i++) _group(i)],
                      onActivate: (_) {},
                      hasMore: false,
                      isLoadingMore: false,
                      onLoadMore: () {},
                      precache: (request, context) async {},
                    ),
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

  /// The scroll viewport, which is what actually clips: it begins under the
  /// heading, not at the top of the screen.
  Rect viewportOf(WidgetTester tester) => tester.getRect(
    find.descendant(of: find.byType(TvUnifiedMediaGrid), matching: find.byType(SingleChildScrollView)),
  );

  Rect ringOf(WidgetTester tester, String title) {
    final card = find.ancestor(of: find.text(title), matching: find.byType(TvUnifiedMediaCard));
    return tester.getRect(find.descendant(of: card, matching: find.byType(AnimatedContainer)).first);
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  /// Hoofdstuk 8.1's band, converted the way every other box measurement in
  /// `tv_unified_layout.dart` converts: as a fraction of the viewport, so it
  /// means the same thing on any canvas.
  double band(Size surface) => surface.height * (TvCatalogLayout.topSafeInset / 1080);

  group('CAT10', () {
    for (final surface in const [Size(1038, 584), Size(1280, 918)]) {
      testWidgets('the first row\'s ring clears the top overscan band at $surface', (tester) async {
        await pumpPage(tester, surfaceSize: surface);

        Focus.of(tester.element(find.text('Title 0'))).requestFocus();
        await tester.pumpAndSettle();

        expect(
          ringOf(tester, 'Title 0').top,
          greaterThanOrEqualTo(band(surface)),
          reason: 'at rest, with the heading above it',
        );
      });

      testWidgets('and still clears it after the remote has scrolled the page at $surface', (tester) async {
        await pumpPage(tester, surfaceSize: surface);

        Focus.of(tester.element(find.text('Title 0'))).requestFocus();
        await tester.pumpAndSettle();
        await press(tester, LogicalKeyboardKey.arrowDown);
        await press(tester, LogicalKeyboardKey.arrowUp);

        final ring = ringOf(tester, 'Title 0');
        final viewport = viewportOf(tester);
        expect(
          ring.top,
          greaterThanOrEqualTo(viewport.top),
          reason:
              'the ring is drawn at ${ring.top} and the scroll viewport clips at ${viewport.top}, '
              'so ${viewport.top - ring.top} logical pixels of it are cut off. That number is the '
              'headroom itself: traversal parked the resting box on the edge and scrolled the '
              'reservation out from under the ring',
        );
        expect(
          ring.top,
          greaterThanOrEqualTo(band(surface)),
          reason: 'and the whole of it stays out of hoofdstuk 8.1\'s overscan band',
        );
      });
    }

    testWidgets('and the bottom edge holds while walking down', (tester) async {
      // CAT8 from the same mechanism, at the other end: `keepVisibleAtEnd` puts
      // the resting box against the bottom of the viewport, so the growth below
      // it is what falls outside. The register has CAT8 open with its cause
      // unconfirmed; this is the measurement it asked for.
      const surface = Size(1038, 584);
      await pumpPage(tester, surfaceSize: surface, count: 60);

      Focus.of(tester.element(find.text('Title 0'))).requestFocus();
      await tester.pumpAndSettle();

      final columns = TvCatalogGrid.forWidth(
        surface.width,
        scale: TvLayoutConstants.scaleOf(tester.element(find.byType(TvUnifiedMediaGrid))),
      ).columns;

      for (var row = 1; row * columns < 60; row++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
        final title = 'Title ${row * columns}';
        if (find.text(title).evaluate().isEmpty) continue;
        final ring = ringOf(tester, title);
        final viewport = viewportOf(tester);
        expect(
          ring.bottom,
          lessThanOrEqualTo(viewport.bottom),
          reason: 'row $row: ${ring.bottom - viewport.bottom} logical pixels clipped at the bottom',
        );
      }
    });
  });
}
