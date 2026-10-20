import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/watch_together/providers/watch_together_provider.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/playback_state_provider.dart';
import 'package:pleya/providers/shader_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/apple_tv_remote_touch_service.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/video_controls/tv_info_panel.dart';
import 'package:pleya/widgets/video_controls/player_chrome_controller.dart';
import 'package:pleya/widgets/video_controls/video_controls.dart';
import 'package:pleya/widgets/video_controls/widgets/player_toast_indicator.dart';
import 'package:drift/native.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';
import '../../test_helpers/watch_together_fakes.dart';

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

/// Calls every arrow-down a swipe, the gesture that opens the info panel.
class _SwipeDownTouch extends AppleTvRemoteTouchService {
  @override
  bool isSwipeDirectional(LogicalKeyboardKey key) => key == LogicalKeyboardKey.arrowDown;
}

class _ControlsPlayer extends FakeSyncPlayer {
  _ControlsPlayer({super.playing, super.position, super.duration});

  @override
  String get playerType => 'mpv';
}

void main() {
  group('PLR-REMOTE-UX1: native pauze opent de balk op Afspelen', () {
    setUp(() async {
      LocaleSettings.setLocaleSync(AppLocale.en);
      await initializeDateFormatting('en');
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      await SettingsService.getInstance();
      TvDetectionService.debugSetAppleTVOverride(true);
    });

    tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

    Future<PlayerChromeController> pumpPlayer(WidgetTester tester, {bool visible = false}) async {
      final player = _ControlsPlayer(
        playing: false,
        position: const Duration(minutes: 3),
        duration: const Duration(minutes: 90),
      );
      addTearDown(player.dispose);
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final chrome = PlayerChromeController(controlsVisible: visible);
      addTearDown(chrome.dispose);
      final toast = PlayerToastController();
      addTearDown(toast.dispose);
      final watchTogether = WatchTogetherProvider();
      addTearDown(watchTogether.dispose);
      final manager = MultiServerManager();
      addTearDown(manager.dispose);
      final servers = MultiServerProvider(manager, DataAggregationService(manager));
      addTearDown(servers.dispose);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<WatchTogetherProvider>.value(value: watchTogether),
            ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
            ChangeNotifierProvider<PlaybackStateProvider>(create: (_) => PlaybackStateProvider()),
            ChangeNotifierProvider<ShaderProvider>(create: (_) => ShaderProvider()),
            Provider<AppDatabase>.value(value: db),
          ],
          child: MaterialApp(
            theme: ThemeData(extensions: const [_testTokens]),
            home: OverlaySheetHost(
              child: Material(
                type: MaterialType.transparency,
                child: PlexVideoControls(
                  player: player,
                  metadata: MediaItem(id: '1', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Film'),
                  toastController: toast,
                  chromeController: chrome,
                  onNext: null,
                  onPrevious: null,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      return chrome;
    }

    testWidgets('verborgen balk komt terug met focus op Afspelen', (tester) async {
      final chrome = await pumpPlayer(tester);
      expect(chrome.controlsVisible, isFalse);

      chrome.requestExplicitPauseChrome();
      await tester.pump(const Duration(milliseconds: 400));

      expect(chrome.controlsVisible, isTrue);
      expect(FocusManager.instance.primaryFocus?.debugLabel, contains('PlayPause'));
    });

    testWidgets('een open sheet houdt de balk verborgen', (tester) async {
      final chrome = await pumpPlayer(tester);
      final sheets = OverlaySheetController.of(tester.element(find.byType(PlexVideoControls)));
      unawaited(sheets.show<void>(builder: (_) => const SizedBox(width: 200, height: 100, child: Text('sheet'))));
      await tester.pump(const Duration(milliseconds: 400));
      expect(sheets.isOpen, isTrue);

      chrome.requestExplicitPauseChrome();
      await tester.pump(const Duration(milliseconds: 400));

      expect(chrome.controlsVisible, isFalse);
    });
    testWidgets('een open infopaneel houdt de balk verborgen', (tester) async {
      AppleTvRemoteTouchService.debugInstanceOverride = _SwipeDownTouch();
      addTearDown(() => AppleTvRemoteTouchService.debugInstanceOverride = null);
      final chrome = await pumpPlayer(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(TvInfoPanel), findsOneWidget);

      chrome.requestExplicitPauseChrome();
      await tester.pump(const Duration(milliseconds: 400));

      expect(chrome.controlsVisible, isFalse);
    });
  });
}
