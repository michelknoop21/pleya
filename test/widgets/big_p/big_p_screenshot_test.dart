// Visual evidence: renders Big P in every mood to PNG. Skipped unless
// BIGP_SHOT_DIR is set, e.g.
//   BIGP_SHOT_DIR=/tmp/bigp flutter test test/widgets/big_p/big_p_screenshot_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/widgets/big_p/big_p_avatar.dart';
import 'package:pleya/widgets/big_p/big_p_rig.dart';

final _dir = Platform.environment['BIGP_SHOT_DIR'];

void main() {
  final shots = <String, (Widget, int)>{
    'idle': (const BigPAvatar(mood: BigPMood.idle, entrance: false), 400),
    'listening': (const BigPAvatar(mood: BigPMood.listening, entrance: false), 400),
    'working': (const BigPAvatar(mood: BigPMood.working, entrance: false, pointAt: Alignment(1, 0.6)), 400),
    'success-cheer': (const BigPAvatar(mood: BigPMood.success), 350),
    'success-talk': (
      const BigPAvatar(mood: BigPMood.success, entrance: false, talkingText: 'Twee taken lopen weer.'),
      1700,
    ),
    'error': (const BigPAvatar(mood: BigPMood.error, entrance: false), 600),
    'attentive': (const BigPAvatar(mood: BigPMood.attentive, entrance: false), 400),
    'portrait': (const BigPPortrait(focused: false, size: 260), 0),
  };
  for (final MapEntry(key: name, value: (widget, ms)) in shots.entries) {
    testWidgets('shot $name', skip: _dir == null, (tester) async {
      tester.view.physicalSize = const Size(600, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      final assets = [
        for (final p in kBigPPoses) bigPPoseAsset(p),
        for (final m in kBigPMouths) bigPAsset('mouth-$m'),
        bigPAsset('brow-l'),
        bigPAsset('brow-r'),
        bigPAsset('aim-arm'),
        bigPAsset('wave-arm'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: boundary,
            child: ColoredBox(
              color: const Color(0xFF14080A),
              child: Center(child: widget),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        final ctx = tester.element(find.byKey(boundary));
        for (final a in assets) {
          await precacheImage(AssetImage(a), ctx);
        }
      });
      for (var t = 0; t < ms; t += 16) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump();
      await tester.runAsync(() async {
        final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await ro.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$_dir/bigp-$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox());
    });
  }
}
