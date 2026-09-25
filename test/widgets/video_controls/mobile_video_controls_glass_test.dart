/// The glass player controls on the iPhone (Liquid Glass Task 6, mockup LG-03).
///
/// On the real [MobileVideoControls] (the widget `VideoControls` mounts on a
/// phone): (a) setting off, today's controls; (b) setting on, three glass
/// circles, one plate, one capsule, buttons in place and the timeline 16 pt
/// inside the plate; (c) the OSD scrim; (d) contrast over the lightest real
/// fixture (Big Buck Bunny), VOD and live. The plates render without a
/// backdrop on every tier (`GlassSurface.backdrop`), so the test composites
/// what the device composites: the tint straight over the frame.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/models/livetv_capture_buffer.dart';
import 'package:pleya/theme/glass/glass_settings.dart';
import 'package:pleya/theme/glass/glass_surface.dart';
import 'package:pleya/theme/glass/glass_text.dart';
import 'package:pleya/watch_together/providers/watch_together_provider.dart';
import 'package:pleya/widgets/video_controls/mobile_video_controls.dart';
import 'package:pleya/widgets/video_controls/mobile_video_controls_glass.dart';
import 'package:pleya/widgets/app_icon.dart';
import 'package:pleya/widgets/video_controls/widgets/live_timeline_bar.dart';
import 'package:pleya/widgets/video_controls/widgets/timeline_slider.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/contrast.dart';
import '../../test_helpers/glass_phone.dart';
import '../../test_helpers/golden.dart';
import '../../test_helpers/prefs.dart';
import '../../test_helpers/watch_together_fakes.dart';
import 'package:pleya/services/settings_service.dart';

late final ui.Image _lightSceneImage;

const _kSceneKey = Key('scene');
const _kTrailingKey = Key('trailing');
const _kTitle = 'Big Buck Bunny';

/// iPhone 17 Pro, landscape (the player runs landscape): 852x393 at 3x.
Future<void> _phoneLandscape(WidgetTester tester, {required bool glass}) async {
  tester.view.physicalSize = const Size(2556, 1179);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.runAsync(() => SettingsService.getInstance());
  await SettingsService.instance.write(SettingsService.liquidGlass, glass);
  useFakeGlassTier();
}

/// The real controls over [background], with the OSD scrim `VideoControls`
/// paints under them.
///
/// [live]: live TV with a time-shift buffer, the `LiveTimelineBar` path.
Future<void> _pumpControls(WidgetTester tester, {required bool glass, Widget? background, bool live = false}) async {
  await _phoneLandscape(tester, glass: glass);
  final player = FakeSyncPlayer(
    position: const Duration(minutes: 2, seconds: 18),
    duration: const Duration(minutes: 9),
  );
  addTearDown(player.dispose);
  final watchTogether = WatchTogetherProvider();
  addTearDown(watchTogether.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<WatchTogetherProvider>.value(
      value: watchTogether,
      child: MaterialApp(
        theme: glassPhoneTheme(),
        home: Material(
          type: MaterialType.transparency,
          child: RepaintBoundary(
            key: _kSceneKey,
            child: Stack(
              fit: StackFit.expand,
              children: [
                background ?? const ColoredBox(color: Colors.black),
                Builder(
                  builder: (context) => DecoratedBox(
                    decoration: playerOverlayScrim(hasFrame: true, glass: playerGlassOn(context)),
                    child: MobileVideoControls(
                      player: player,
                      metadata: MediaItem(id: '1', backend: MediaBackend.plex, kind: MediaKind.movie, title: _kTitle),
                      chapters: const [],
                      chaptersLoaded: true,
                      seekTimeSmall: 10,
                      trackChapterControls: Row(
                        key: _kTrailingKey,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(onPressed: () {}, icon: const Icon(Icons.cast)),
                          IconButton(onPressed: () {}, icon: const Icon(Icons.tune)),
                        ],
                      ),
                      onSeek: (_) {},
                      onSeekEnd: (_) {},
                      onPlayPause: () {},
                      onPrevious: () {},
                      onNext: () {},
                      isLive: live,
                      captureBuffer: live
                          ? const CaptureBuffer(startedAt: 1790000000, seekStartSeconds: 0, seekEndSeconds: 3600)
                          : null,
                      streamStartEpoch: 1790001800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

Iterable<GlassSurface> _surfaces(WidgetTester tester, Type shape) =>
    tester.widgetList<GlassSurface>(find.byType(GlassSurface)).where((s) => s.shape.runtimeType == shape);

/// Geometry that must not move when glass turns on.
Map<String, Rect> _geometry(WidgetTester tester) => {
  'play': tester.getRect(find.bySemanticsLabel(t.videoControls.playButton)),
  'previous': tester.getRect(find.bySemanticsLabel(t.videoControls.previousButton)),
  'next': tester.getRect(find.bySemanticsLabel(t.videoControls.nextButton)),
  'trailing': tester.getRect(find.byKey(_kTrailingKey)),
  'title': tester.getRect(find.text(_kTitle)),
};

/// The live timecode: the only `Text` inside the `LiveTimelineBar`.
Finder get _liveTime => find.descendant(of: find.byType(LiveTimelineBar), matching: find.byType(Text));

void main() {
  setUpAll(() async {
    await loadAppFontsForGoldens();
    LocaleSettings.setLocaleSync(AppLocale.en);
    await initializeDateFormatting('en');
    final bytes = File('test/fixtures/glass/bbb_light_scene.jpg').readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    _lightSceneImage = (await codec.getNextFrame()).image;
  });
  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  testWidgets('(a) glas uit: de bediening van vandaag, geen blur, zwarte cirkels', (tester) async {
    await _pumpControls(tester, glass: false);

    expect(find.byType(BackdropFilter), findsNothing);
    final circles = tester
        .widgetList<Container>(find.byType(Container))
        .where(
          (c) => c.decoration == BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
        );
    expect(circles, hasLength(3));
    expect(tester.widget<Text>(find.text(_kTitle)).style?.shadows, isNull);
    expect(DefaultTextStyle.of(tester.element(find.text(_kTitle))).style.shadows, isNull);
  });

  testWidgets('(b) glas aan: drie glazen cirkels, één plaat, één capsule; de knoppen blijven staan', (tester) async {
    await _pumpControls(tester, glass: false);
    final off = _geometry(tester);
    final offSlider = tester.getRect(find.byType(TimelineSlider));
    final offTime = tester.getRect(find.text('2:18'));

    await _pumpControls(tester, glass: true);
    expect(glassTierFor(tester.element(find.byType(MobileVideoControls))), GlassTier.fake);
    // No backdrop anywhere: the video is a native layer Flutter can't sample.
    expect(find.byType(GlassLayer), findsNothing);
    expect(_surfaces(tester, CircleBorder).every((s) => !s.backdrop), isTrue);
    expect(_surfaces(tester, CircleBorder), hasLength(3));
    expect(_surfaces(tester, RoundedRectangleBorder), hasLength(1));
    expect(_surfaces(tester, StadiumBorder), hasLength(1));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.widgetList<GlassSurface>(find.byType(GlassSurface)).where((s) => s.backdrop), isEmpty);
    // Title and timestamps inherit the glass shadow.
    expect(DefaultTextStyle.of(tester.element(find.text(_kTitle))).style.shadows, kGlassTextShadows);

    expect(_geometry(tester), off);

    // The timeline sits 16 pt inside the plate (LG-03), the timestamps move
    // in with it; nothing else moves.
    final plate = tester.getRect(find.byWidgetPredicate((w) => w is GlassSurface && w.shape is RoundedRectangleBorder));
    final slider = tester.getRect(find.byType(TimelineSlider));
    expect(slider.left, plate.left + 16);
    expect(slider.right, plate.right - 16);
    expect(slider.center.dy, offSlider.center.dy);
    expect(slider.width, offSlider.width - 32);
    expect(tester.getRect(find.text('2:18')).left, offTime.left + 16);
    final capsule = tester.getRect(find.byWidgetPredicate((w) => w is GlassSurface && w.shape is StadiumBorder));
    expect(capsule, off['trailing']);
  });

  test('(c) scrim: glas uit precies de oude, glas aan alleen een topband', () {
    expect(
      playerOverlayScrim(hasFrame: true, glass: false),
      BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.7),
          ],
          stops: const [0.0, 0.2, 0.8, 1.0],
        ),
      ),
    );
    expect(playerOverlayScrim(hasFrame: false, glass: false), const BoxDecoration(color: Colors.black));
    expect(playerOverlayScrim(hasFrame: false, glass: true), const BoxDecoration(color: Colors.black));
    final glass = playerOverlayScrim(hasFrame: true, glass: true).gradient! as LinearGradient;
    expect(glass.colors.first, Colors.black.withValues(alpha: 0.55));
    expect(glass.colors.last, Colors.transparent);
  });

  testWidgets('(b) live: met glas aan staat de live-tijdlijn op een plaat, met glas uit zoals vandaag', (tester) async {
    await _pumpControls(tester, glass: false, live: true);
    expect(find.byType(GlassSurface), findsNWidgets(2)); // play circle, capsule: both render legacy
    final offBar = tester.getRect(find.byType(LiveTimelineBar));
    expect(tester.widget<Text>(_liveTime).style!.color, Colors.white70);

    await _pumpControls(tester, glass: true, live: true);
    final plate = find.byWidgetPredicate((w) => w is GlassSurface && w.shape is RoundedRectangleBorder);
    expect(plate, findsOneWidget);
    expect(find.descendant(of: plate, matching: find.byType(LiveTimelineBar)), findsOneWidget);
    // The bar keeps its own 16 pt inset, now inside the plate.
    expect(tester.getRect(find.byType(LiveTimelineBar)).width, offBar.width - 32);
    expect(tester.widget<Text>(_liveTime).style!.color, Colors.white);
  });

  group('(d) contrast over Big Buck Bunny, gelijk aan het toestel', () {
    // The meter needs the text painted transparent with its shadow kept
    // (`textContrastOverBackground`). The controls hard-code their colors, so
    // the real controls first give the geometry: every glass surface with its
    // shape, and every glyph. Then the same scene, scrim, surfaces and
    // inherited shadows are pumped at exactly those rects, with transparent
    // glyphs. Surfaces that the real tree lacks are missing here too.
    Future<Map<String, double>> measure(WidgetTester tester, {bool live = false}) async {
      Widget scene() => RawImage(image: _lightSceneImage, fit: BoxFit.cover);
      await _pumpControls(tester, glass: true, background: scene(), live: live);
      final surfaces = [
        for (final e in find.byType(GlassSurface).evaluate())
          (tester.getRect(find.byWidget(e.widget)), (e.widget as GlassSurface).shape),
      ];
      final title = tester.getRect(find.text(_kTitle));
      final titleStyle = tester.widget<Text>(find.text(_kTitle)).style!;
      final play = find.bySemanticsLabel(t.videoControls.playButton);
      final playIcon = tester.getRect(find.descendant(of: play, matching: find.byType(Icon)));
      final capsuleIcon = tester.getRect(
        find.descendant(of: find.byKey(_kTrailingKey), matching: find.byType(Icon)).first,
      );
      final (Rect, TextStyle, String) time = live
          ? (tester.getRect(_liveTime), tester.widget<Text>(_liveTime).style!, tester.widget<Text>(_liveTime).data!)
          : (tester.getRect(find.text('2:18')), tester.widget<Text>(find.text('2:18')).style!, '2:18');

      Widget at(Rect r, Widget child) => Positioned.fromRect(rect: r, child: child);
      const titleKey = Key('title'), timeKey = Key('time'), iconKey = Key('icon'), capsuleKey = Key('capsule');
      await tester.pumpWidget(
        MaterialApp(
          theme: glassPhoneTheme(),
          home: RepaintBoundary(
            key: _kSceneKey,
            child: Builder(
              builder: (context) => Stack(
                fit: StackFit.expand,
                children: [
                  scene(),
                  DecoratedBox(decoration: playerOverlayScrim(hasFrame: true, glass: true)),
                  playerGlassScope(
                    context,
                    Stack(
                      children: [
                        for (final (rect, shape) in surfaces)
                          at(rect, playerGlassSurface(shape, const SizedBox.expand())),
                        at(
                          title,
                          Text(
                            _kTitle,
                            key: titleKey,
                            style: titleStyle.copyWith(color: Colors.transparent),
                          ),
                        ),
                        at(
                          time.$1,
                          Text(
                            time.$3,
                            key: timeKey,
                            style: time.$2.copyWith(color: Colors.transparent),
                          ),
                        ),
                        // The capsule's icons carry no shadow (see `playerGlassCapsule`).
                        at(
                          capsuleIcon,
                          Icon(
                            Icons.tune,
                            key: capsuleKey,
                            size: capsuleIcon.height,
                            color: Colors.transparent,
                            shadows: const [],
                          ),
                        ),
                        // The glyph the button really draws: Material Symbols,
                        // fill 1, AppIcon's default weight 700.
                        at(
                          playIcon,
                          AppIcon(
                            Symbols.play_arrow_rounded,
                            key: iconKey,
                            fill: 1,
                            size: playIcon.height,
                            color: Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      Future<double> m(Key k, {Color color = Colors.white}) =>
          textContrastOverBackground(tester, area: find.byKey(k), textColor: color, boundary: find.byKey(_kSceneKey));
      return {
        'title': await m(titleKey),
        // The timecode's own color; a translucent one (white70 on the live
        // bar with glass off) composited over black, the darkest it can
        // end up, so conservative.
        'timestamp': await m(timeKey, color: Color.alphaBlend(time.$2.color!, Colors.black)),
        'playIcon': await m(iconKey),
        'capsuleIcon': await m(capsuleKey),
      };
    }

    testWidgets('VOD: titel en tijdcode halen 4,5:1, de iconen 3:1', (tester) async {
      final ratios = await measure(tester);
      // ignore: avoid_print - the measured ratios belong in the test log
      print('glass player contrast, VOD: $ratios');
      expect(ratios['title'], greaterThanOrEqualTo(4.5));
      expect(ratios['timestamp'], greaterThanOrEqualTo(4.5));
      expect(ratios['playIcon'], greaterThanOrEqualTo(3.0));
      expect(ratios['capsuleIcon'], greaterThanOrEqualTo(3.0));
    });

    testWidgets('live: de live-tijdcode haalt 4,5:1', (tester) async {
      final ratios = await measure(tester, live: true);
      // ignore: avoid_print - the measured ratios belong in the test log
      print('glass player contrast, live: $ratios');
      expect(ratios['timestamp'], greaterThanOrEqualTo(4.5));
    });
  });
}
