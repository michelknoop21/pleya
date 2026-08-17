import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv_browse_rail.dart';
import 'package:pleya/widgets/tv_spotlight_background.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';

/// Long enough that the hero has to clip it, so the block is at its tallest.
const _longSummary =
    'Joe and Angela have been married for eleven years, long enough that the '
    'silences between them have their own vocabulary. When the couple from the '
    'apartment upstairs comes down for a dinner party that neither of them '
    'wanted to host, the evening turns into an inventory of everything that was '
    'left unsaid, and by the time the plates are cleared nobody is certain '
    'whether the visit reignited the spark or finally put it out for good.';

const _longTitle = 'The Invite: An Exceptionally Long Feature Title That Refuses To Fit On One Line';

const _railHubTitle = 'Recently added films';
const _secondRailHubTitle = 'Recently released films';

MediaItem _spotlightItem() => MediaItem(
  id: 'movie_hero',
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: _longTitle,
  summary: _longSummary,
  artPath: '/art',
  contentRating: 'nl/12',
  durationMs: 6420000,
  year: 2026,
);

MediaHub _hub(String id, String title) => MediaHub(
  id: id,
  title: title,
  type: 'movie',
  size: 3,
  items: [
    for (var i = 0; i < 3; i++)
      MediaItem(id: '${id}_$i', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Rail movie $i'),
  ],
);

/// Two hubs, like the library on the screenshot: a second one makes the rail
/// reserve a next-hub peek, which is most of what the old peek figure missed.
List<MediaHub> _railHubs() => [_hub('recently_added', _railHubTitle), _hub('recently_released', _secondRailHubTitle)];

/// The composition of `_LibraryRecommendedTabState._buildTvContent`: a hero
/// bounded by [contentTop]/[contentBottom] over a rail docked at bottom 0.
Widget _libraryTvContent({required Size size, required double contentTop, required double contentBottom}) {
  final serverManager = MultiServerManager();
  return ChangeNotifierProvider<MultiServerProvider>(
    create: (_) => MultiServerProvider(serverManager, DataAggregationService(serverManager)),
    child: MaterialApp(
      theme: monoTheme(dark: true),
      home: Scaffold(
        body: SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              TvSpotlightBackground(
                item: _spotlightItem(),
                client: null,
                contentTop: contentTop,
                contentBottom: contentBottom,
                contentLeft: 24,
                compact: true,
                showPrimaryAction: false,
                constrainInfoToAvailableHeight: true,
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: TvBrowseRail(
                  hubs: _railHubs(),
                  iconForHub: (_, _) => Icons.movie_rounded,
                  // Must match what _railHeightFor feeds estimateHeight, the
                  // way the library tab passes the same value to both.
                  tallPosterScale: TvBrowseRailLayout.compactTallPosterScale,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

double _railHeightFor(Size size) => TvBrowseRailLayout.estimateHeight(
  size: size,
  hubs: _railHubs(),
  density: SettingsService.instance.read(SettingsService.libraryDensity),
  episodePosterMode: SettingsService.instance.read(SettingsService.episodePosterMode),
  fullCardLayout: SettingsService.instance.read(SettingsService.tvFullCardLayout),
  tallPosterScale: TvBrowseRailLayout.compactTallPosterScale,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
    LocaleSettings.setLocaleSync(AppLocale.en);
    await SettingsService.getInstance();
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  group('heroBottomInsetForDockedRail', () {
    test('reserves everything the rail occupies except its empty top padding', () {
      for (final size in const [Size(1920, 1080), Size(1280, 720), Size(3840, 2160)]) {
        final scale = TvBrowseRailLayout.scaleForSize(size);
        final railHeight = _railHeightFor(size);
        final inset = TvBrowseRailLayout.heroBottomInsetForDockedRail(
          railHeight: railHeight,
          scale: scale,
          gap: MonoTokens.tvHeroRailGap * scale,
        );

        expect(
          railHeight - inset,
          lessThanOrEqualTo(TvBrowseRailLayout.railTopPaddingForScale(scale) + 0.5),
          reason: 'at $size the hero band reaches into the rail past its top padding',
        );
      }
    });

    test('reserves more than the sliding home screen peek', () {
      // The regression in one line: the peek figure is the smaller of the two,
      // and using it for a docked rail is what put the summary on the row label.
      const size = Size(1920, 1080);
      final scale = TvBrowseRailLayout.scaleForSize(size);
      final railHeight = _railHeightFor(size);
      final peek = TvBrowseRailLayout.firstHubPeekHeight(
        hub: _railHubs().first,
        railSize: size,
        density: SettingsService.instance.read(SettingsService.libraryDensity),
        episodePosterMode: SettingsService.instance.read(SettingsService.episodePosterMode),
        tallPosterScale: TvBrowseRailLayout.compactTallPosterScale,
      );

      expect(
        TvBrowseRailLayout.heroBottomInsetForDockedRail(
          railHeight: railHeight,
          scale: scale,
          gap: MonoTokens.tvHeroRailGap * scale,
        ),
        greaterThan(peek + MonoTokens.tvHeroRailGap * scale),
      );
    });

    test('an absent rail reserves nothing', () {
      expect(TvBrowseRailLayout.heroBottomInsetForDockedRail(railHeight: 0, scale: 1, gap: 16), 0);
    });
  });

  group('hero over a docked rail', () {
    /// Pumps the composition and returns the rects of the four blocks that must
    /// stay apart. The metadata is found through the "Movie" kind label, which
    /// opens the line.
    Future<({Rect title, Rect metadata, Rect summary, Rect railLabel})> pumpAndMeasure(
      WidgetTester tester,
      Size size,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final scale = TvLayoutConstants.scaleForSize(size);
      final railHeight = _railHeightFor(size);
      final contentTop = (size.height * 0.075).clamp(64.0 * scale, 120.0 * scale).toDouble();

      await tester.pumpWidget(
        _libraryTvContent(
          size: size,
          contentTop: contentTop,
          contentBottom: TvBrowseRailLayout.heroBottomInsetForDockedRail(
            railHeight: railHeight,
            scale: scale,
            gap: MonoTokens.tvHeroRailGap * scale,
          ),
        ),
      );
      // Past the spotlight's 280ms AnimatedSwitcher.
      await tester.pump(const Duration(milliseconds: 400));

      return (
        title: tester.getRect(find.text(_longTitle)),
        metadata: tester.getRect(find.text(t.discover.movie)),
        summary: tester.getRect(find.text(_longSummary)),
        railLabel: tester.getRect(find.text(_railHubTitle)),
      );
    }

    testWidgets('title, metadata, summary and the first row label never overlap at 1920x1080', (tester) async {
      final rects = await pumpAndMeasure(tester, const Size(1920, 1080));

      expect(rects.title.bottom, lessThanOrEqualTo(rects.metadata.top + 0.5), reason: 'title runs into the metadata');
      expect(
        rects.metadata.bottom,
        lessThanOrEqualTo(rects.summary.top + 0.5),
        reason: 'metadata runs into the summary',
      );
      expect(
        rects.summary.bottom,
        lessThanOrEqualTo(rects.railLabel.top + 0.5),
        reason: 'the summary is drawn over the "$_railHubTitle" row header — the bug from the screenshot',
      );
    });

    testWidgets('the same holds on a 1280x720 viewport', (tester) async {
      final rects = await pumpAndMeasure(tester, const Size(1280, 720));

      expect(rects.title.bottom, lessThanOrEqualTo(rects.metadata.top + 0.5));
      expect(rects.metadata.bottom, lessThanOrEqualTo(rects.summary.top + 0.5));
      expect(
        rects.summary.bottom,
        lessThanOrEqualTo(rects.railLabel.top + 0.5),
        reason: 'the summary is drawn over the "$_railHubTitle" row header',
      );
    });

    testWidgets('the sliding-rail peek figure really does overlap here', (tester) async {
      // Pins why heroBottomInsetForDockedRail exists, and proves the assertion
      // above can fail: hand the hero the home screen's peek — the value this
      // screen used to use — and the summary lands on the row header.
      const size = Size(1920, 1080);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final scale = TvLayoutConstants.scaleForSize(size);
      final peek = TvBrowseRailLayout.firstHubPeekHeight(
        hub: _railHubs().first,
        railSize: size,
        density: SettingsService.instance.read(SettingsService.libraryDensity),
        episodePosterMode: SettingsService.instance.read(SettingsService.episodePosterMode),
        tallPosterScale: TvBrowseRailLayout.compactTallPosterScale,
      );

      await tester.pumpWidget(
        _libraryTvContent(size: size, contentTop: 120, contentBottom: peek + MonoTokens.tvHeroRailGap * scale),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.getRect(find.text(_longSummary)).bottom, greaterThan(tester.getRect(find.text(_railHubTitle)).top));
    });

    testWidgets('a short band sheds summary lines instead of shrinking the whole block', (tester) async {
      const size = Size(1920, 1080);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final scale = TvLayoutConstants.scaleForSize(size);
      final railHeight = _railHeightFor(size);
      final roomy = TvBrowseRailLayout.heroBottomInsetForDockedRail(
        railHeight: railHeight,
        scale: scale,
        gap: MonoTokens.tvHeroRailGap * scale,
      );

      await tester.pumpWidget(_libraryTvContent(size: size, contentTop: 120, contentBottom: roomy));
      await tester.pump(const Duration(milliseconds: 400));
      final roomyLines = tester.widget<Text>(find.text(_longSummary)).maxLines;
      final roomyTitleFontSize = tester.widget<Text>(find.text(_longTitle)).style?.fontSize;

      // Squeeze the band until only the logo slot, the metadata line and a
      // sliver of summary fit.
      await tester.pumpWidget(
        _libraryTvContent(size: size, contentTop: 120, contentBottom: size.height - 120 - (200 * scale)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      final tightLines = tester.widget<Text>(find.text(_longSummary)).maxLines;

      expect(roomyLines, 3, reason: 'a roomy band still renders the summary the way it always did');
      expect(tightLines, lessThan(roomyLines!), reason: 'a tight band drops summary lines');
      expect(tightLines, greaterThanOrEqualTo(1));
      expect(roomyTitleFontSize, isNotNull, reason: 'the title keeps a real font size rather than being scaled away');
      expect(tester.takeException(), isNull, reason: 'no overflow while the band tightens');
    });
  });
}
