import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/models/transcode_quality_preset.dart';
import 'package:pleya/widgets/video_controls/sheets/version_quality_sheet.dart';

void main() {
  testWidgets('quality picker starts on the active choice and accepts keyboard selection', (tester) async {
    final choices = <TranscodeQualityPreset>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VersionQualityPicker(
            availableVersions: const [],
            selectedMediaIndex: 0,
            selectedQualityPreset: TranscodeQualityPreset.original,
            serverSupportsTranscoding: true,
            onVersionSelected: (_) {},
            onQualitySelected: choices.add,
            onDismiss: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(choices, [TranscodeQualityPreset.original]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(choices.last, TranscodeQualityPreset.p1080_20mbps);
  });
}
