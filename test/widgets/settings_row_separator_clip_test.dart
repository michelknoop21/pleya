/// VIS-0925 review FIX 2: in Light the dark separator beside the white focus
/// ring was cut off by the settings card's clip on the first and last row, and
/// a white ring on a light card is invisible without it. The separator now
/// sits inside the box for an inside ring, so the card clip cannot remove it.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/setting_tile.dart';
import 'package:pleya/widgets/settings_section.dart';

import '../test_helpers/prefs.dart';

const _boundary = ValueKey('boundary');

void main() {
  late List<FocusNode> nodes;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
    await SettingsService.getInstance();
    nodes = [FocusNode(), FocusNode()];
  });

  tearDown(() {
    for (final n in nodes) {
      n.dispose();
    }
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  Future<Color> pixel(WidgetTester tester, Offset global) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundary));
    final local = global - boundary.localToGlobal(Offset.zero);
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage();
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final i = (local.dy.floor() * image.width + local.dx.floor()) * 4;
        final l = data!.buffer.asUint8List();
        return [l[i], l[i + 1], l[i + 2], l[i + 3]];
      } finally {
        image.dispose();
      }
    });
    return Color.fromARGB(bytes![3], bytes[0], bytes[1], bytes[2]);
  }

  for (final (label, index, edgeOf) in [
    ('first row, top edge', 0, (Rect r) => Offset(r.center.dx, r.top + 0.5)),
    ('last row, bottom edge', 1, (Rect r) => Offset(r.center.dx, r.bottom - 0.5)),
  ]) {
    testWidgets('Light: the separator survives the card clip on the $label', (tester) async {
      tester.view.physicalSize = const Size(1038, 584);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        InputModeTracker(
          child: MaterialApp(
            theme: monoTheme(dark: false),
            home: Scaffold(
              body: RepaintBoundary(
                key: _boundary,
                child: Builder(
                  builder: (context) => ColoredBox(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: SettingsGroup(
                        children: [
                          for (var i = 0; i < 2; i++)
                            SettingNavigationTile(
                              icon: Symbols.settings_rounded,
                              title: 'Row $i',
                              focusNode: nodes[i],
                              onTap: () {},
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      nodes[index].requestFocus();
      await tester.pumpAndSettle();

      final row = tester.getRect(find.byType(ListTile).at(index));
      final edge = await pixel(tester, edgeOf(row));
      expect(edge.computeLuminance(), lessThan(0.5), reason: 'separator pixel $edge at the card edge');
    });
  }
}
