import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/mpv/models.dart';
import 'package:pleya/mpv/player/player.dart';
import 'package:pleya/mpv/player/player_state.dart';
import 'package:pleya/mpv/player/player_streams.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/video_controls/sheets/video_settings_sheet.dart';

import '../test_helpers/prefs.dart';

const _testTokens = MonoTokens(
  radiusSm: 4,
  radiusMd: 8,
  space: 8,
  fast: Duration(milliseconds: 100),
  normal: Duration(milliseconds: 200),
  slow: Duration(milliseconds: 300),
  bg: Colors.black,
  surface: Color(0xFF111111),
  surfaceElevated: Color(0xFF2F2F2F),
  outline: Color(0xFF333333),
  text: Colors.white,
  textMuted: Color(0xFFAAAAAA),
  isLight: false,
  accent: Color(0xFFF42B1F),
  accentAlt: Color(0xFFFFB020),
  splashFactory: NoSplash.splashFactory,
);

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  testWidgets('shows the audio output mode on supported TV-style surfaces', (tester) async {
    await _pumpSheet(tester);

    await tester.scrollUntilVisible(find.text('Audio Output Mode'), 500, scrollable: find.byType(Scrollable).first);

    expect(find.text('Audio Output Mode'), findsOneWidget);
    // Off-device there is no route to report, so the mode shows on its own
    // rather than as "Auto (now: …)".
    expect(find.text('Auto'), findsOneWidget);
  });

  testWidgets('shows the audio output mode on Apple TV too', (tester) async {
    // Apple TV used to be excluded from this setting entirely; a receiver over
    // HDMI is exactly the case Dolby passthrough exists for.
    TvDetectionService.debugSetAppleTVOverride(true);

    await _pumpSheet(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    expect(find.text('Audio Output Mode'), findsOneWidget);
  });

  // OVR2, through the caller that owns the regression rather than through the
  // resolver alone. The compact sync bar is the one surface in the app that
  // places itself, and OVR1b centred it on a television. The numbers come from
  // the production constants, so this cannot drift away from what ships.
  testWidgets('the compact sync bar keeps its top edge and its box on Apple TV', (tester) async {
    const tvCanvas = Size(1038, 584);
    const inset = 1038 * (72 / 1920);
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

    await _pumpSheetInHost(tester, canvas: tvCanvas);

    await tester.scrollUntilVisible(find.text('Audio Sync'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Audio Sync'));
    await tester.pumpAndSettle();

    final bar = tester.getRect(
      find.descendant(of: find.byType(CustomSingleChildLayout), matching: find.byType(Material)).first,
    );

    expect(bar.width, moreOrLessEquals(kCompactSyncBarConstraints.maxWidth, epsilon: 1));
    expect(bar.height, moreOrLessEquals(kCompactSyncBarConstraints.maxHeight, epsilon: 1));
    expect(kCompactSyncBarAlignment, Alignment.topCenter, reason: 'the caller still asks for the top edge');
    expect(bar.top, moreOrLessEquals(inset, epsilon: 1), reason: 'against the top, one safe inset down');
    expect(bar.center.dy, lessThan(tvCanvas.height / 4), reason: 'OVR1b put this at 292, the middle of the picture');
    expect(bar.center.dx, moreOrLessEquals(tvCanvas.width / 2, epsilon: 1));
  });
}

Future<void> _pumpSheetInHost(WidgetTester tester, {required Size canvas}) async {
  tester.view.physicalSize = canvas;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [_testTokens]),
      home: OverlaySheetHost(
        child: Scaffold(
          body: VideoSettingsSheet(
            player: _FakeSettingsPlayer(),
            audioSyncOffset: 0,
            subtitleSyncOffset: 0,
            canControl: false,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpSheet(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [_testTokens]),
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 700,
          child: VideoSettingsSheet(
            player: _FakeSettingsPlayer(),
            audioSyncOffset: 0,
            subtitleSyncOffset: 0,
            canControl: false,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeSettingsPlayer implements Player {
  _FakeSettingsPlayer()
    : _streams = PlayerStreams(
        playing: const Stream<bool>.empty(),
        completed: const Stream<bool>.empty(),
        buffering: const Stream<bool>.empty(),
        position: const Stream<Duration>.empty(),
        duration: const Stream<Duration>.empty(),
        seekable: const Stream<bool>.empty(),
        buffer: const Stream<Duration>.empty(),
        volume: const Stream<double>.empty(),
        rate: const Stream<double>.empty(),
        tracks: const Stream<Tracks>.empty(),
        track: const Stream<TrackSelection>.empty(),
        log: const Stream<PlayerLog>.empty(),
        error: const Stream<PlayerError>.empty(),
        audioDevice: const Stream<AudioDevice>.empty(),
        audioDevices: const Stream<List<AudioDevice>>.empty(),
        bufferRanges: const Stream<List<BufferRange>>.empty(),
        playbackRestart: const Stream<void>.empty(),
        backendSwitched: const Stream<void>.empty(),
      );

  final PlayerStreams _streams;

  @override
  PlayerState get state => const PlayerState();

  @override
  PlayerStreams get streams => _streams;

  @override
  String get playerType => 'exoplayer';

  @override
  Future<void> setAudioPassthrough(bool enabled) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
