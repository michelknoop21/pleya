/// DENS1, the player on iPhone and Apple TV against mockup A (Filmbeeld).
///
/// Every number here is a measured contract from the November 2026 audit:
/// the iPhone values are mockup A converted to an 844 pt landscape phone, the
/// Apple TV values are HIG points on the 1920x1080 canvas, measured on a
/// 1038x584 logical panel the way an Apple TV lays it out.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_source_info.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/utils/tv_hig.dart';
import 'package:pleya/watch_together/providers/watch_together_provider.dart';
import 'package:pleya/widgets/video_controls/desktop_video_controls.dart';
import 'package:pleya/widgets/video_controls/film_frame_palette.dart';
import 'package:pleya/widgets/video_controls/mobile_video_controls.dart';
import 'package:pleya/widgets/video_controls/models/track_controls_state.dart';
import 'package:pleya/widgets/video_controls/player_chrome_controller.dart';
import 'package:pleya/widgets/video_controls/player_corner_offset.dart';
import 'package:pleya/widgets/video_controls/sheets/base_video_control_sheet.dart';
import 'package:pleya/widgets/video_controls/tv_info_panel/tv_panel_widgets.dart';
import 'package:pleya/widgets/video_controls/tv_info_panel/tv_sleep_timer_sub_view.dart';
import 'package:pleya/widgets/video_controls/video_control_button.dart';
import 'package:pleya/widgets/video_controls/widgets/content_strip.dart';
import 'package:pleya/widgets/video_controls/widgets/media_selector_thumbnail.dart';
import 'package:pleya/widgets/video_controls/widgets/player_toast_indicator.dart';
import 'package:pleya/widgets/video_controls/widgets/timeline_slider.dart';
import 'package:pleya/widgets/video_controls/widgets/track_chapter_controls.dart';
import 'package:pleya/widgets/video_controls/widgets/tv_quality_summary_line.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/glass_phone.dart';
import '../../test_helpers/prefs.dart';
import '../../test_helpers/watch_together_fakes.dart';

const _kTitle = 'Aurora';
const _kFooter = Key('film-footer');
const _kHeader = Key('film-header');

const _tokens = MonoTokens(
  radiusSm: 8,
  radiusMd: 12,
  space: 8,
  fast: Duration(milliseconds: 1),
  normal: Duration(milliseconds: 1),
  slow: Duration(milliseconds: 1),
  bg: Colors.black,
  surface: Colors.black,
  surfaceElevated: Color(0xFF2F2F2F),
  outline: Colors.white24,
  text: Colors.white,
  textMuted: Colors.white70,
  isLight: false,
  accent: Color(0xFFF42B1F),
  accentAlt: Color(0xFFFFB020),
  splashFactory: NoSplash.splashFactory,
);

/// The real iPhone controls (`MobileVideoControls` with the Filmbeeld header
/// and footer from `TrackChapterControls`) on a landscape phone of [size].
Future<void> _pumpPhone(
  WidgetTester tester, {
  required Size size,
  bool film = false,
  bool series = true,
  MediaKind kind = MediaKind.movie,
  ValueChanged<Duration>? onSeekEnd,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(left: 177, right: 177, bottom: 63);
  addTearDown(tester.view.reset);
  await tester.runAsync(() => SettingsService.getInstance());
  final player = FakeSyncPlayer(position: const Duration(minutes: 2), duration: const Duration(minutes: 90));
  addTearDown(player.dispose);
  final watchTogether = WatchTogetherProvider();
  addTearDown(watchTogether.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<WatchTogetherProvider>.value(
      value: watchTogether,
      child: MaterialApp(
        theme: glassPhoneTheme(),
        home: Material(
          color: Colors.black,
          child: TrackChapterControls(
            player: player,
            chapters: const [],
            chaptersLoaded: true,
            trackControlsState: TrackControlsState(
              onTogglePIPMode: () {},
              onCycleBoxFitMode: () {},
              onToggleRotationLock: () {},
              onToggleScreenLock: () {},
            ),
            filmFrameLayout: (header, footer) => MobileVideoControls(
              player: player,
              metadata: MediaItem(id: '1', backend: MediaBackend.plex, kind: kind, title: _kTitle),
              chapters: const [],
              chaptersLoaded: true,
              seekTimeSmall: 10,
              trackChapterControls: KeyedSubtree(key: _kHeader, child: header),
              footerControls: KeyedSubtree(key: _kFooter, child: footer),
              onSeek: (_) {},
              onSeekEnd: onSeekEnd ?? (_) {},
              onPlayPause: () {},
              onPrevious: film ? null : () {},
              onNext: film || !series ? null : () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

List<Rect> _buttonsIn(WidgetTester tester, Key key) {
  final finder = find.descendant(of: find.byKey(key), matching: find.byType(VideoControlButton));
  return [for (final e in finder.evaluate()) tester.getRect(find.byWidget(e.widget))]
    ..sort((a, b) => a.left.compareTo(b.left));
}

/// The 46 pt disc around a header/footer button (the parent of the button's
/// `SizedBox.square`).
List<Rect> _discsIn(WidgetTester tester, Key key) {
  final finder = find.descendant(
    of: find.byKey(key),
    matching: find.byWidgetPredicate((w) => w is SizedBox && w.width == kFilmTarget && w.height == kFilmTarget),
  );
  return [for (final e in finder.evaluate()) tester.getRect(find.byWidget(e.widget))]
    ..sort((a, b) => a.left.compareTo(b.left));
}

void _expectGaps(List<Rect> rects, double gap) {
  for (var i = 1; i < rects.length; i++) {
    expect(rects[i].left - rects[i - 1].right, closeTo(gap, 0.5), reason: 'gap $i');
  }
}

void main() {
  setUpAll(() async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    await initializeDateFormatting('en');
  });
  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  group('iPhone, mockup A', () {
    for (final size in [const Size(667, 375), const Size(874, 402), const Size(956, 440), const Size(1024, 768)]) {
      testWidgets('transport group: 68 play, 52 skip, 18 apart, centred ($size)', (tester) async {
        await _pumpPhone(tester, size: size);
        final play = tester.getRect(find.bySemanticsLabel(t.videoControls.playButton));
        final previous = tester.getRect(find.bySemanticsLabel(t.videoControls.previousButton));
        final next = tester.getRect(find.bySemanticsLabel(t.videoControls.nextButton));
        expect(play.size, const Size(kFilmPlaySize, kFilmPlaySize));
        expect(previous.size, const Size(kFilmSkipSize, kFilmSkipSize));
        expect(next.size, const Size(kFilmSkipSize, kFilmSkipSize));
        expect(play.left - previous.right, closeTo(kFilmTransportGap, 0.5));
        expect(next.left - play.right, closeTo(kFilmTransportGap, 0.5));
        expect(next.right - previous.left, closeTo(2 * kFilmSkipSize + kFilmPlaySize + 2 * kFilmTransportGap, 0.5));
        expect(play.center.dx, closeTo(size.width / 2, 0.5));
        expect(tester.takeException(), isNull);
      });

      testWidgets('footer centred with 10 between the discs, header 46 apart by 10 ($size)', (tester) async {
        await _pumpPhone(tester, size: size);
        final footer = _discsIn(tester, _kFooter);
        expect(footer.length, greaterThanOrEqualTo(3));
        for (final r in footer) {
          expect(r.size, const Size(kFilmTarget, kFilmTarget));
        }
        _expectGaps(footer, kFilmToolGap);
        final groupCentre = (footer.first.left + footer.last.right) / 2;
        expect(groupCentre, closeTo(size.width / 2, 0.5));
        final header = _discsIn(tester, _kHeader);
        expect(header.length, greaterThanOrEqualTo(2));
        _expectGaps(header, kFilmToolGap);
        expect(_buttonsIn(tester, _kHeader), isNotEmpty);
      });
    }

    testWidgets('a film draws no previous or next', (tester) async {
      await _pumpPhone(tester, size: const Size(874, 402), film: true);
      expect(find.bySemanticsLabel(t.videoControls.previousButton), findsNothing);
      expect(find.bySemanticsLabel(t.videoControls.nextButton), findsNothing);
      final play = tester.getRect(find.bySemanticsLabel(t.videoControls.playButton));
      expect(play.center.dx, closeTo(874 / 2, 0.5));
    });

    testWidgets('an episode without navigation (Watch Together guest) keeps both greyed buttons', (tester) async {
      await _pumpPhone(tester, size: const Size(874, 402), film: true, kind: MediaKind.episode);
      expect(find.bySemanticsLabel(t.videoControls.previousButton), findsOneWidget);
      expect(find.bySemanticsLabel(t.videoControls.nextButton), findsOneWidget);
    });

    // Review C1: the round thumb is 13 tall and shrank the gesture area with
    // it, so a tap in the timeline row fell through to the video and hid the
    // controls (the Verify film runs ended on a blank frame).
    for (final size in [const Size(667, 375), const Size(956, 440)]) {
      testWidgets('the timeline keeps a 44 pt touch band and a tap in its middle seeks ($size)', (tester) async {
        Duration? seeked;
        await _pumpPhone(tester, size: size, onSeekEnd: (d) => seeked = d);
        final band = find.descendant(of: find.byType(TimelineSlider), matching: find.byType(RawGestureDetector));
        expect(tester.getSize(band.first).height, greaterThanOrEqualTo(44));
        // The bottom edge of the band, not its middle: a band that reaches past
        // its parent's size is not hit there (re-review Minor 1).
        final bandRect = tester.getRect(band.first);
        await tester.tapAt(Offset(bandRect.center.dx, bandRect.bottom - 2));
        await tester.pump();
        expect(seeked, isNotNull);
        // The pending-seek failsafe timer.
        await tester.pump(const Duration(seconds: 16));
      });
    }

    testWidgets('the last episode keeps a greyed next so play stays centred', (tester) async {
      await _pumpPhone(tester, size: const Size(874, 402), series: false);
      expect(find.bySemanticsLabel(t.videoControls.nextButton), findsOneWidget);
      expect(tester.getRect(find.bySemanticsLabel(t.videoControls.playButton)).center.dx, closeTo(874 / 2, 0.5));
    });

    testWidgets('one disc colour, back button in a disc, 28 pt title, round thumb', (tester) async {
      await _pumpPhone(tester, size: const Size(874, 402));
      final discColours = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.shape == BoxShape.circle)
          .map((d) => d.color)
          .toSet();
      expect(discColours, {kFilmDisc});
      final back = find.bySemanticsLabel(t.common.back);
      expect(tester.getSize(back), const Size(kFilmTarget, kFilmTarget));
      expect(
        find.descendant(
          of: back,
          matching: find.byWidgetPredicate(
            (w) => w is DecoratedBox && w.decoration == const BoxDecoration(color: kFilmDisc, shape: BoxShape.circle),
          ),
        ),
        findsOneWidget,
      );
      expect(tester.widget<Text>(find.text(_kTitle)).style!.fontSize, kFilmTitleSize);
      final slider = find.descendant(of: find.byType(TimelineSlider), matching: find.byType(SliderTheme));
      expect(tester.widget<SliderTheme>(slider).data.thumbShape, isA<RoundSliderThumbShape>());
    });

    testWidgets('a light player sheet keeps the app primary (review I1)', (tester) async {
      late Color primary;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: const ColorScheme.light(primary: Color(0xFFF42B1F)),
            extensions: const [_tokens],
          ),
          home: BaseVideoControlSheet(
            title: 'x',
            child: Builder(
              builder: (context) {
                primary = Theme.of(context).colorScheme.primary;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(primary, const Color(0xFFF42B1F));
    });

    testWidgets('player sheets mark a choice in the Filmbeeld mint, not the red primary', (tester) async {
      late Color primary;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: const ColorScheme.dark(primary: Color(0xFFF42B1F)),
            extensions: const [_tokens],
          ),
          home: BaseVideoControlSheet(
            title: 'x',
            child: Builder(
              builder: (context) {
                primary = Theme.of(context).colorScheme.primary;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(primary, kFilmFocus);
    });
  });

  group('Apple TV, HIG points', () {
    const panel = Size(1038, 584);
    double pt(double points) => points * panel.height / 1080;

    setUp(() => TvDetectionService.debugSetAppleTVOverride(true));
    tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

    Future<void> tvCanvas(WidgetTester tester) async {
      tester.view.physicalSize = panel;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => SettingsService.getInstance());
    }

    Future<void> pumpTvControls(WidgetTester tester) async {
      await tvCanvas(tester);
      final player = FakeSyncPlayer(playing: true, position: const Duration(minutes: 3));
      addTearDown(player.dispose);
      final watchTogether = WatchTogetherProvider();
      addTearDown(watchTogether.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<WatchTogetherProvider>.value(
          value: watchTogether,
          child: MaterialApp(
            theme: ThemeData(extensions: const [_tokens]),
            home: Material(
              color: Colors.black,
              child: DesktopVideoControls(
                player: player,
                metadata: MediaItem(id: '1', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Film'),
                chapters: [MediaChapter(id: 1, startTimeOffset: 0, title: 'Een')],
                chaptersLoaded: true,
                seekTimeSmall: 10,
                onSeekBackward: () {},
                onSeekForward: () {},
                onSeekToPreviousChapter: () {},
                onSeekToNextChapter: () {},
                onSeek: (_) {},
                onSeekEnd: (_) {},
                onNext: () {},
                onPrevious: () {},
                getReplayIcon: (_) => Icons.replay_10,
                getForwardIcon: (_) => Icons.forward_10,
                useDpadNavigation: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('T1: the transport row ends 60 pt above the bottom edge', (tester) async {
      await pumpTvControls(tester);
      final play = tester.getRect(find.bySemanticsLabel(t.videoControls.pauseButton).first);
      expect(panel.height - play.bottom, greaterThanOrEqualTo(pt(60) - 0.5));
    });

    testWidgets('T4: one focus language, no ring around play, so the row keeps one pitch', (tester) async {
      await pumpTvControls(tester);
      final row = find.ancestor(
        of: find.bySemanticsLabel(t.videoControls.pauseButton).first,
        matching: find.byType(Row),
      );
      final wrappers = find.descendant(of: row.first, matching: find.byType(IconButton));
      final rects = [for (final e in wrappers.evaluate()) tester.getRect(find.byWidget(e.widget))]
        ..sort((a, b) => a.left.compareTo(b.left));
      expect(rects.length, greaterThanOrEqualTo(5));
      // Neighbouring buttons touch: no ring padding opens a gap around play.
      for (var i = 1; i < 5; i++) {
        expect(rects[i].left - rects[i - 1].right, closeTo(0, 0.5), reason: 'gap $i');
      }
    });

    testWidgets('T2: panel, toast and quality badge text is at least 23 pt', (tester) async {
      await tvCanvas(tester);
      late TvPanelMetrics m;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [_tokens]),
          home: Material(
            child: Builder(
              builder: (context) {
                m = TvPanelMetrics.of(context);
                return Column(
                  children: [
                    const PlayerToastIndicator(icon: Icons.check, text: 'Ondertitels aan', detail: 'Nederlands'),
                    TvQualitySummaryLine(player: FakeSyncPlayer(), isTranscoding: false),
                  ],
                );
              },
            ),
          ),
        ),
      );
      for (final size in [
        m.titleFontSize,
        m.valueFontSize,
        m.subtitleFontSize,
        m.sectionFontSize,
        m.markValueFontSize,
      ]) {
        expect(size, greaterThanOrEqualTo(pt(TvHig.caption2) - 0.01));
      }
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(text.style?.fontSize ?? 14, greaterThanOrEqualTo(pt(TvHig.caption2) - 0.01), reason: text.data);
      }
    });

    testWidgets('T3: the sleep timer shows all eight durations, "2 hours" included', (tester) async {
      await tvCanvas(tester);
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [_tokens]),
          home: Material(
            child: Center(
              // The panel body an Apple TV leaves for a sub-view.
              child: SizedBox(
                width: 960,
                height: 360,
                child: TvSleepTimerSubView(player: FakeSyncPlayer(), firstFocusNode: node, onDone: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final body = tester.getRect(find.byType(TvSleepTimerSubView));
      final lastRow = tester.getRect(find.text('2 hours'));
      expect(lastRow.bottom, lessThanOrEqualTo(body.bottom));
      expect(tester.takeException(), isNull);
    });

    testWidgets('T8: the chapter strip takes the wide tablet layout on a TV', (tester) async {
      await tvCanvas(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [_tokens]),
          home: Material(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ContentStrip(
                player: FakeSyncPlayer(),
                chapters: [
                  MediaChapter(id: 1, startTimeOffset: 0, title: 'Een'),
                  MediaChapter(id: 2, startTimeOffset: 60000, title: 'Twee'),
                ],
                chaptersLoaded: true,
                useFocusNavigation: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // The tablet thumbnail is 200x112; a phone gets 120x68.
      final thumbs = tester.widgetList<MediaSelectorThumbnail>(find.byType(MediaSelectorThumbnail));
      expect(thumbs.map((t) => (t.width, t.height)).toSet(), {(200.0, 112.0)});
    });

    testWidgets('T7: corner prompts sit on the TV inset and 60 pt up', (tester) async {
      await tvCanvas(tester);
      final chrome = PlayerChromeController();
      addTearDown(chrome.dispose);
      late ({double right, double bottom, double maxWidth}) hidden;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              hidden = playerCornerOffset(context, chrome, controlsShown: false);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(hidden.bottom, closeTo(pt(60), 0.01));
      expect(hidden.right, greaterThan(24));
    });
  });

  testWidgets('T7: on a phone the card stays 10 above the measured bottom block', (tester) async {
    tester.view.physicalSize = const Size(874, 402) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final chrome = PlayerChromeController()..setBottomChromeFraction(0.3);
    addTearDown(chrome.dispose);
    late ({double right, double bottom, double maxWidth}) shown;
    await tester.pumpWidget(
      MaterialApp(
        theme: glassPhoneTheme(),
        home: Builder(
          builder: (context) {
            shown = playerCornerOffset(context, chrome, controlsShown: true);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(shown.bottom, closeTo(402 * 0.3 + 10, 0.01));
  });
}
