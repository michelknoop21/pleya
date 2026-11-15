import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/widgets/video_controls/film_frame_palette.dart';
import 'package:pleya/widgets/app_icon.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/watch_together/providers/watch_together_provider.dart';
import 'package:pleya/widgets/video_controls/desktop_video_controls.dart';
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

void main() {
  group('PLR-REMOTE-UX1: de focusrij slaat knoppen zonder actie over', () {
    setUp(() async {
      LocaleSettings.setLocaleSync(AppLocale.en);
      await initializeDateFormatting('en');
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      await SettingsService.getInstance();
      TvDetectionService.debugSetAppleTVOverride(true);
    });

    tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

    final key = GlobalKey<State<DesktopVideoControls>>();

    /// A film: no chapters, no previous or next item, so four buttons are dead.
    Future<void> pumpFilm(WidgetTester tester) async {
      final player = FakeSyncPlayer(
        playing: true,
        position: const Duration(minutes: 3),
        duration: const Duration(minutes: 90),
      );
      addTearDown(player.dispose);
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final watchTogether = WatchTogetherProvider();
      addTearDown(watchTogether.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<WatchTogetherProvider>.value(
          value: watchTogether,
          child: MaterialApp(
            theme: ThemeData(extensions: const [_testTokens]),
            builder: (context, child) => InputModeTracker(child: child!),
            home: Material(
              type: MaterialType.transparency,
              child: DesktopVideoControls(
                key: key,
                player: player,
                metadata: MediaItem(id: '1', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Film'),
                chapters: const [],
                chaptersLoaded: true,
                seekTimeSmall: 10,
                // ignore: no-empty-block - not exercised by these tests
                onSeekBackward: () {},
                // ignore: no-empty-block - not exercised by these tests
                onSeekForward: () {},
                // ignore: no-empty-block - not exercised by these tests
                onSeekToPreviousChapter: () {},
                // ignore: no-empty-block - not exercised by these tests
                onSeekToNextChapter: () {},
                // ignore: no-empty-block - not exercised by these tests
                onSeek: (_) {},
                // ignore: no-empty-block - not exercised by these tests
                onSeekEnd: (_) {},
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

    testWidgets('dode knoppen nemen geen focus aan', (tester) async {
      await pumpFilm(tester);
      (key.currentState! as dynamic).requestPlayPauseFocus();
      await tester.pump();
      final play = FocusManager.instance.primaryFocus!;

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      final afterLeft = FocusManager.instance.primaryFocus!;
      expect(afterLeft, isNot(play));
      expect(afterLeft.canRequestFocus, isTrue);

      // Left of skip-back there is nothing that works: focus stays put.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, afterLeft);
    });

    testWidgets('rechts van de laatste werkende knop landt op de trackcontrols, niet op een dode knop', (tester) async {
      await pumpFilm(tester);
      (key.currentState! as dynamic).requestPlayPauseFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // skip forward
      await tester.pump();
      final skipForward = FocusManager.instance.primaryFocus!;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      final next = FocusManager.instance.primaryFocus!;
      expect(next.canRequestFocus, isTrue);
      expect(next, isNot(skipForward));
    });

    testWidgets('terug vanaf de trackcontrols landt op de laatste werkende knop', (tester) async {
      await pumpFilm(tester);
      (key.currentState! as dynamic).requestPlayPauseFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      final skipForward = FocusManager.instance.primaryFocus!;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      (key.currentState! as dynamic).navigateFromTrackToVolume();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, skipForward);
    });

    testWidgets('een externe node wordt weer focusbaar als zijn uitgeschakelde wrapper verdwijnt', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      Widget host({required bool mounted, required bool enabled}) => MaterialApp(
        home: mounted
            ? FocusableWrapper(focusNode: node, canRequestFocus: enabled, child: const SizedBox(width: 10, height: 10))
            : const SizedBox(),
      );

      await tester.pumpWidget(host(mounted: true, enabled: false));
      expect(node.canRequestFocus, isFalse);
      await tester.pumpWidget(host(mounted: false, enabled: false));
      await tester.pumpWidget(host(mounted: true, enabled: true));
      expect(node.canRequestFocus, isTrue);
    });

    // DENS1 review I2: the focus language itself, not only the absence of a
    // ring. The focused button is the solid Filmbeeld tile with a dark glyph;
    // play keeps its quiet tile while focus is elsewhere.
    testWidgets('de gefocuste knop is de massieve tegel, afspelen blijft stil (DENS1 T4)', (tester) async {
      await pumpFilm(tester);
      (key.currentState! as dynamic).requestPlayPauseFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      final focused = FocusManager.instance.primaryFocus!;

      final tiles = find.byWidgetPredicate(
        (w) => w is IconButton && w.style?.shape?.resolve(const {}) is RoundedRectangleBorder,
      );
      IconButton tileOf(FocusNode node) => tester.widget<IconButton>(
        find.descendant(
          of: find.byWidgetPredicate((w) => w is FocusableWrapper && w.focusNode == node),
          matching: tiles,
        ),
      );
      Color? fill(IconButton b) => b.style!.backgroundColor?.resolve(const {});
      Color? glyph(IconButton b) => (b.icon as AppIcon).color;

      final next = tileOf(focused);
      expect(fill(next), kFilmPrimary);
      expect(glyph(next), kFilmInk);

      final play = find.byWidgetPredicate(
        (w) => w is IconButton && (w.icon is AppIcon) && (w.icon as AppIcon).icon == Symbols.pause_rounded,
      );
      final playButton = tester.widget<IconButton>(play);
      expect(fill(playButton), Colors.white.withValues(alpha: 0.2));
      expect(glyph(playButton), Colors.white);
    });

    testWidgets('de transportrij heeft één focustaal: geen ring om afspelen, gelijke steek (DENS1 T4)', (tester) async {
      await pumpFilm(tester);
      // Every transport button is the same rounded tile and draws its own
      // focus (the solid Filmbeeld tile); none goes through a ring that adds
      // its width around play alone. Before, only play had the tile shape.
      final tiles = find.byWidgetPredicate(
        (w) => w is IconButton && w.style?.shape?.resolve(const {}) is RoundedRectangleBorder,
      );
      expect(tiles.evaluate().length, greaterThanOrEqualTo(5));
      final wrappers = tester.widgetList<FocusableWrapper>(
        find.ancestor(of: tiles, matching: find.byType(FocusableWrapper)),
      );
      expect(wrappers.where((w) => w.mode == FocusIndicatorMode.ring), isEmpty);
    });
  });
}
