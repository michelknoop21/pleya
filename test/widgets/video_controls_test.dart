import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_source_info.dart';
import 'package:pleya/media/media_version.dart';
import 'package:pleya/models/shader_preset.dart';
import 'package:pleya/mpv/mpv.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/watch_together/providers/watch_together_provider.dart';
import 'package:pleya/widgets/video_controls/video_controls.dart';
import 'package:pleya/widgets/video_controls/desktop_video_controls.dart';
import 'package:pleya/widgets/video_controls/painters/buffer_range_painter.dart';
import 'package:pleya/widgets/video_controls/widgets/mobile_skip_zones.dart';
import 'package:pleya/widgets/video_controls/widgets/skip_marker_button.dart';
import 'package:pleya/widgets/video_controls/widgets/sync_offset_control.dart';
import 'package:pleya/widgets/video_controls/widgets/timeline_slider.dart';
import 'package:pleya/widgets/video_controls/widgets/video_timeline_bar.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';
import '../test_helpers/watch_together_fakes.dart';

const _testTokens = MonoTokens(
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveShaderTogglePreset', () {
    test('turns shaders off when a shader is currently active', () {
      final result = resolveShaderTogglePreset(
        currentPreset: ShaderPreset.nvscalerDefault,
        savedPreset: ShaderPreset.nvscalerDefault,
        allPresets: ShaderPreset.allPresets,
      );

      expect(result, ShaderPreset.none);
    });

    test('restores the saved preset when shaders are currently off', () {
      final saved = ShaderPreset.artcnnPreset(ArtCNNModel.c4f16, ArtCNNVariant.neutral);
      final result = resolveShaderTogglePreset(
        currentPreset: ShaderPreset.none,
        savedPreset: saved,
        allPresets: ShaderPreset.allPresets,
      );

      expect(result, saved);
    });

    test('falls back to the first enabled preset when no shader is saved', () {
      final result = resolveShaderTogglePreset(
        currentPreset: ShaderPreset.none,
        savedPreset: ShaderPreset.none,
        allPresets: const [ShaderPreset.none, ShaderPreset.nvscalerDefault],
      );

      expect(result, ShaderPreset.nvscalerDefault);
    });
  });

  group('effectiveVersionQualityControls', () {
    test('clears switchable version and quality state during offline playback', () {
      final version = MediaVersion(id: 'v1', videoResolution: '1080');
      final audio = MediaAudioTrack(id: 1, languageCode: 'eng', selected: false);
      final subtitle = MediaSubtitleTrack(id: 2, languageCode: 'eng', selected: false, forced: false);

      final result = effectiveVersionQualityControls(
        isOfflinePlayback: true,
        availableVersions: [version],
        serverSupportsTranscoding: true,
        isTranscoding: true,
        sourceAudioTracks: [audio],
        selectedAudioStreamId: 1,
        sourceSubtitleTracks: [subtitle],
        selectedSubtitleStreamId: 2,
      );

      expect(result.canSwitch, isFalse);
      expect(result.availableVersions, isEmpty);
      expect(result.serverSupportsTranscoding, isFalse);
      expect(result.isTranscoding, isFalse);
      expect(result.sourceAudioTracks, isEmpty);
      expect(result.selectedAudioStreamId, isNull);
      expect(result.sourceSubtitleTracks, isEmpty);
      expect(result.selectedSubtitleStreamId, isNull);
    });

    test('keeps switchable state during online playback', () {
      final version = MediaVersion(id: 'v1', videoResolution: '1080');
      final audio = MediaAudioTrack(id: 1, languageCode: 'eng', selected: false);
      final subtitle = MediaSubtitleTrack(id: 2, languageCode: 'eng', selected: false, forced: false);

      final result = effectiveVersionQualityControls(
        isOfflinePlayback: false,
        availableVersions: [version],
        serverSupportsTranscoding: true,
        isTranscoding: true,
        sourceAudioTracks: [audio],
        selectedAudioStreamId: 1,
        sourceSubtitleTracks: [subtitle],
        selectedSubtitleStreamId: 2,
      );

      expect(result.canSwitch, isTrue);
      expect(result.availableVersions, [version]);
      expect(result.serverSupportsTranscoding, isTrue);
      expect(result.isTranscoding, isTrue);
      expect(result.sourceAudioTracks, [audio]);
      expect(result.selectedAudioStreamId, 1);
      expect(result.sourceSubtitleTracks, [subtitle]);
      expect(result.selectedSubtitleStreamId, 2);
    });
  });

  group('selectableSourceSubtitleTracks', () {
    MediaSubtitleTrack sub(int id, {String? codec, String? key}) =>
        MediaSubtitleTrack(id: id, codec: codec, key: key, languageCode: 'eng', selected: false, forced: false);

    test('returns the full list unchanged when not transcoding', () {
      final tracks = [sub(1, codec: 'srt'), sub(2, codec: 'pgs'), sub(3, codec: 'weird')];
      expect(selectableSourceSubtitleTracks(tracks, isTranscoding: false), same(tracks));
    });

    test('keeps text, image and keyed tracks while transcoding', () {
      final text = sub(1, codec: 'srt');
      final image = sub(2, codec: 'pgs');
      final keyed = sub(3, codec: 'weird', key: '/library/streams/3');
      final result = selectableSourceSubtitleTracks([text, image, keyed], isTranscoding: true);
      expect(result, [text, image, keyed]);
    });

    test('drops non-keyed unsupported codecs while transcoding', () {
      final text = sub(1, codec: 'ass');
      final unsupported = sub(2, codec: 'weird');
      final result = selectableSourceSubtitleTracks([text, unsupported], isTranscoding: true);
      expect(result, [text]);
    });
  });

  group('shouldShowSkipMarkerButton', () {
    test('does not show before the first frame is rendered', () {
      expect(
        shouldShowSkipMarkerButton(
          hasFirstFrame: false,
          hasMarker: true,
          hasPlayNextPrompt: false,
          skipButtonDismissed: false,
          controlsVisible: true,
        ),
        isFalse,
      );
    });

    test('shows after first frame when marker is active and not dismissed', () {
      expect(
        shouldShowSkipMarkerButton(
          hasFirstFrame: true,
          hasMarker: true,
          hasPlayNextPrompt: false,
          skipButtonDismissed: false,
          controlsVisible: false,
        ),
        isTrue,
      );
    });

    test('does not show when dismissed until controls are visible again', () {
      expect(
        shouldShowSkipMarkerButton(
          hasFirstFrame: true,
          hasMarker: true,
          hasPlayNextPrompt: false,
          skipButtonDismissed: true,
          controlsVisible: false,
        ),
        isFalse,
      );
      expect(
        shouldShowSkipMarkerButton(
          hasFirstFrame: true,
          hasMarker: true,
          hasPlayNextPrompt: false,
          skipButtonDismissed: true,
          controlsVisible: true,
        ),
        isTrue,
      );
    });

    test('does not show while play next prompt is active', () {
      expect(
        shouldShowSkipMarkerButton(
          hasFirstFrame: true,
          hasMarker: true,
          hasPlayNextPrompt: true,
          skipButtonDismissed: false,
          controlsVisible: true,
        ),
        isFalse,
      );
    });
  });

  group('markerCanOfferSkip', () {
    MediaMarker marker(String type) => MediaMarker(id: 1, type: type, startTimeOffset: 0, endTimeOffset: 30000);

    test('an episode intro is offered, that is what the button is for', () {
      expect(markerCanOfferSkip(marker: marker('intro'), kind: MediaKind.episode), isTrue);
    });

    test('a movie intro is not offered at all', () {
      // A movie's intro marker comes from the chapter-title fallback and can run
      // for minutes, so the button used to sit there and return on every tap.
      expect(markerCanOfferSkip(marker: marker('intro'), kind: MediaKind.movie), isFalse);
    });

    test('clips and unknown items get no intro button either', () {
      expect(markerCanOfferSkip(marker: marker('intro'), kind: MediaKind.clip), isFalse);
      expect(markerCanOfferSkip(marker: marker('unknown'), kind: MediaKind.unknown), isFalse);
    });

    test('credits stay skippable, on a movie as much as on an episode', () {
      expect(markerCanOfferSkip(marker: marker('credits'), kind: MediaKind.movie), isTrue);
      expect(markerCanOfferSkip(marker: marker('credits'), kind: MediaKind.episode), isTrue);
    });
  });

  group('shouldAutoSkipMarker', () {
    MediaMarker marker(String type) => MediaMarker(id: 1, type: type, startTimeOffset: 0, endTimeOffset: 30000);

    bool autoSkip(String type, MediaKind kind, {bool intro = true, bool credits = true}) =>
        shouldAutoSkipMarker(marker: marker(type), kind: kind, autoSkipIntro: intro, autoSkipCredits: credits);

    test('auto-skips an intro marker on an episode', () {
      expect(autoSkip('intro', MediaKind.episode), isTrue);
    });

    test('never auto-skips an intro marker on a movie', () {
      expect(autoSkip('intro', MediaKind.movie), isFalse);
    });

    test('never auto-skips an intro marker on clips or unknown items', () {
      expect(autoSkip('intro', MediaKind.clip), isFalse);
      expect(autoSkip('intro', MediaKind.unknown), isFalse);
    });

    test('respects the intro setting on episodes', () {
      expect(autoSkip('intro', MediaKind.episode, intro: false), isFalse);
    });

    test('leaves credits auto-skip untouched, including on movies', () {
      expect(autoSkip('credits', MediaKind.movie), isTrue);
      expect(autoSkip('credits', MediaKind.episode), isTrue);
    });

    test('does not auto-skip credits when the setting is off', () {
      expect(autoSkip('credits', MediaKind.movie, credits: false), isFalse);
      expect(autoSkip('credits', MediaKind.episode, credits: false), isFalse);
    });

    test('treats other marker types as intro: episode only', () {
      expect(autoSkip('recap', MediaKind.movie), isFalse);
      expect(autoSkip('recap', MediaKind.episode), isTrue);
      expect(autoSkip('recap', MediaKind.episode, intro: false), isFalse);
    });
  });

  group('handlePromptDismissBackKey', () {
    test('ignores back keys when no prompt is visible', () {
      final dismissCount = 0;

      final result = handlePromptDismissBackKey(_keyUp(LogicalKeyboardKey.goBack), null);

      expect(result, KeyEventResult.ignored);
      expect(dismissCount, 0);
    });

    test('consumes key down and dismisses on key up', () {
      var dismissCount = 0;
      void dismissPrompt() => dismissCount++;

      final downResult = handlePromptDismissBackKey(_keyDown(LogicalKeyboardKey.goBack), dismissPrompt);
      final upResult = handlePromptDismissBackKey(_keyUp(LogicalKeyboardKey.goBack), dismissPrompt);

      expect(downResult, KeyEventResult.handled);
      expect(upResult, KeyEventResult.handled);
      expect(dismissCount, 1);
    });

    test('ignores non-back keys', () {
      var dismissCount = 0;

      final result = handlePromptDismissBackKey(_keyDown(LogicalKeyboardKey.arrowLeft), () => dismissCount++);

      expect(result, KeyEventResult.ignored);
      expect(dismissCount, 0);
    });
  });

  group('SkipMarkerButton', () {
    testWidgets('tap activates skip', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      var activateCount = 0;

      await _pumpSkipMarkerButton(
        tester,
        focusNode: focusNode,
        isAutoSkipActive: true,
        onActivate: () => activateCount++,
      );

      expect(find.text('Skip Intro (3)'), findsOneWidget);

      await tester.tap(find.byType(InkWell));
      await tester.pump();

      expect(activateCount, 1);
    });

    testWidgets('select activates skip', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      var activateCount = 0;

      await _pumpSkipMarkerButton(
        tester,
        focusNode: focusNode,
        isAutoSkipActive: true,
        onActivate: () => activateCount++,
      );

      focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();

      expect(activateCount, 1);
    });

    testWidgets('d-pad down moves focus without activating', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      var activateCount = 0;
      var focusDownCount = 0;

      await _pumpSkipMarkerButton(
        tester,
        focusNode: focusNode,
        isAutoSkipActive: true,
        onActivate: () => activateCount++,
        onFocusDown: () => focusDownCount++,
      );

      focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(activateCount, 0);
      expect(focusDownCount, 1);
    });

    testWidgets('tap activates when auto-skip is inactive', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      var activateCount = 0;

      await _pumpSkipMarkerButton(
        tester,
        focusNode: focusNode,
        isAutoSkipActive: false,
        onActivate: () => activateCount++,
      );

      expect(find.text('Skip Intro'), findsOneWidget);

      await tester.tap(find.byType(InkWell));
      await tester.pump();

      expect(activateCount, 1);
    });

    testWidgets('d-pad up, left and right release focus instead of dead-ending', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      var exitCount = 0;

      await _pumpSkipMarkerButton(
        tester,
        focusNode: focusNode,
        isAutoSkipActive: false,
        onActivate: () {},
        onFocusExit: () => exitCount++,
      );

      focusNode.requestFocus();
      await tester.pump();

      for (final key in [LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight]) {
        await tester.sendKeyEvent(key);
        await tester.pump();
      }

      expect(exitCount, 3);
    });

    testWidgets('credits at the end of the file become the next-episode button', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await _pumpSkipMarkerButton(
        tester,
        focusNode: focusNode,
        isAutoSkipActive: false,
        onActivate: () {},
        marker: MediaMarker(id: 2, type: 'credits', startTimeOffset: 1140000, endTimeOffset: 1200000),
        playerDuration: const Duration(minutes: 20),
        hasNextEpisode: true,
      );

      expect(find.text('Next Episode'), findsOneWidget);

      // That same label also lives on the Play Next card, so the card has to
      // win: two next-episode affordances at once is the bug this guards.
      expect(
        shouldShowSkipMarkerButton(
          hasFirstFrame: true,
          hasMarker: true,
          hasPlayNextPrompt: true,
          skipButtonDismissed: false,
          controlsVisible: false,
        ),
        isFalse,
      );
    });
  });

  group('mobileSkipZoneForTap', () {
    const size = Size(1000, 600);

    test('returns backward for left skip zone', () {
      expect(mobileSkipZoneForTap(position: const Offset(100, 300), size: size), isFalse);
    });

    test('returns forward for right skip zone', () {
      expect(mobileSkipZoneForTap(position: const Offset(900, 300), size: size), isTrue);
    });

    test('returns null outside skip zones', () {
      expect(mobileSkipZoneForTap(position: const Offset(500, 300), size: size), isNull);
      expect(mobileSkipZoneForTap(position: const Offset(100, 20), size: size), isNull);
      expect(mobileSkipZoneForTap(position: const Offset(900, 580), size: size), isNull);
    });
  });

  group('TimelineSlider', () {
    testWidgets('routes keyboard input through the custom focus handler', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      var keyEvents = 0;
      var seekEvents = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: TimelineSlider(
                position: const Duration(minutes: 1),
                duration: const Duration(minutes: 10),
                chapters: const [],
                chaptersLoaded: true,
                focusNode: focusNode,
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowRight) {
                    keyEvents++;
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                onSeek: (_) => seekEvents++,
                onSeekEnd: (_) {},
              ),
            ),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(keyEvents, 1);
      expect(seekEvents, 0);
    });

    testWidgets('does not pass chapters to painter when timeline markers are hidden', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: TimelineSlider(
                position: const Duration(minutes: 1),
                duration: const Duration(minutes: 10),
                chapters: [MediaChapter(id: 1, startTimeOffset: 300000)],
                chaptersLoaded: true,
                showChapterMarkersOnTimeline: false,
                onSeek: (_) {},
                onSeekEnd: (_) {},
              ),
            ),
          ),
        ),
      );

      final customPaint = tester.widget<CustomPaint>(
        find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is BufferRangePainter),
      );

      expect((customPaint.painter! as BufferRangePainter).chapters, isEmpty);
    });

    testWidgets('clamps stale position beyond duration before building slider', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: TimelineSlider(
                position: const Duration(minutes: 12),
                duration: const Duration(minutes: 10),
                chapters: const [],
                chaptersLoaded: true,
                onSeek: (_) {},
                onSeekEnd: (_) {},
              ),
            ),
          ),
        ),
      );

      final slider = tester.widget<Slider>(find.byType(Slider));

      expect(slider.value, const Duration(minutes: 10).inMilliseconds.toDouble());
      expect(slider.max, const Duration(minutes: 10).inMilliseconds.toDouble());
    });

    testWidgets('clamps stale position when duration is unknown', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: TimelineSlider(
                position: const Duration(minutes: 12),
                duration: Duration.zero,
                chapters: const [],
                chaptersLoaded: true,
                onSeek: (_) {},
                onSeekEnd: (_) {},
              ),
            ),
          ),
        ),
      );

      final slider = tester.widget<Slider>(find.byType(Slider));

      expect(slider.value, 0.0);
      expect(slider.max, 0.0);
    });

    testWidgets('timeline bar displays pending preview position while player position is stale', (tester) async {
      final player = FakeSyncPlayer(position: const Duration(minutes: 1), duration: const Duration(minutes: 10));
      addTearDown(player.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: VideoTimelineBar(
                player: player,
                chapters: const [],
                chaptersLoaded: true,
                previewPosition: const Duration(minutes: 4),
                onSeek: (_) {},
                onSeekEnd: (_) {},
              ),
            ),
          ),
        ),
      );

      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, const Duration(minutes: 4).inMilliseconds.toDouble());
    });

    Future<void> pumpScrubSlider(
      WidgetTester tester, {
      required List<Duration> seeks,
      required List<Duration> seekEnds,
      Duration duration = const Duration(minutes: 10),
      bool enabled = true,
      VoidCallback? onScrubStart,
      VoidCallback? onScrubEnd,
      Widget Function(Widget child)? wrap,
    }) async {
      Widget slider = SizedBox(
        width: 400,
        child: TimelineSlider(
          position: const Duration(minutes: 1),
          duration: duration,
          chapters: const [],
          chaptersLoaded: true,
          enabled: enabled,
          onSeek: seeks.add,
          onSeekEnd: seekEnds.add,
          onScrubStart: onScrubStart,
          onScrubEnd: onScrubEnd,
        ),
      );
      if (wrap != null) slider = wrap(slider);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: slider)),
        ),
      );
    }

    testWidgets('touch drag survives tooltip appearance and finalizes once', (tester) async {
      final seeks = <Duration>[];
      final seekEnds = <Duration>[];
      var scrubStarts = 0;
      var scrubEnds = 0;
      await pumpScrubSlider(
        tester,
        seeks: seeks,
        seekEnds: seekEnds,
        onScrubStart: () => scrubStarts++,
        onScrubEnd: () => scrubEnds++,
      );

      // Down at the center (200/400 → 5min), drag +100px (→ 7.5min). The
      // first scrub event makes the tooltip appear; the drag must keep
      // tracking through that rebuild and finalize exactly once.
      final gesture = await tester.startGesture(tester.getCenter(find.byType(TimelineSlider)));
      await tester.pump();
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(seeks, isNotEmpty);
      expect(seekEnds, hasLength(1));
      expect(scrubStarts, 1);
      expect(scrubEnds, 1);
      expect(seekEnds.single.inMilliseconds, closeTo(const Duration(minutes: 7, seconds: 30).inMilliseconds, 2000));
    });

    // The scrub lifecycle for keyboard/remote input is owned by
    // DesktopVideoControls (see the scrub-mode group below); the slider itself
    // only reports drag scrubs, so key events must leave it silent.
    testWidgets('keyboard input does not start a scrub lifecycle in the slider', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      var scrubStarts = 0;
      var scrubEnds = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: TimelineSlider(
                position: const Duration(minutes: 1),
                duration: const Duration(minutes: 10),
                chapters: const [],
                chaptersLoaded: true,
                focusNode: focusNode,
                onKeyEvent: (_, event) => KeyEventResult.handled,
                onSeek: (_) {},
                onSeekEnd: (_) {},
                onScrubStart: () => scrubStarts++,
                onScrubEnd: () => scrubEnds++,
              ),
            ),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(scrubStarts, 0);
      expect(scrubEnds, 0);
    });

    testWidgets('disposing mid-drag ends the scrub lifecycle', (tester) async {
      final seeks = <Duration>[];
      final seekEnds = <Duration>[];
      var scrubStarts = 0;
      var scrubEnds = 0;
      await pumpScrubSlider(
        tester,
        seeks: seeks,
        seekEnds: seekEnds,
        onScrubStart: () => scrubStarts++,
        onScrubEnd: () => scrubEnds++,
      );

      final gesture = await tester.startGesture(tester.getCenter(find.byType(TimelineSlider)));
      await tester.pump();
      expect(scrubStarts, 1);
      expect(scrubEnds, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await gesture.cancel();

      expect(scrubEnds, 1);
    });

    testWidgets('tap seeks to the tapped position', (tester) async {
      final seeks = <Duration>[];
      final seekEnds = <Duration>[];
      await pumpScrubSlider(tester, seeks: seeks, seekEnds: seekEnds);

      final topLeft = tester.getTopLeft(find.byType(TimelineSlider));
      final size = tester.getSize(find.byType(TimelineSlider));
      final gesture = await tester.startGesture(Offset(topLeft.dx + size.width * 0.75, topLeft.dy + size.height / 2));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(seekEnds, hasLength(1));
      expect(seekEnds.single.inMilliseconds, closeTo(const Duration(minutes: 7, seconds: 30).inMilliseconds, 2000));
    });

    testWidgets('drag starting on the slider is never stolen by ancestor recognizers', (tester) async {
      final seeks = <Duration>[];
      final seekEnds = <Duration>[];
      var verticalDragUpdates = 0;
      var longPresses = 0;
      await pumpScrubSlider(
        tester,
        seeks: seeks,
        seekEnds: seekEnds,
        wrap: (child) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: (_) => verticalDragUpdates++,
          onLongPressStart: (_) => longPresses++,
          child: child,
        ),
      );

      // Press-aim-drag: hold past the long-press deadline, then drag with a
      // vertical-dominant start. Without the eager claim, the long-press or
      // the vertical recognizer wins and the scrub is eaten.
      final gesture = await tester.startGesture(tester.getCenter(find.byType(TimelineSlider)));
      await tester.pump(const Duration(milliseconds: 600));
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(8, 12));
        await tester.pump();
      }
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(seekEnds, hasLength(1));
      expect(verticalDragUpdates, 0);
      expect(longPresses, 0);
    });

    testWidgets('ignores input when disabled', (tester) async {
      final seeks = <Duration>[];
      final seekEnds = <Duration>[];
      await pumpScrubSlider(tester, seeks: seeks, seekEnds: seekEnds, enabled: false);

      final gesture = await tester.startGesture(tester.getCenter(find.byType(TimelineSlider)));
      await tester.pump();
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(seeks, isEmpty);
      expect(seekEnds, isEmpty);
    });

    testWidgets('ignores input when duration is unknown', (tester) async {
      final seeks = <Duration>[];
      final seekEnds = <Duration>[];
      await pumpScrubSlider(tester, seeks: seeks, seekEnds: seekEnds, duration: Duration.zero);

      final gesture = await tester.startGesture(tester.getCenter(find.byType(TimelineSlider)));
      await tester.pump();
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(seeks, isEmpty);
      expect(seekEnds, isEmpty);
    });

    testWidgets('second finger is ignored mid-drag', (tester) async {
      final seeks = <Duration>[];
      final seekEnds = <Duration>[];
      await pumpScrubSlider(tester, seeks: seeks, seekEnds: seekEnds);

      final center = tester.getCenter(find.byType(TimelineSlider));
      final first = await tester.startGesture(center);
      await tester.pump();
      final seeksAfterDown = seeks.length;

      final second = await tester.startGesture(center + const Offset(100, 0));
      await tester.pump();
      await second.moveBy(const Offset(-80, 0));
      await tester.pump();
      expect(seeks.length, seeksAfterDown, reason: 'second pointer must not drive the scrub');

      await first.moveBy(const Offset(40, 0));
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pump();

      // 240/400 of 10min → 6min: follows the first pointer only.
      expect(seekEnds, hasLength(1));
      expect(seekEnds.single.inMilliseconds, closeTo(const Duration(minutes: 6).inMilliseconds, 2000));
    });
  });

  group('seekMultiplierForStreak', () {
    test('a lone press seeks by exactly the configured step', () {
      expect(seekMultiplierForStreak(0), 1.0);
    });

    test('quickly repeated presses climb the acceleration tiers', () {
      expect(seekMultiplierForStreak(1), 1.5);
      expect(seekMultiplierForStreak(5), 1.5);
      expect(seekMultiplierForStreak(6), 3.0);
      expect(seekMultiplierForStreak(15), 3.0);
      expect(seekMultiplierForStreak(16), 6.0);
      expect(seekMultiplierForStreak(30), 6.0);
      expect(seekMultiplierForStreak(31), 10.0);
    });
  });

  group('DesktopVideoControls scrub mode', () {
    late FakeSyncPlayer player;
    late List<Duration> seeks;
    late List<Duration> seekEnds;
    late List<String> scrubLifecycle;

    setUp(() async {
      LocaleSettings.setLocaleSync(AppLocale.en);
      await initializeDateFormatting('en');
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      await SettingsService.getInstance();
      seeks = [];
      seekEnds = [];
      scrubLifecycle = [];
    });

    tearDown(() => player.dispose());

    Future<DesktopVideoControlsState> pumpControls(WidgetTester tester, {required bool playing}) async {
      player = FakeSyncPlayer(
        playing: playing,
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 10),
      );
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controlsKey = GlobalKey<DesktopVideoControlsState>();
      final watchTogether = WatchTogetherProvider();
      addTearDown(watchTogether.dispose);
      // Bind the recorders to locals: the tree is disposed after the next
      // test's setUp has already swapped in fresh lists.
      final recordedSeeks = seeks;
      final recordedSeekEnds = seekEnds;
      final recordedLifecycle = scrubLifecycle;
      await tester.pumpWidget(
        ChangeNotifierProvider<WatchTogetherProvider>.value(
          value: watchTogether,
          child: MaterialApp(
            theme: ThemeData(extensions: const [_testTokens]),
            home: Scaffold(
              body: SizedBox(
                width: 1600,
                height: 900,
                child: DesktopVideoControls(
                  key: controlsKey,
                  player: player,
                  metadata: MediaItem(id: '1', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Test'),
                  chapters: const [],
                  chaptersLoaded: true,
                  seekTimeSmall: 10,
                  // ignore: no-empty-block - not exercised by these tests
                  onSeekToPreviousChapter: () {},
                  // ignore: no-empty-block - not exercised by these tests
                  onSeekToNextChapter: () {},
                  onSeek: recordedSeeks.add,
                  onSeekEnd: recordedSeekEnds.add,
                  onScrubStart: () => recordedLifecycle.add('start'),
                  onScrubEnd: () => recordedLifecycle.add('end'),
                  getReplayIcon: (_) => Icons.replay_10,
                  getForwardIcon: (_) => Icons.forward_10,
                  useDpadNavigation: true,
                ),
              ),
            ),
          ),
        ),
      );
      final state = controlsKey.currentState!;
      state.requestTimelineFocus();
      await tester.pump();
      return state;
    }

    Duration sliderPosition(WidgetTester tester) {
      final slider = tester.widget<Slider>(find.byType(Slider).first);
      return Duration(milliseconds: slider.value.round());
    }

    testWidgets('select on the focused timeline pauses and opens a preview', (tester) async {
      await pumpControls(tester, playing: true);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();

      expect(player.commandLog, contains('pause'));
      expect(scrubLifecycle, ['start']);
      expect(seeks, isEmpty);
      expect(seekEnds, isEmpty);
    });

    testWidgets('arrow keys move the preview without seeking, select commits once', (tester) async {
      await pumpControls(tester, playing: true);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
      }

      expect(seeks, isEmpty);
      expect(seekEnds, isEmpty);
      final previewed = sliderPosition(tester);
      expect(previewed, greaterThan(const Duration(minutes: 5)));

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();

      expect(seekEnds, hasLength(1));
      expect(seekEnds.single, previewed);
      expect(scrubLifecycle, ['start', 'end']);
      // Entering the scrub mode did the pausing, so confirming resumes.
      expect(player.commandLog.last, 'play');
    });

    testWidgets('back cancels the preview without seeking', (tester) async {
      await pumpControls(tester, playing: true);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(sliderPosition(tester), lessThan(const Duration(minutes: 5)));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(seeks, isEmpty);
      expect(seekEnds, isEmpty);
      expect(sliderPosition(tester), const Duration(minutes: 5));
      expect(scrubLifecycle, ['start', 'end']);
      expect(player.commandLog.last, 'play');
    });

    testWidgets('arrow keys on playing video keep seeking immediately', (tester) async {
      await pumpControls(tester, playing: true);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(seeks, hasLength(1));
      expect(seeks.single, const Duration(minutes: 5, seconds: 10));
      expect(scrubLifecycle, isEmpty);
      expect(player.commandLog, isNot(contains('pause')));
    });

    testWidgets('arrow keys on paused video open the preview instead of seeking', (tester) async {
      await pumpControls(tester, playing: false);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(seeks, isEmpty);
      expect(scrubLifecycle, ['start']);
      expect(sliderPosition(tester), const Duration(minutes: 5, seconds: 10));
      // The user paused, so confirming must not start playback again.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(seekEnds, hasLength(1));
      expect(player.commandLog, isNot(contains('play')));
    });

    testWidgets('repeated clicks accelerate the seek step', (tester) async {
      await pumpControls(tester, playing: true);

      for (var i = 0; i < 8; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
      }

      expect(seeks, hasLength(8));
      final firstStep = seeks.first - const Duration(minutes: 5);
      final lastStep = seeks.last - const Duration(minutes: 5);
      expect(firstStep, const Duration(seconds: 10));
      expect(lastStep, greaterThan(const Duration(seconds: 10)));
    });
  });

  group('shouldSkipDuplicateTimelineSeek', () {
    test('skips a matching non-transcode final seek', () {
      expect(
        shouldSkipDuplicateTimelineSeek(
          isTranscoding: false,
          lastDispatchedSeek: const Duration(minutes: 7, seconds: 30),
          finalSeek: const Duration(minutes: 7, seconds: 30),
        ),
        isTrue,
      );
    });

    test('does not skip matching transcode seek', () {
      expect(
        shouldSkipDuplicateTimelineSeek(
          isTranscoding: true,
          lastDispatchedSeek: const Duration(minutes: 7, seconds: 30),
          finalSeek: const Duration(minutes: 7, seconds: 30),
        ),
        isFalse,
      );
    });

    test('does not skip when no matching seek was already dispatched', () {
      expect(
        shouldSkipDuplicateTimelineSeek(
          isTranscoding: false,
          lastDispatchedSeek: const Duration(minutes: 7),
          finalSeek: const Duration(minutes: 7, seconds: 30),
        ),
        isFalse,
      );
      expect(
        shouldSkipDuplicateTimelineSeek(
          isTranscoding: false,
          lastDispatchedSeek: null,
          finalSeek: const Duration(minutes: 7, seconds: 30),
        ),
        isFalse,
      );
    });
  });

  group('SyncOffsetControl', () {
    testWidgets('uses 100ms slider steps without rendering tick marks', (tester) async {
      LocaleSettings.setLocaleSync(AppLocale.en);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [_testTokens]),
          home: Scaffold(
            body: SizedBox(
              width: 700,
              child: SyncOffsetControl(
                player: _FakeSyncPlayer(),
                propertyName: 'sub-delay',
                initialOffset: 0,
                labelText: 'Subtitles',
                onOffsetChanged: (_) async {},
                compact: true,
              ),
            ),
          ),
        ),
      );

      final slider = tester.widget<Slider>(find.byType(Slider));
      final sliderTheme = tester.widget<SliderTheme>(
        find.ancestor(of: find.byType(Slider), matching: find.byType(SliderTheme)).first,
      );

      expect(slider.min, -60000);
      expect(slider.max, 60000);
      expect(slider.divisions, 1200);
      expect((slider.max - slider.min) / slider.divisions!, 100);
      expect(sliderTheme.data.tickMarkShape, same(SliderTickMarkShape.noTickMark));
    });
  });
}

KeyDownEvent _keyDown(LogicalKeyboardKey key) {
  return KeyDownEvent(physicalKey: PhysicalKeyboardKey.escape, logicalKey: key, timeStamp: Duration.zero);
}

KeyUpEvent _keyUp(LogicalKeyboardKey key) {
  return KeyUpEvent(physicalKey: PhysicalKeyboardKey.escape, logicalKey: key, timeStamp: Duration.zero);
}

Future<void> _pumpSkipMarkerButton(
  WidgetTester tester, {
  required FocusNode focusNode,
  required bool isAutoSkipActive,
  required VoidCallback onActivate,
  VoidCallback? onFocusDown,
  VoidCallback? onFocusExit,
  MediaMarker? marker,
  Duration playerDuration = const Duration(minutes: 20),
  bool hasNextEpisode = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [_testTokens]),
      home: Scaffold(
        body: Center(
          child: SkipMarkerButton(
            marker: marker ?? MediaMarker(id: 1, type: 'intro', startTimeOffset: 10000, endTimeOffset: 45000),
            playerDuration: playerDuration,
            hasNextEpisode: hasNextEpisode,
            isAutoSkipActive: isAutoSkipActive,
            shouldShowAutoSkip: true,
            autoSkipDelay: 5,
            autoSkipProgress: 0.4,
            focusNode: focusNode,
            onActivate: onActivate,
            onFocusDown: onFocusDown ?? () {},
            onFocusExit: onFocusExit ?? () {},
          ),
        ),
      ),
    ),
  );
}

class _FakeSyncPlayer implements Player {
  @override
  PlayerState get state => PlayerState();

  @override
  Future<void> setProperty(String name, String value) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
