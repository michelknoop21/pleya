import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pleya/mpv/mpv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
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
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/video_controls/player_chrome_controller.dart';
import 'package:pleya/widgets/video_controls/video_controls.dart';
import 'package:pleya/widgets/video_controls/widgets/player_toast_indicator.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';
import '../../test_helpers/watch_together_fakes.dart';

const tvPlayerTestTokens = MonoTokens(
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
class SwipeDownTouch extends AppleTvRemoteTouchService {
  @override
  bool isSwipeDirectional(LogicalKeyboardKey key) => key == LogicalKeyboardKey.arrowDown;
}

class ControlsPlayer extends FakeSyncPlayer {
  ControlsPlayer({super.playing, super.position, super.duration, this.subtitle});
  final SubtitleTrack? subtitle;
  @override
  PlayerState get state => super.state.copyWith(track: TrackSelection(subtitle: subtitle));
  @override
  Future<void> setProperty(String name, String value) async {
    commandLog.add('$name=$value');
  }

  @override
  String get playerType => 'mpv';
}

/// Registers the setUp/tearDown a TV player test needs: English strings, clean
/// prefs, and Apple TV detection.
void setUpTvPlayerEnvironment() {
  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    await initializeDateFormatting('en');
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    TvDetectionService.debugSetAppleTVOverride(true);
  });
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
}

class TvPlayerRig {
  TvPlayerRig(this.chrome, this.player);
  final PlayerChromeController chrome;
  final ControlsPlayer player;
}

/// Pumps [PlexVideoControls] on a 1920x1080 Apple TV canvas inside an overlay
/// sheet host, with every provider the controls read.
Future<TvPlayerRig> pumpTvPlayer(
  WidgetTester tester, {
  bool visible = false,
  bool playing = false,
  MediaKind kind = MediaKind.movie,
  Duration position = const Duration(minutes: 3),
  ValueChanged<bool>? onSheetOpenChanged,
  FocusNode? playNextFocusNode,
  ValueNotifier<bool>? subtitleVisibility,
  SubtitleTrack? subtitle,
}) async {
  final player = ControlsPlayer(
    playing: playing,
    position: position,
    duration: const Duration(minutes: 90),
    subtitle: subtitle,
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
        theme: ThemeData(extensions: const [tvPlayerTestTokens]),
        home: InputModeTracker(
          child: OverlaySheetHost(
            onOpenChanged: onSheetOpenChanged,
            child: Material(
              type: MaterialType.transparency,
              child: Stack(
                children: [
                  // Stands in for the Play Next card, which owns [playNextFocusNode].
                  if (playNextFocusNode != null)
                    Focus(focusNode: playNextFocusNode, child: const SizedBox(width: 10, height: 10)),
                  PlexVideoControls(
                    player: player,
                    subtitleVisibility: subtitleVisibility,
                    metadata: MediaItem(id: '1', backend: MediaBackend.plex, kind: kind, title: 'Titel'),
                    toastController: toast,
                    chromeController: chrome,
                    onNext: null,
                    onPrevious: null,
                    playNextFocusNode: playNextFocusNode,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
  return TvPlayerRig(chrome, player);
}
