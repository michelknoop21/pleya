import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_node.dart';
import 'package:pleya/theme/mono_theme.dart';

import '../test_helpers/contrast.dart';
import '../test_helpers/glass_phone.dart';
import '../test_helpers/golden.dart';
import '../test_helpers/prefs.dart';

void main() {
  late ui.Image scene;
  setUpAll(() async {
    await loadAppFontsForGoldens();
    final codec = await ui.instantiateImageCodec(File('test/fixtures/glass/bbb_light_scene.jpg').readAsBytesSync());
    scene = (await codec.getNextFrame()).image;
    codec.dispose();
  });
  tearDownAll(() => scene.dispose());
  setUp(resetSharedPreferencesForTest);

  testWidgets('red selected icon keeps contrast while the lens is held over another tab', (tester) async {
    await glassPhone(tester, glass: true);
    const key = ValueKey('contrast-scene');
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: glassMainShell(
          (_) => Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Colors.black)),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 180,
                child: RawImage(image: scene, fit: BoxFit.cover),
              ),
            ],
          ),
          transparentForeground: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final lens = find.byKey(const ValueKey('mobile-tab-glass-lens'));
    final start = tester.getCenter(lens);
    final bar = tester.getRect(find.byType(NavigationBar));
    final target = Offset(bar.right - bar.width / 8, bar.center.dy);
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(Offset((start.dx + target.dx) / 2, target.dy));
    await tester.pump();
    await gesture.moveTo(target);
    await tester.pump();
    expect((tester.getCenter(lens).dx - target.dx).abs(), lessThan(1));
    final selectedIcon = find.byWidgetPredicate((w) => w is AutomationNode && w.id == 'nav.discover').first;
    final ratio = await textContrastOverBackground(
      tester,
      area: selectedIcon,
      textColor: kAccent,
      boundary: find.byKey(key),
    );
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(ratio, greaterThanOrEqualTo(3), reason: 'The red committed icon needs backing even while its lens moves.');
  });
}
