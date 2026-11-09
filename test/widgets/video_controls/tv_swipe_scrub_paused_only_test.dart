import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/apple_tv_remote_touch_service.dart';
import 'package:pleya/widgets/video_controls/tv_info_panel.dart';

import 'tv_player_harness.dart';

/// Calls every left/right arrow a touch-surface swipe.
class SwipeHorizontalTouch extends AppleTvRemoteTouchService {
  @override
  bool isSwipeDirectional(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight;
}

void main() {
  group('Swipe-scrub alleen tijdens pauze (A-12)', () {
    setUpTvPlayerEnvironment();
    tearDown(() => AppleTvRemoteTouchService.debugInstanceOverride = null);

    List<String> seeks(TvPlayerRig rig) => rig.player.commandLog.where((c) => c.startsWith('seek')).toList();

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump(const Duration(seconds: 1));
    }

    // Two presses cover both paths: the first meets hidden controls
    // (key_events.dart), the second the focused timeline (desktop_video_controls).
    testWidgets('swipe tijdens afspelen verzet niets en toont de controls', (tester) async {
      AppleTvRemoteTouchService.debugInstanceOverride = SwipeHorizontalTouch();
      final rig = await pumpTvPlayer(tester, playing: true);

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(rig.chrome.controlsVisible, isTrue);
      await press(tester, LogicalKeyboardKey.arrowRight);

      expect(seeks(rig), isEmpty);
      expect(rig.player.commandLog, isNot(contains('pause')));
      expect(rig.player.state.playing, isTrue);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('ringklik tijdens afspelen blijft zoeken per druk', (tester) async {
      AppleTvRemoteTouchService.debugInstanceOverride = AppleTvRemoteTouchService();
      final rig = await pumpTvPlayer(tester, playing: true);

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(seeks(rig), hasLength(1));
      await press(tester, LogicalKeyboardKey.arrowRight);

      expect(seeks(rig).length, greaterThanOrEqualTo(2));
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('swipe tijdens pauze scrubt nog steeds', (tester) async {
      AppleTvRemoteTouchService.debugInstanceOverride = SwipeHorizontalTouch();
      final rig = await pumpTvPlayer(tester, playing: false);

      await press(tester, LogicalKeyboardKey.arrowRight);
      final before = seeks(rig).length; // hidden controls seek directly
      await press(tester, LogicalKeyboardKey.arrowRight); // enters scrub mode
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.select); // confirm

      expect(seeks(rig).length, greaterThan(before));
      expect(rig.player.commandLog, contains('play')); // confirming plays
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('swipe omlaag tijdens afspelen opent nog het infopaneel', (tester) async {
      AppleTvRemoteTouchService.debugInstanceOverride = SwipeDownTouch();
      await pumpTvPlayer(tester, playing: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(TvInfoPanel), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });
  });
}
