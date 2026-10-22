import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/screens/media_detail/mobile/detail_primary_actions.dart';
import 'package:pleya/screens/media_detail/mobile/light_ink_plate.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/glass/glass_surface.dart';
import 'package:pleya/theme/mono_theme.dart';

import '../../test_helpers/glass_phone.dart';
import '../../test_helpers/prefs.dart';

Widget _harness({required bool dark, required Color poster, required GlobalKey shot}) {
  return MaterialApp(
    theme: monoTheme(dark: dark).copyWith(platform: TargetPlatform.iOS),
    home: Scaffold(
      body: RepaintBoundary(
        key: shot,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [poster, const Color(0xFFE8A07A), poster, const Color(0xFF3A5F8A), poster],
              stops: const [0, 0.1, 0.2, 0.5, 1],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: DetailPrimaryActions(
              glass: true,
              playLabel: 'Hervatten',
              playDetail: '· S1E8 · 12 min over',
              onPlay: () {},
              onPlayFromStart: () {},
              actions: [
                for (final id in ['Kijklijst', 'Trailer', 'Beoordeel', 'Bekeken', 'Meer'])
                  DetailActionItem(
                    key: Key('media-detail.action.$id'),
                    icon: Icons.star_border,
                    label: id,
                    onTap: () {},
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _snap(WidgetTester tester, GlobalKey key, String name) async {
  final dir = Platform.environment['GLASS_SHOT_DIR'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUp(resetSharedPreferencesForTest);

  testWidgets('light theme: play capsule and restart circle are translucent glass, not an opaque plate', (
    tester,
  ) async {
    await glassPhone(tester, glass: true);
    final shot = GlobalKey();
    await tester.pumpWidget(_harness(dark: false, poster: const Color(0xFF1B1B2F), shot: shot));
    await tester.pump();

    final play = tester.widget<GlassSurface>(
      find.descendant(of: find.byKey(const Key('media-detail.play')), matching: find.byType(GlassSurface)),
    );
    expect(play.tokens, isNotNull, reason: 'the light capsule must not use the near-white prominent plate');
    expect(play.tokens!.tint.a, lessThanOrEqualTo(0.35));
    expect(kLightInkPlateAlpha, lessThanOrEqualTo(0.35));
    final restart = tester.widget<Material>(find.byKey(const Key('media-detail.play-from-start')));
    expect(restart.color!.a, lessThanOrEqualTo(0.35));
    expect(
      find.descendant(of: find.byKey(const Key('media-detail.play-from-start')), matching: find.byType(InkWell)),
      findsOneWidget,
    );
    await _snap(tester, shot, 'light-dark-poster');

    await tester.pumpWidget(_harness(dark: false, poster: const Color(0xFFF4F0E8), shot: shot));
    await tester.pump();
    await _snap(tester, shot, 'light-light-poster');
  });

  testWidgets('dark theme keeps the prominent white capsule', (tester) async {
    await glassPhone(tester, glass: true);
    final shot = GlobalKey();
    await tester.pumpWidget(_harness(dark: true, poster: const Color(0xFF1B1B2F), shot: shot));
    await tester.pump();
    final play = tester.widget<GlassSurface>(
      find.descendant(of: find.byKey(const Key('media-detail.play')), matching: find.byType(GlassSurface)),
    );
    expect(play.tokens, isNull);
    expect(play.prominent, isTrue);
    await _snap(tester, shot, 'dark');
    expect(SettingsService.instance, isNotNull);
  });
}
