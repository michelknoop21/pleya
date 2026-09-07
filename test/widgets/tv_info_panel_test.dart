import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_source_info.dart';
import 'package:pleya/mpv/models.dart';
import 'package:pleya/mpv/player/player_state.dart';
import 'package:pleya/services/audio_output_coordinator.dart';
import 'package:pleya/services/audio_output_decision.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/shader_service.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/video_controls/models/track_controls_state.dart';
import 'package:pleya/widgets/video_controls/tv_info_panel.dart';
import 'package:pleya/widgets/video_controls/tv_info_panel/tv_audio_subtitle_tabs.dart';
import 'package:pleya/widgets/video_controls/tv_info_panel/tv_panel_widgets.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';
import 'package:pleya/widgets/video_controls/widgets/track_chapter_controls.dart';

import '../test_helpers/prefs.dart';
import '../test_helpers/watch_together_fakes.dart';

/// PNL2 / AUD1 / AUD2 / PNL1 / STR1 (DEC-101). Every test here was written
/// against the panel as it stood before mockup 33 and is red there: the pills
/// took no Select, the rows knew no LEFT/RIGHT, the sync view opened with
/// nothing focused, "Maximum volume" wrote only the ceiling, and the second
/// label line was dropped.
void main() {
  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    await initializeDateFormatting('en');
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    TvDetectionService.debugSetAppleTVOverride(true);
    AudioOutputCoordinator.bitstreamActive.value = false;
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    AudioOutputCoordinator.bitstreamActive.value = false;
  });

  testWidgets('opens on Info with the Info pill focused', (tester) async {
    final h = await _pumpPanel(tester);
    expect(find.text('Information'), findsOneWidget);
    expect(h.focusedPill(), 'information');
  });

  testWidgets('Select on a pill opens the tab and lands on its first row (PNL2)', (tester) async {
    final h = await _pumpPanel(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('DISPLAY'), findsOneWidget, reason: 'RIGHT on a pill switches the tab');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    final focused = h.focusedRow(tester);
    expect(focused, isNotNull, reason: 'Select on the Video pill must hand the focus to the rows');
    expect(focused!.title, 'Aspect ratio');
  });

  testWidgets('LEFT on an entered speed row steps the rate down, RIGHT steps it up (PNL2)', (tester) async {
    final h = await _pumpPanel(tester, initial: TvInfoPanelRequest.video);
    await h.focusRow(tester, 'Playback Speed');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(h.player.state.rate, 1.0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(h.player.state.rate, 0.75);

    // One press per frame: the row reads the rate from a stream, so two
    // presses without a frame in between both step off the same old value.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(h.player.state.rate, 1.25);
  });

  testWidgets('volume boost raises the ceiling and then the level (AUD1)', (tester) async {
    final h = await _pumpPanel(tester, initial: TvInfoPanelRequest.audio);
    await h.focusRow(tester, 'Volume boost');
    // Select enters the row and RIGHT steps it (DEC-107); Select no longer
    // cycles the value itself.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(h.player.writes, containsAllInOrder(['volume-max=150', 'volume=150.0']));
    expect(SettingsService.instance.read(SettingsService.maxVolume), 150);
    expect(SettingsService.instance.read(SettingsService.volume), 150.0);
    expect(find.text('+50%'), findsOneWidget);
  });

  testWidgets('during a bitstream the boost and loudness rows say why they are paused (DEC-013)', (tester) async {
    AudioOutputCoordinator.bitstreamActive.value = true;
    final h = await _pumpPanel(tester, initial: TvInfoPanelRequest.audio);
    expect(find.text('Paused'), findsNWidgets(3));
    await h.focusRow(tester, 'Volume boost');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(h.player.writes.where((w) => w.startsWith('volume')), isEmpty, reason: 'a paused row writes nothing');
  });

  testWidgets('audio tracks carry the technical second line (PNL1)', (tester) async {
    await _pumpPanel(tester, initial: TvInfoPanelRequest.audio);
    expect(find.text('English'), findsOneWidget);
    expect(find.textContaining('5.1'), findsWidgets, reason: 'the secondary TrackLabel line is shown');
  });

  testWidgets('the sync sub-view opens on its value row and RIGHT writes audio-delay (AUD2)', (tester) async {
    final h = await _pumpPanel(tester, initial: TvInfoPanelRequest.audio);
    await h.focusRow(tester, 'Audio Sync');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    final focused = h.focusedRow(tester);
    expect(focused?.title, 'Offset', reason: 'the sub-view must open with its value row focused');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(h.player.writes, contains('audio-delay=0.1'));
    expect(SettingsService.instance.read(SettingsService.audioSyncOffset), 100);

    // Menu goes back one layer: to the Sound tab, not out of the panel.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(h.closed, isFalse);
    expect(find.text('OUTPUT'), findsOneWidget);
  });

  testWidgets('priority is dimmed and skipped by traversal outside Auto', (tester) async {
    await SettingsService.instance.write(SettingsService.audioOutputMode, AudioOutputMode.pcm);
    final h = await _pumpPanel(tester, initial: TvInfoPanelRequest.audio);
    final priority = h.row(tester, 'Priority');
    expect(priority.dimmed, isTrue);
    expect(priority.canRequestFocus, isFalse);
  });

  testWidgets('an entered value row clamps at its ends instead of wrapping (PNL2)', (tester) async {
    // Wrapping was the old behaviour and it is wrong: RIGHT on +200% dropped
    // the boost back to Off. Under DEC-107 the clamp no longer doubles as the
    // way out of the column — that is the row's rest state — but a step past
    // the end must still do nothing.
    expect(stepValueClamped(kTvPanelVolumeBoostSteps, 300, 1), isNull);
    expect(stepValueClamped(kTvPanelVolumeBoostSteps, 100, -1), isNull);
    expect(stepValueClamped(kTvPanelVolumeBoostSteps, 150, 1), 200);

    await SettingsService.instance.write(SettingsService.maxVolume, 300);
    final h = await _pumpPanel(tester, initial: TvInfoPanelRequest.audio);
    final boost = h.row(tester, 'Volume boost');
    expect(boost.onStepRight, isNull, reason: 'at the top there is nothing to step to');
    expect(boost.onStepLeft, isNotNull);
    expect(boost.stepsValue, isTrue, reason: 'Select enters this row, it no longer cycles the value');
  });

  // PLR5 / DEC-107. Michel on hardware: from a value row the other column is
  // unreachable unless you change the value. Zoom sits at 100%, in the middle
  // of `kTvPanelZoomPresets`, so `clampedSteps` hands back neither direction
  // and the old row swallowed both. Red before DEC-107 on both counts: the
  // ring stayed put and the value moved.
  testWidgets('a value row at rest lets RIGHT cross to the other column without stepping (PLR5)', (tester) async {
    final zoom = <double>[];
    final h = await _pumpFullVideoTab(tester, onVideoZoomChanged: zoom.add);
    await h.focusRow(tester, 'Zoom');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(zoom, isEmpty, reason: 'a row at rest must not step');
    expect(h.focusedRow(tester)?.title, isNot('Zoom'), reason: 'RIGHT belongs to the traversal until Select enters');
  });

  testWidgets('Select enters a value row, Menu leaves it and keeps the panel open (PLR5)', (tester) async {
    final zoom = <double>[];
    final h = await _pumpFullVideoTab(tester, onVideoZoomChanged: zoom.add);
    await h.focusRow(tester, 'Zoom');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(
      find.text(t.videoControls.tvPanel.hintValueRow),
      findsOneWidget,
      reason: 'the footer says which state holds',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(zoom, [1.1], reason: 'an entered row steps');
    expect(h.focusedRow(tester)?.title, 'Zoom', reason: 'and keeps the ring');

    // Menu peels the row first. The panel must survive it, or DEC-107 would
    // hand PLR6 a second way to trap the remote.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(h.closed, isFalse, reason: 'Menu leaves the row before it closes the panel');
    expect(find.text(t.videoControls.tvPanel.hint), findsOneWidget);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(h.closed, isTrue, reason: 'and the next Menu closes it');
  });

  testWidgets('moving the focus away leaves the entered row behind (PLR5)', (tester) async {
    final zoom = <double>[];
    final h = await _pumpFullVideoTab(tester, onVideoZoomChanged: zoom.add);
    await h.focusRow(tester, 'Zoom');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(h.focusedRow(tester)?.title, isNot('Zoom'));
    expect(find.text(t.videoControls.tvPanel.hint), findsOneWidget, reason: 'no row is entered any more');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(zoom, isEmpty, reason: 'the entered state does not travel with the ring');
  });

  testWidgets('a chapter jump from the panel reports the seek (Watch Together)', (tester) async {
    final seeks = <Duration>[];
    final completed = <Duration>[];
    final h = await _pumpPanel(
      tester,
      initial: TvInfoPanelRequest.chapters,
      chapters: [
        MediaChapter(id: 1, index: 0, startTimeOffset: 0, title: 'Arrakis'),
        MediaChapter(id: 2, index: 1, startTimeOffset: 600000, title: 'Sietch Tabr'),
      ],
      onSeekToChapter: (position) async => seeks.add(position),
      onSeekCompleted: completed.add,
    );
    await h.focusRow(tester, '2. Sietch Tabr');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(seeks, [const Duration(minutes: 10)]);
    expect(completed, seeks, reason: 'onSeekCompleted is the only path to WatchTogetherProvider.onLocalSeek');
  });

  testWidgets('the Video pill is translated (STR1) and the stats row says On, not OK', (tester) async {
    await SettingsService.instance.write(SettingsService.showPerformanceOverlay, true);
    await _pumpPanel(tester, initial: TvInfoPanelRequest.video);
    expect(find.text('Video'), findsOneWidget);
    expect(find.text('OK'), findsNothing);
  });

  testWidgets('Menu closes the panel from a focused row (PLR6 contract)', (tester) async {
    final h = await _pumpPanel(tester, initial: TvInfoPanelRequest.video);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(h.focusedRow(tester), isNotNull, reason: 'the row must own the focus before Menu is judged');

    // On Apple TV `handleBackKeyAction` runs onBack on the KeyDown and swallows
    // the KeyUp, so the down alone must close it. PLR6 reports the panel as
    // inescapable on hardware; this proves the Dart side is not the reason.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(h.closed, isTrue);
  });

  // PLR4. The hardware photo shows the Video tab losing its last rows under
  // the card edge. The old cap was `min(height * 0.56, 620)`, a fraction with
  // no relation to what the tab needs; at 1080 it happened to leave fifty
  // pixels of slack, which is why the panel measured as fitting here while it
  // did not on the set. These three heights pin the property the cap now has:
  // the card is bounded by the title-safe band, so it grows to its content
  // instead of hiding rows. Red before the fix at 900 (right column 51px
  // hidden) and at 720 (both columns, 89 and 152).
  for (final height in [1080.0, 900.0, 720.0]) {
    testWidgets('the full Video tab fits inside the card at ${height.toInt()}p (PLR4)', (tester) async {
      await _pumpFullVideoTab(tester, viewSize: Size(1920, height));

      expect(find.byType(TvPanelRow), findsNWidgets(11), reason: 'five display rows and six playback rows');
      final extents = _columnScrollExtents(tester);
      expect(extents, hasLength(2), reason: 'the Video tab is two columns, each with its own scroll view');
      expect(
        extents,
        everyElement(0.0),
        reason: 'no row may sit under the card edge without an affordance; extents were $extents',
      );
    });
  }

  // PLR7. The panel used to write its own pixel values and never asked
  // `TvLayoutConstants.scaleOf` anything, which made it the one TV surface that
  // did not move with the ten-foot scale. The Apple TV renders Flutter at about
  // 1038x584 logical with a 1.85 device ratio (DEC-028), so `scaleOf` sits on
  // its 0.85 floor there: a row label stood at 17 logical, 31.5 reference px,
  // against hoofdstuk 8.3's own 23-26 band for that tier, and a row was 62 tall
  // where the same ladder asks for 54.4. Red on the old values at both sizes.
  for (final (name, viewSize, scale) in [
    ('the Apple TV viewport', const Size(1038, 584), 0.85),
    ('the canonical canvas', const Size(1920, 1080), 1.0),
  ]) {
    testWidgets('rows follow the shared ten-foot ladder on $name (PLR7)', (tester) async {
      await _pumpFullVideoTab(tester, viewSize: viewSize);

      final title = tester.widget<Text>(find.text('Zoom'));
      expect(
        title.style?.fontSize,
        closeTo(TvSourcePickerLayout.rowPrimaryFontSize * scale, 0.01),
        reason: 'the row label is hoofdstuk 8.3s row-primary tier, not a number of its own',
      );

      final row = find.ancestor(of: find.text('Zoom'), matching: find.byType(TvPanelRow)).first;
      expect(
        tester.getSize(row).height,
        closeTo(TvSourcePickerLayout.rowMinHeight * scale, 0.01),
        reason: 'a single-line row rests on the shared minimum height',
      );
    });
  }

  testWidgets('on TV the tune button asks for the panel instead of a sheet (PLR3)', (tester) async {
    final player = _PanelPlayer();
    addTearDown(player.dispose);
    TvInfoPanelRequest? requested;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrackChapterControls(
            player: player,
            chapters: const [],
            chaptersLoaded: true,
            trackControlsState: const TrackControlsState(),
            onOpenTvPanel: (request) => requested = request,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(t.videoControls.settingsButton));
    await tester.pumpAndSettle();
    expect(requested, TvInfoPanelRequest.video);
    expect(
      find.text(t.videoControls.settingsButton),
      findsNothing,
      reason: 'no sheet title: nothing opened but the panel',
    );
  });
}

/// The scroll extent of each [TvPanelColumns] column, in the order they are
/// laid out. Zero means the column fits: nothing is hidden under the card edge.
List<double> _columnScrollExtents(WidgetTester tester) {
  final columns = find.descendant(of: find.byType(TvPanelColumns), matching: find.byType(Scrollable));
  return List<double>.generate(
    columns.evaluate().length,
    (i) => tester.state<ScrollableState>(columns.at(i)).position.maxScrollExtent,
  );
}

/// The Video tab with every row a real Apple TV builds. The default harness
/// leaves four of them out — no shader service, no ambient support, no
/// chapters and no second version — which is exactly why the panel measured
/// as fitting while the hardware photo shows it does not (PLR4).
Future<_Harness> _pumpFullVideoTab(
  WidgetTester tester, {
  Size viewSize = const Size(1920, 1080),
  ValueChanged<double>? onVideoZoomChanged,
}) async {
  final shaderPlayer = _PanelPlayer();
  addTearDown(shaderPlayer.dispose);
  return _pumpPanel(
    tester,
    initial: TvInfoPanelRequest.video,
    ambientSupported: true,
    viewSize: viewSize,
    chapters: [
      MediaChapter(id: 1, index: 0, startTimeOffset: 0, title: 'Arrakis'),
      MediaChapter(id: 2, index: 1, startTimeOffset: 2760000, title: 'The Water of Life'),
    ],
    trackControlsState: TrackControlsState(
      // ignore: no-empty-block - the tab only needs the row to exist
      onCycleBoxFitMode: () {},
      onVideoZoomChanged: onVideoZoomChanged ?? (_) {},
      audioSyncOffset: 0,
      subtitleSyncOffset: 0,
      canControl: true,
      shaderService: ShaderService(shaderPlayer),
      serverSupportsTranscoding: true,
      // ignore: no-empty-block - the tab only needs the row to exist
      onSwitchQualityPreset: (_) {},
    ),
  );
}

class _Harness {
  _Harness(this.player);

  final _PanelPlayer player;
  bool closed = false;

  TvPanelRow row(WidgetTester tester, String title) {
    final finder = find.byWidgetPredicate((w) => w is TvPanelRow && w.title == title);
    expect(finder, findsOneWidget, reason: 'row "$title"');
    return tester.widget<TvPanelRow>(finder);
  }

  /// Focuses a row by its title through its own node, the way the pill's DOWN
  /// or the traversal would, then lets the frame settle.
  Future<void> focusRow(WidgetTester tester, String title) async {
    final finder = find.byWidgetPredicate((w) => w is TvPanelRow && w.title == title);
    expect(finder, findsOneWidget, reason: 'row "$title"');
    final focus = find.descendant(of: finder, matching: find.byType(Focus)).first;
    tester.widget<Focus>(focus).focusNode!.requestFocus();
    await tester.pumpAndSettle();
  }

  /// The row whose focus node holds primary focus, or null.
  TvPanelRow? focusedRow(WidgetTester tester) {
    for (final element in find.byType(TvPanelRow).evaluate()) {
      final row = element.widget as TvPanelRow;
      final focusFinder = find.descendant(of: find.byWidget(row), matching: find.byType(Focus)).first;
      final node = tester.widget<Focus>(focusFinder).focusNode;
      if (node != null && node.hasPrimaryFocus) return row;
    }
    return null;
  }

  /// The pill that holds primary focus, by tab name, or null.
  String? focusedPill() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return null;
    final label = primary.debugLabel ?? '';
    // The pill nodes are labelled TvInfoPill<index>.
    final match = RegExp(r'TvInfoPill(\d+)').firstMatch(label);
    if (match == null) return null;
    return TvInfoPanelTab.values[int.parse(match.group(1)!)].name;
  }
}

Future<_Harness> _pumpPanel(
  WidgetTester tester, {
  TvInfoPanelRequest initial = TvInfoPanelRequest.information,
  List<MediaChapter> chapters = const [],
  Future<void> Function(Duration)? onSeekToChapter,
  void Function(Duration)? onSeekCompleted,
  bool ambientSupported = false,
  TrackControlsState? trackControlsState,
  Size viewSize = const Size(1920, 1080),
}) async {
  final player = _PanelPlayer();
  addTearDown(player.dispose);
  final harness = _Harness(player);
  tester.view.physicalSize = viewSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: viewSize.width,
          height: viewSize.height,
          child: TvInfoPanel(
            player: player,
            metadata: MediaItem(id: '1', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Dune: Part Two'),
            trackControlsState:
                trackControlsState ??
                TrackControlsState(
                  // ignore: no-empty-block - the tab only needs the row to exist
                  onCycleBoxFitMode: () {},
                  audioSyncOffset: 0,
                  subtitleSyncOffset: 0,
                  canControl: true,
                ),
            chapters: chapters,
            onSeekToChapter: onSeekToChapter,
            onSeekCompleted: onSeekCompleted,
            isAmbientEnabled: false,
            ambientSupported: ambientSupported,
            // ignore: no-empty-block - ambient is not exercised here
            onSetAmbientIntensity: (_) {},
            onClose: () => harness.closed = true,
            initial: initial,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

/// A player with two audio tracks and a recorder for every property write,
/// so a test can prove what mpv was told and in which order.
class _PanelPlayer extends FakeSyncPlayer {
  _PanelPlayer() : super(playing: true, duration: const Duration(minutes: 166));

  static const _english = AudioTrack(id: '1', language: 'en', codec: 'eac3', channels: 6);
  static const _dutch = AudioTrack(id: '2', language: 'nl', codec: 'ac3', channels: 6);

  final writes = <String>[];

  /// `ShaderService.isSupported` gates on this, and the Shaders row gates on
  /// that. Without it the Video tab silently loses a row.
  @override
  String get playerType => 'mpv';

  @override
  PlayerState get state => super.state.copyWith(
    tracks: const Tracks(audio: [_english, _dutch]),
    track: const TrackSelection(audio: _english),
  );

  @override
  Future<void> setProperty(String name, String value) async {
    writes.add('$name=$value');
  }

  @override
  Future<String?> getProperty(String name) async => null;

  @override
  Future<void> setVolume(double volume) async {
    writes.add('volume=$volume');
  }

  @override
  Future<void> selectAudioTrack(AudioTrack track) async {
    writes.add('aid=${track.id}');
  }

  @override
  Future<void> selectSubtitleTrack(SubtitleTrack track) async {
    writes.add('sid=${track.id}');
  }

  @override
  Future<void> setAudioNormalization(AudioLoudness loudness) async {
    writes.add('af=${loudness.mpvFilter}');
  }
}
