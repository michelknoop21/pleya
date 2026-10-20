import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/services/airplay_service.dart';
import 'package:pleya/widgets/pleya_fly_icon.dart';
import 'package:pleya/widgets/video_controls/models/track_controls_state.dart';
import 'package:pleya/widgets/video_controls/video_control_button.dart';
import 'package:pleya/widgets/video_controls/widgets/track_chapter_controls.dart';

import '../../test_helpers/watch_together_fakes.dart';

const _shots = String.fromEnvironment('PLEYA_FLY_SHOTS');
const _symbolsFont = String.fromEnvironment('PLEYA_FLY_SYMBOLS_FONT');

/// Screenshots only: load the real Material Symbols so neighbours are not tofu.
Future<void> _loadSymbols() async {
  if (_symbolsFont.isEmpty) return;
  final loader = FontLoader('packages/material_symbols_icons/MaterialSymbolsRounded')
    ..addFont(Future.value(ByteData.sublistView(File(_symbolsFont).readAsBytesSync())));
  await loader.load();
}

ColorFilter? _fly(WidgetTester tester) => tester.widget<SvgPicture>(find.byType(SvgPicture)).colorFilter;

void main() {
  setUpAll(_loadSymbols);
  setUp(() => AirPlayService.debugAvailableOverride = true);
  tearDown(() => AirPlayService.debugAvailableOverride = null);

  Widget bar(ThemeData theme, GlobalKey key, FakeSyncPlayer player) => MaterialApp(
    theme: theme,
    home: Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: Colors.black,
            child: TrackChapterControls(
              player: player,
              chapters: const [],
              chaptersLoaded: true,
              trackControlsState: const TrackControlsState(canHandoff: true, serverId: 'srv', ratingKey: '1'),
            ),
          ),
        ),
      ),
    ),
  );

  for (final (name, theme) in [('dark', ThemeData.dark()), ('light', ThemeData.light())]) {
    testWidgets('the player bar shows the Pleya Fly button ($name)', (tester) async {
      final player = FakeSyncPlayer(playing: true, duration: const Duration(minutes: 90));
      addTearDown(player.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(bar(theme, key, player));
      await tester.pumpAndSettle();

      final button = find.byTooltip('${t.playbackHandoff.button} · ${t.playbackHandoff.description}');
      expect(button, findsOneWidget);
      expect(find.descendant(of: button, matching: find.byType(PleyaFlyIcon)), findsOneWidget);
      expect(find.bySemanticsLabel('Pleya Fly'), findsOneWidget);
      expect(tester.getSize(find.descendant(of: button, matching: find.byType(PleyaFlyIcon))), const Size(24, 24));

      if (_shots.isNotEmpty) {
        await tester.runAsync(() async {
          final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 6);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$_shots/player-bar-$name.png').writeAsBytesSync(data!.buffer.asUint8List());
        });
      }
    });
  }

  // Light theme: its IconTheme colour is dark, so only the button's own colour can make the glyph white.
  for (final (name, button, expected) in [
    (
      'white by default',
      const VideoControlButton(icon: Icons.add, iconWidget: PleyaFlyIcon(), onPressed: null),
      Colors.white,
    ),
    (
      'amber when active',
      const VideoControlButton(icon: Icons.add, iconWidget: PleyaFlyIcon(), isActive: true, onPressed: null),
      Colors.amber,
    ),
    (
      'the explicit colour',
      const VideoControlButton(icon: Icons.add, iconWidget: PleyaFlyIcon(), color: Colors.red, onPressed: null),
      Colors.red,
    ),
  ]) {
    testWidgets('the Pleya Fly glyph follows the button colour: $name', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(body: Center(child: button)),
        ),
      );
      expect(_fly(tester), ColorFilter.mode(expected, BlendMode.srcIn));
    });
  }
}
