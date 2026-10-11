/// The Light band outside the white ring is as wide as the ring (2.5 px),
/// where it used to be 1 px. It reserves no layout, so wherever a ring already
/// sat close to a clip, the wider band could be cut off and leave a white ring
/// on a light page with nothing around it.
///
/// This walks the places that sit closest to a clip, in the light theme on an
/// Apple TV canvas, and reads the painted pixels on all four sides of the
/// focused control: a tile in a discovery rail (a clipping `ListView`), the
/// first card of the catalog grid, the first and last settings row inside the
/// card's clip (where the band sits inside the row instead), a chip in a
/// single-line chip bar, and the hero's call to action.
///
/// With `PLEYA_SHOT_DIR` set, every frame is kept as an image.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/focus/card_focus_scope.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/focus/focus_theme.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/setting_tile.dart';
import 'package:pleya/widgets/settings_section.dart';
import 'package:pleya/widgets/tv/tv_catalog_card.dart';
import 'package:pleya/widgets/tv/tv_discovery_rail.dart';
import 'package:pleya/widgets/tv/tv_hero_billboard_carousel.dart';
import 'package:pleya/widgets/tv/tv_page_chip_bar.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';
import 'package:pleya/widgets/tv/tv_unified_media_grid.dart';

import '../test_helpers/focus_band.dart';
import '../test_helpers/golden.dart';
import '../test_helpers/prefs.dart';
import '../test_helpers/tv_discovery_artwork.dart';
import '../test_helpers/tv_discovery_fixtures.dart';

const _shot = ValueKey('shot');

const _sides = [AxisDirection.up, AxisDirection.right, AxisDirection.down, AxisDirection.left];

/// The thickness a focus indicator has to hold 3:1 over (WCAG 2.2, 2.4.13).
const _minThickness = 2.0;

final _light = monoTheme(dark: false);

UnifiedMediaGroup _film(int index) {
  final item = MediaItem(
    id: 'f$index',
    backend: MediaBackend.jellyfin,
    kind: MediaKind.movie,
    title: 'Film $index',
    year: 2024,
    summary: 'Film $index has a synopsis long enough to fill the hero block.',
    durationMs: 100 * 60 * 1000,
    serverId: 'nas',
    serverName: 'NAS',
  );
  final source = UnifiedMediaSource.fromItem(item);
  return UnifiedMediaGroup(
    groupId: 'f$index',
    identity: CanonicalMediaIdentity.movie(title: 'Film $index', year: 2024),
    sources: [source],
    representativeSourceKey: source.sourceKey,
    watchState: UnifiedWatchState(representativeSourceKey: source.sourceKey, isWatched: false),
  );
}

Widget _app(Widget body) => TranslationProvider(
  child: RepaintBoundary(
    key: _shot,
    child: InputModeTracker(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _light,
        home: Scaffold(backgroundColor: _light.extension<MonoTokens>()!.bg, body: body),
      ),
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Reads all four sides of [box] and asserts the band holds on each.
Future<void> _expectBand(
  WidgetTester tester,
  String scene,
  Rect box, {
  double outside = 7,
  double inside = 8,
  Set<AxisDirection> sides = const {...AxisDirection.values},
  Map<AxisDirection, double> minThickness = const {},
}) async {
  final frame = await FocusFrame.capture(tester, find.byKey(_shot));
  await frame.keep(tester, 'clip-$scene-light-1920x1080');
  final failures = <String>[];
  for (final side in _sides.where(sides.contains)) {
    final band = frame.band(box, side, outside: outside, inside: inside);
    debugPrint('measure $scene ${side.name}: $band');
    if (band.contrast < 3 || band.thickness < (minThickness[side] ?? _minThickness)) {
      failures.add('${side.name}: $band');
    }
    if (contrastRatio(band.inner, Colors.white) >= 1.05) failures.add('${side.name}: no white ring inside the band');
  }
  expect(failures, isEmpty, reason: scene);
}

void main() {
  setUpAll(() async {
    await loadAppFontsForGoldens();
    TvDiscoveryArtwork.install();
  });
  tearDownAll(TvDiscoveryArtwork.remove);

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    TvDetectionService.debugSetAppleTVOverride(true);
  });

  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  /// Apple TV: 1920x1080 laid out at 1.85 (DEC-028).
  void tv(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.85;
    addTearDown(tester.view.reset);
  }

  testWidgets('a tile in a discovery rail, first and further along', (tester) async {
    tv(tester);
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: TvDiscoveryLayout.railSectionHeight(TvLayoutConstants.scaleOf(context)),
              child: TvDiscoveryRail(title: 'Films', groups: tvDiscoveryFilmsRow(), onActivate: (_) {}),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);

    Rect focusedArtwork() {
      final focused = find.byWidgetPredicate((w) => w is CardFocusBorder).evaluate().where((e) {
        return CardFocusScope.maybeOf(e) ?? false;
      });
      expect(focused, hasLength(1), reason: 'one focused tile');
      return tester.getRect(find.byElementPredicate((e) => e == focused.single));
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    final first = FocusManager.instance.rootScope.descendants.firstWhere(
      (n) => n.debugLabel?.startsWith('tvDiscoveryTile_') ?? false,
    );
    first.requestFocus();
    await _settle(tester);
    // The rail's viewport leaves `cardFocusRingGap * scale` (4.25 px on the
    // Apple TV canvas) between a focused tile's artwork and its top and bottom
    // clip. The ring takes 2.5 of that, so about 1.6 px of band shows there (3 device pixels at 1080p): full
    // ink, where the old line was 1 px at 55%. Growing the rail's band height
    // for the rest would move every rail on the landing, so it is left alone.
    const railClip = {AxisDirection.up: 1.5, AxisDirection.down: 1.5};
    await _expectBand(tester, 'rail-first-tile', focusedArtwork(), minThickness: railClip);

    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _settle(tester);
    }
    await _expectBand(tester, 'rail-fourth-tile', focusedArtwork(), minThickness: railClip);
  });

  testWidgets('the first card of the catalog grid', (tester) async {
    tv(tester);
    await tester.pumpWidget(
      _app(
        // Below a header, as on the catalog page, so the grid's own viewport
        // clip is the edge the band has to clear, not the screen's.
        Column(
          children: [
            const SizedBox(height: 80),
            Expanded(
              child: TvUnifiedMediaGrid(
                groups: [for (var i = 0; i < 24; i++) _film(i)],
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
    );
    await _settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    Focus.of(tester.element(find.text('Film 0'))).requestFocus();
    await _settle(tester);

    // The ring is drawn inside the card's outer bounds; the band outside them.
    final card = find.ancestor(of: find.text('Film 0'), matching: find.byType(TvCatalogCard));
    final poster = tester.getRect(find.descendant(of: card, matching: find.byKey(tvCatalogPosterKey)));
    final scale = TvLayoutConstants.scaleOf(tester.element(card));
    await _expectBand(
      tester,
      'grid-first-card',
      poster.inflate(TvCatalogLayout.cardContentInset(scale)),
      // Not the bottom, where the card's footer is. Not the top either: the
      // grid's viewport cuts the first row's focused card through its ring,
      // white part included, on main as well as here. That is the grid's
      // scroll padding against the 1.06 focus scale, not the band, and it is
      // tracked as its own finding.
      sides: {AxisDirection.left, AxisDirection.right},
    );
  });

  for (final (label, index) in [('first', 0), ('last', 2)]) {
    testWidgets('the $label settings row inside the card clip', (tester) async {
      tv(tester);
      final nodes = [for (var i = 0; i < 3; i++) FocusNode()];
      addTearDown(() {
        for (final n in nodes) {
          n.dispose();
        }
      });
      await tester.pumpWidget(
        _app(
          Padding(
            padding: const EdgeInsets.all(40),
            child: SettingsGroup(
              children: [
                for (var i = 0; i < 3; i++)
                  SettingNavigationTile(
                    icon: Symbols.settings_rounded,
                    title: 'Rij $i',
                    subtitle: 'Uitleg bij rij $i',
                    focusNode: nodes[i],
                    onTap: () {},
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      nodes[index].requestFocus();
      await _settle(tester);

      final row = tester.getRect(find.byType(SettingRowFocus).at(index));
      // The band is the row's outer 2.5 px here, inside the card's clip; the
      // white ring is inside it.
      await _expectBand(tester, 'settings-$label-row', row, outside: 6);

      // And the ring, now 2.5 to 5 px in from the row's edge, stays clear of
      // what the row says.
      final reach = FocusTheme.focusBorderWidth * 2;
      for (final content in [find.text('Rij $index'), find.text('Uitleg bij rij $index'), find.byType(Icon)]) {
        for (final element in content.evaluate()) {
          final rect = tester.getRect(find.byElementPredicate((e) => e == element));
          if (!row.overlaps(rect)) continue;
          expect(rect.top - row.top, greaterThan(reach), reason: '$content against the top of the ring');
          expect(row.bottom - rect.bottom, greaterThan(reach), reason: '$content against the bottom');
          expect(rect.left - row.left, greaterThan(reach), reason: '$content against the left');
          expect(row.right - rect.right, greaterThan(reach), reason: '$content against the right');
        }
      }
    });
  }

  testWidgets('a chip in a single-line chip bar', (tester) async {
    tv(tester);
    final nodes = FocusMemoryTracker(debugLabelPrefix: 'test');
    addTearDown(nodes.dispose);
    await tester.pumpWidget(
      _app(
        Padding(
          padding: const EdgeInsets.all(40),
          child: Align(
            alignment: Alignment.topLeft,
            // Narrower than the chips, so the bar scrolls and its viewport clips,
            // as on a library page with more libraries than fit.
            child: SizedBox(
              width: 420,
              child: TvPageChipBar(
                singleLine: true,
                nodes: nodes,
                chips: [
                  for (final (i, label) in ['Films', 'Series', 'Documentaires', 'Concerten'].indexed)
                    TvPageChip(key: 'c$i', label: label, selected: i == 0, onSelect: () {}),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    nodes.get('c1').requestFocus();
    await _settle(tester);

    final chip = find.ancestor(of: find.text('Series'), matching: find.byType(FocusableWrapper)).first;
    await _expectBand(tester, 'chipbar-chip', tester.getRect(chip), outside: 5);
  });

  testWidgets('the hero call to action', (tester) async {
    tv(tester);
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            final size = Size(MediaQuery.sizeOf(context).width, 308);
            return Align(
              alignment: Alignment.topLeft,
              child: SizedBox.fromSize(
                size: size,
                child: TvHeroBillboardCarousel(
                  groups: [_film(0), _film(1)],
                  size: size,
                  autoplayEnabled: false,
                  hideSpoilers: false,
                  onActivate: (group, {required intent, required playDirectly}) {},
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    tester
        .widgetList<Focus>(find.byType(Focus))
        .map((f) => f.focusNode)
        .whereType<FocusNode>()
        .firstWhere((n) => n.debugLabel == 'tvHeroMoreInfo')
        .requestFocus();
    await _settle(tester);

    // The ring stands a clear gap outside the fill; scan from just past the
    // band. Not on the left: there the band runs up to the Play button, which
    // is a neighbour, not a clip.
    final fill = tester.getRect(find.byKey(const ValueKey('tvHeroCta.info.fill')));
    await _expectBand(
      tester,
      'hero-cta',
      fill,
      outside: 10,
      inside: 2,
      sides: {AxisDirection.up, AxisDirection.right, AxisDirection.down},
    );
  });
}
