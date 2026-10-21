import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_source_info.dart';
import 'package:pleya/services/apple_tv_remote_touch_service.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/video_controls/player_chrome_controller.dart';
import 'package:pleya/widgets/video_controls/tv_info_panel.dart';
import 'package:pleya/widgets/video_controls/video_controls.dart';
import 'package:pleya/widgets/video_controls/widgets/skip_marker_button.dart';

import 'tv_player_harness.dart';

final _intro = PlaybackExtras(
  chapters: const [],
  markers: [MediaMarker(id: 1, type: 'intro', startTimeOffset: 0, endTimeOffset: 90000)],
);

const _skipLabel = 'SkipMarkerButton';

String? _focusLabel() => FocusManager.instance.primaryFocus?.debugLabel;

void _offerMarker(WidgetTester tester) {
  (tester.state(find.byType(PlexVideoControls)) as dynamic).debugApplyPlaybackExtras(_intro);
}

void main() {
  group('PLR-REMOTE-UX1: skipfocus alleen vanuit de neutrale video', () {
    setUpTvPlayerEnvironment();

    Future<TvPlayerRig> pump(WidgetTester tester, {bool visible = false, bool playing = true}) => pumpTvPlayer(
      tester,
      kind: MediaKind.episode,
      position: const Duration(seconds: 30),
      visible: visible,
      playing: playing,
    );

    testWidgets('een marker bij verborgen balk krijgt focus', (tester) async {
      await pump(tester);
      _offerMarker(tester);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SkipMarkerButton), findsOneWidget);
      expect(_focusLabel(), _skipLabel);
    });

    testWidgets('een marker neemt de focus niet van het infopaneel', (tester) async {
      AppleTvRemoteTouchService.debugInstanceOverride = SwipeDownTouch();
      addTearDown(() => AppleTvRemoteTouchService.debugInstanceOverride = null);
      await pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(TvInfoPanel), findsOneWidget);
      final before = FocusManager.instance.primaryFocus;

      _offerMarker(tester);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(TvInfoPanel), findsOneWidget);
      expect(_focusLabel(), isNot(_skipLabel));
      expect(FocusManager.instance.primaryFocus, before);
    });

    testWidgets('een marker neemt de focus niet van zichtbare controls', (tester) async {
      final rig = await pump(tester, visible: true, playing: false);
      rig.chrome.show(focusTarget: PlayerChromeFocusTarget.playPause);
      await tester.pump(const Duration(milliseconds: 400));
      final before = FocusManager.instance.primaryFocus;
      expect(_focusLabel(), isNot(_skipLabel));

      _offerMarker(tester);
      await tester.pump(const Duration(milliseconds: 400));

      expect(FocusManager.instance.primaryFocus, before);
    });

    testWidgets('een marker neemt de focus niet van een open sheet', (tester) async {
      await pump(tester);
      final sheets = OverlaySheetController.of(tester.element(find.byType(PlexVideoControls)));
      unawaited(sheets.show<void>(builder: (_) => const SizedBox(width: 200, height: 100, child: Text('sheet'))));
      await tester.pump(const Duration(milliseconds: 400));
      final before = FocusManager.instance.primaryFocus;

      _offerMarker(tester);
      await tester.pump(const Duration(milliseconds: 400));

      expect(sheets.isOpen, isTrue);
      expect(FocusManager.instance.primaryFocus, before);
      expect(_focusLabel(), isNot(_skipLabel));
    });

    testWidgets('na zeven seconden verdwijnt een gefocuste skipknop niet zolang de marker geldt', (tester) async {
      await pump(tester);
      _offerMarker(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(_focusLabel(), _skipLabel);

      await tester.pump(const Duration(seconds: 15));

      expect(find.byType(SkipMarkerButton), findsOneWidget);
      expect(_focusLabel(), _skipLabel);
    });

    testWidgets('zonder focus verdwijnt de skipknop na zeven seconden nog steeds', (tester) async {
      await pump(tester);
      _offerMarker(tester);
      await tester.pump(const Duration(milliseconds: 400));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(_focusLabel(), isNot(_skipLabel));

      await tester.pump(const Duration(seconds: 8));

      expect(find.byType(SkipMarkerButton), findsNothing);
    });

    testWidgets('een marker die onder focus afloopt laat een geldige focus achter', (tester) async {
      final rig = await pump(tester);
      _offerMarker(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(_focusLabel(), _skipLabel);

      rig.player.setPosition(const Duration(minutes: 5));
      _offerMarker(tester);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SkipMarkerButton), findsNothing);
      expect(_focusLabel(), 'PlayerControlsRoot');
    });

    testWidgets('de spelerbediening meldt het open infopaneel aan de screen, voor de Play Next-focus', (tester) async {
      AppleTvRemoteTouchService.debugInstanceOverride = SwipeDownTouch();
      addTearDown(() => AppleTvRemoteTouchService.debugInstanceOverride = null);
      final rig = await pump(tester);
      expect(rig.chrome.tvInfoPanelOpen, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 400));
      expect(rig.chrome.tvInfoPanelOpen, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.byType(TvInfoPanel), findsNothing);
      expect(rig.chrome.tvInfoPanelOpen, isFalse);
    });
  });
}
