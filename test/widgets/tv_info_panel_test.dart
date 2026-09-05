import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/mpv/models.dart';
import 'package:pleya/mpv/player/player_state.dart';
import 'package:pleya/services/audio_output_coordinator.dart';
import 'package:pleya/services/audio_output_decision.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/video_controls/models/track_controls_state.dart';
import 'package:pleya/widgets/video_controls/tv_info_panel.dart';
import 'package:pleya/widgets/video_controls/tv_info_panel/tv_panel_widgets.dart';
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

  testWidgets('LEFT on the speed row steps the rate down, RIGHT steps it up (PNL2)', (tester) async {
    final h = await _pumpPanel(tester, initial: TvInfoPanelRequest.video);
    await h.focusRow(tester, 'Playback Speed');
    expect(h.player.state.rate, 1.0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(h.player.state.rate, 0.75);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(h.player.state.rate, 1.25);
  });

  testWidgets('volume boost raises the ceiling and then the level (AUD1)', (tester) async {
    final h = await _pumpPanel(tester, initial: TvInfoPanelRequest.audio);
    await h.focusRow(tester, 'Volume boost');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
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

  testWidgets('the Video pill is translated (STR1) and the stats row says On, not OK', (tester) async {
    await SettingsService.instance.write(SettingsService.showPerformanceOverlay, true);
    await _pumpPanel(tester, initial: TvInfoPanelRequest.video);
    expect(find.text('Video'), findsOneWidget);
    expect(find.text('OK'), findsNothing);
  });

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
    expect(find.text(t.videoControls.settingsButton), findsNothing, reason: 'no sheet title: nothing opened but the panel');
  });
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

Future<_Harness> _pumpPanel(WidgetTester tester, {TvInfoPanelRequest initial = TvInfoPanelRequest.information}) async {
  final player = _PanelPlayer();
  addTearDown(player.dispose);
  final harness = _Harness(player);
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1920,
          height: 1080,
          child: TvInfoPanel(
            player: player,
            metadata: MediaItem(id: '1', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Dune: Part Two'),
            trackControlsState: TrackControlsState(
              // ignore: no-empty-block - the tab only needs the row to exist
              onCycleBoxFitMode: () {},
              audioSyncOffset: 0,
              subtitleSyncOffset: 0,
              canControl: true,
            ),
            chapters: const [],
            onSeekToChapter: null,
            isAmbientEnabled: false,
            ambientSupported: false,
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
