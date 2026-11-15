/// Optional supplemental widget rasters, explicitly not native screenshots.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

Future<void> captureFollowup(WidgetTester tester, Finder finder, String name) async {
  final directory = Platform.environment['PLEYA_FOLLOWUP_EVIDENCE'];
  if (directory == null) return;
  final dpr = tester.view.devicePixelRatio;
  final logical = tester.view.physicalSize / dpr;
  await tester.runAsync(() async {
    final image = await captureImage(tester.element(finder));
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$directory/$name.png').writeAsBytes(data!.buffer.asUint8List());
      await File('$directory/$name.json').writeAsString(
        jsonEncode({
          'kind': 'supplemental widget raster',
          'logicalWidth': logical.width,
          'logicalHeight': logical.height,
          'devicePixelRatio': dpr,
          'rasterWidth': image.width,
          'rasterHeight': image.height,
        }),
      );
    } finally {
      image.dispose();
    }
  });
}
