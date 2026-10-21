import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/apple_tv_remote_touch_service.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/video_controls/tv_info_panel.dart';
import 'package:pleya/widgets/video_controls/video_controls.dart';

import 'tv_player_harness.dart';

void main() {
  group('PLR-REMOTE-UX1: native pauze opent de balk op Afspelen', () {
    setUpTvPlayerEnvironment();

    testWidgets('verborgen balk komt terug met focus op Afspelen', (tester) async {
      final chrome = (await pumpTvPlayer(tester)).chrome;
      expect(chrome.controlsVisible, isFalse);

      chrome.requestExplicitPauseChrome();
      await tester.pump(const Duration(milliseconds: 400));

      expect(chrome.controlsVisible, isTrue);
      expect(FocusManager.instance.primaryFocus?.debugLabel, contains('PlayPause'));
    });

    testWidgets('een open sheet houdt de balk verborgen', (tester) async {
      final chrome = (await pumpTvPlayer(tester)).chrome;
      final sheets = OverlaySheetController.of(tester.element(find.byType(PlexVideoControls)));
      unawaited(sheets.show<void>(builder: (_) => const SizedBox(width: 200, height: 100, child: Text('sheet'))));
      await tester.pump(const Duration(milliseconds: 400));
      expect(sheets.isOpen, isTrue);

      chrome.requestExplicitPauseChrome();
      await tester.pump(const Duration(milliseconds: 400));

      expect(chrome.controlsVisible, isFalse);
    });
    testWidgets('een open infopaneel houdt de balk verborgen', (tester) async {
      AppleTvRemoteTouchService.debugInstanceOverride = SwipeDownTouch();
      addTearDown(() => AppleTvRemoteTouchService.debugInstanceOverride = null);
      final chrome = (await pumpTvPlayer(tester)).chrome;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(TvInfoPanel), findsOneWidget);

      chrome.requestExplicitPauseChrome();
      await tester.pump(const Duration(milliseconds: 400));

      expect(chrome.controlsVisible, isFalse);
    });
  });
}
