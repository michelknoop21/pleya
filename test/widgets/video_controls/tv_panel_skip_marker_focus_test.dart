import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/media_source_info.dart';
import 'package:pleya/mpv/mpv.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/playback_state_provider.dart';
import 'package:pleya/providers/shader_provider.dart';
import 'package:pleya/services/apple_tv_remote_touch_service.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/watch_together/providers/watch_together_provider.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
import 'package:pleya/widgets/video_controls/player_chrome_controller.dart';
import 'package:pleya/widgets/video_controls/tv_info_panel.dart';
import 'package:pleya/widgets/video_controls/video_controls.dart';
import 'package:pleya/widgets/video_controls/widgets/player_toast_indicator.dart';
import 'package:pleya/widgets/video_controls/widgets/skip_marker_button.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';
import '../../test_helpers/watch_together_fakes.dart';

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

const _serverId = 'srv-skip';

/// The intro the hardware run sat in: 7:00 to 8:00, playback at 7:19.
final _intro = MediaMarker(id: 1, type: 'intro', startTimeOffset: 420000, endTimeOffset: 480000);

/// Feeds the position stream, which the real player drives and the shared
/// fake leaves empty: the skip button comes and goes with it.
class _PositionPlayer extends FakeSyncPlayer {
  _PositionPlayer() : super(playing: true, position: const Duration(minutes: 7, seconds: 19));

  final _position = StreamController<Duration>.broadcast();

  @override
  String get playerType => 'mpv';

  void moveTo(Duration position) {
    setPosition(position);
    _position.add(position);
  }

  @override
  PlayerStreams get streams {
    final s = super.streams;
    return PlayerStreams(
      playing: s.playing,
      completed: s.completed,
      buffering: s.buffering,
      position: _position.stream,
      duration: s.duration,
      seekable: s.seekable,
      buffer: s.buffer,
      volume: s.volume,
      rate: s.rate,
      tracks: s.tracks,
      track: s.track,
      log: s.log,
      error: s.error,
      audioDevice: s.audioDevice,
      audioDevices: s.audioDevices,
      bufferRanges: s.bufferRanges,
      playbackRestart: s.playbackRestart,
      backendSwitched: s.backendSwitched,
    );
  }

  @override
  Future<void> dispose({bool preserveDisplayMode = false}) async {
    await _position.close();
    await super.dispose(preserveDisplayMode: preserveDisplayMode);
  }
}

/// Answers the extras request when the test says so, so the marker can land
/// after the panel is already open, the order build 389 showed.
class _MarkerClient implements MediaServerClient {
  final extras = Completer<PlaybackExtras>();

  @override
  ServerId get serverId => ServerId(_serverId);

  @override
  Future<PlaybackExtras> fetchPlaybackExtras(
    String itemId, {
    String? introPattern,
    String? creditsPattern,
    bool forceChapterFallback = false,
    bool forceRefresh = false,
  }) => extras.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  _Harness(this.player, this.client, this.chrome);

  final _PositionPlayer player;
  final _MarkerClient client;
  final PlayerChromeController chrome;
  int backCalls = 0;
}

void main() {
  late DateTime now;
  late AppleTvRemoteTouchService touch;
  final emitted = <LogicalKeyboardKey>[];

  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    await initializeDateFormatting('en');
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    TvDetectionService.debugSetAppleTVOverride(true);
    now = DateTime(2026, 10, 20, 22, 30);
    emitted.clear();
    touch = AppleTvRemoteTouchService(
      simulateKeyPress: emitted.add,
      simulateKeyDown: (_) {},
      simulateKeyUp: (_) {},
      scheduleFrame: () {},
      now: () => now,
    );
    AppleTvRemoteTouchService.debugInstanceOverride = touch;
  });

  tearDown(() {
    AppleTvRemoteTouchService.debugInstanceOverride = null;
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  Future<_Harness> pumpPlayer(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // The test host is macOS, so the controls ask the window manager about
    // always-on-top. Nothing here is about windows.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => false,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('window_manager'), null),
    );

    final player = _PositionPlayer();
    addTearDown(player.dispose);
    final client = _MarkerClient();
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final servers = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(servers.dispose);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    final watchTogether = WatchTogetherProvider();
    addTearDown(watchTogether.dispose);
    final playback = PlaybackStateProvider();
    addTearDown(playback.dispose);
    final shaders = ShaderProvider();
    addTearDown(shaders.dispose);
    final chrome = PlayerChromeController(controlsVisible: false);
    addTearDown(chrome.dispose);
    final toasts = PlayerToastController();
    addTearDown(toasts.dispose);
    final harness = _Harness(player, client, chrome);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
          ChangeNotifierProvider<WatchTogetherProvider>.value(value: watchTogether),
          ChangeNotifierProvider<PlaybackStateProvider>.value(value: playback),
          ChangeNotifierProvider<ShaderProvider>.value(value: shaders),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [_tokens]),
          home: InputModeTracker(
            child: Material(
              color: Colors.black,
              child: PlexVideoControls(
                player: player,
                metadata: MediaItem(
                  id: '56532',
                  backend: MediaBackend.plex,
                  kind: MediaKind.episode,
                  title: 'Can It Be All So Simple',
                  serverId: _serverId,
                ),
                toastController: toasts,
                chromeController: chrome,
                onBack: () => harness.backCalls++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return harness;
  }

  /// A downward swipe over the touch surface, the way the remote sends it:
  /// the service tags the arrow as a swipe, then the key reaches the app.
  Future<void> swipeDown(WidgetTester tester) async {
    await touch.handleMessage({'type': 'started', 'x': 960.0, 'y': 540.0});
    for (final y in [580.0, 640.0, 720.0, 820.0]) {
      now = now.add(const Duration(milliseconds: 20));
      await touch.handleMessage({'type': 'move', 'x': 960.0, 'y': y});
    }
    expect(emitted, contains(LogicalKeyboardKey.arrowDown), reason: 'the swipe must produce arrowDown');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await touch.handleMessage({'type': 'ended', 'x': 960.0, 'y': 820.0});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> pressMenu(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
  }

  Future<void> landIntro(WidgetTester tester, _Harness h) async {
    h.client.extras.complete(PlaybackExtras(chapters: const [], markers: [_intro]));
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  bool focusInPanel(WidgetTester tester) {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return false;
    final panel = tester.element(find.byType(TvInfoPanel));
    return primary.context != null &&
        (primary.context == panel || primary.context!.findAncestorWidgetOfExactType<TvInfoPanel>() != null);
  }

  FocusNode skipNode(WidgetTester tester) => tester
      .widget<FocusableWrapper>(
        find.descendant(of: find.byType(SkipMarkerButton), matching: find.byType(FocusableWrapper)),
      )
      .focusNode!;

  // Build 389, log 9l62r: the swipe opened the panel on its information pill,
  // the intro started a moment later and its button took the focus (the next
  // RIGHT reached the skip button's onNavigateRight, which parks focus on the
  // player root). From there every Menu press was ignored, because the
  // player stands aside for the panel while it is open.
  testWidgets('Menu sluit het paneel als de intro opduikt terwijl het open staat', (tester) async {
    final h = await pumpPlayer(tester);
    await swipeDown(tester);
    expect(find.byType(TvInfoPanel), findsOneWidget);

    await landIntro(tester, h);
    expect(find.byType(SkipMarkerButton), findsOneWidget, reason: 'the intro is on screen behind the panel');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    await pressMenu(tester);
    expect(find.byType(TvInfoPanel), findsNothing, reason: 'Menu closes the panel');
    expect(h.backCalls, 0, reason: 'Menu closes the panel, it does not leave the player');
  });

  testWidgets('een intro die opduikt terwijl het paneel open staat pakt de focus niet', (tester) async {
    final h = await pumpPlayer(tester);
    await swipeDown(tester);
    expect(focusInPanel(tester), isTrue, reason: 'the panel lands on its information pill');

    await landIntro(tester, h);
    expect(find.byType(SkipMarkerButton), findsOneWidget);
    expect(focusInPanel(tester), isTrue, reason: 'the skip button must not take focus away from an open panel');
  });

  testWidgets('staat de focus toch buiten het paneel, dan sluit Menu het nog steeds', (tester) async {
    final h = await pumpPlayer(tester);
    await swipeDown(tester);
    await landIntro(tester, h);

    // However it got there: focus on the skip button, then RIGHT, which hands
    // it to the player root, exactly the hardware path.
    skipNode(tester).requestFocus();
    await tester.pump();
    expect(focusInPanel(tester), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(focusInPanel(tester), isFalse);

    await pressMenu(tester);
    expect(find.byType(TvInfoPanel), findsNothing, reason: 'the last-resort path closes the panel');
    expect(h.backCalls, 0);
  });

  testWidgets('verdwijnt de knop onder de focus, dan sluit Menu het paneel zonder de speler te verlaten', (
    tester,
  ) async {
    final h = await pumpPlayer(tester);
    await swipeDown(tester);
    await landIntro(tester, h);

    skipNode(tester).requestFocus();
    await tester.pump();
    // The intro ends under the focused button: its node unfocuses and the
    // primary focus falls out of the player's subtree.
    h.player.moveTo(const Duration(minutes: 8, seconds: 1));
    await tester.pump();
    await tester.pump();
    expect(find.byType(SkipMarkerButton), findsNothing);
    expect(focusInPanel(tester), isFalse);

    await pressMenu(tester);
    expect(find.byType(TvInfoPanel), findsNothing);
    expect(h.backCalls, 0);
  });

  testWidgets('met de focus in het paneel sluit Menu precies één laag', (tester) async {
    final h = await pumpPlayer(tester);
    await swipeDown(tester);
    expect(focusInPanel(tester), isTrue);

    await pressMenu(tester);
    expect(find.byType(TvInfoPanel), findsNothing);
    expect(h.backCalls, 0, reason: 'one press, one layer');

    // The next Menu belongs to the player again: controls hidden, so it
    // leaves the player, once.
    await pressMenu(tester);
    expect(h.backCalls, 1);
  });
}
