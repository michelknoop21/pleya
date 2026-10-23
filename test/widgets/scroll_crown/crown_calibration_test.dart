import 'baseline_motion.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pleya/widgets/scroll_crown/scroll_crown.dart';
import 'package:pleya/widgets/scroll_crown/crown_drag_motion.dart';

import '../../../tool/crown_calibration.dart';
import '../../../tool/crown_calibration_model.dart';

Map<String, Object> point(String event, int ms, double row) => {
  'event': event,
  't_us': ms * 1000,
  'pixels': row * crownRowExtent,
};

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.directory);
  final String directory;
  @override
  Future<String?> getApplicationDocumentsPath() async => directory;
}

void main() {
  test('protocol fixes all targets, repetitions and alphabet spread', () {
    for (final count in crownLibrarySizes) {
      final tasks = crownTasks(count);
      expect(tasks.length, 7);
      expect(tasks.map((t) => t.id).toSet().length, tasks.length);
      expect(tasks.every((t) => t.start >= 0 && t.start < count && t.target >= 0 && t.target < count), isTrue);
      expect(crownTitle(0, count), 'A · 00001');
      expect(crownTitle(count - 1, count), 'Z · ${count.toString().padLeft(5, '0')}');
      expect(tasks[0].target - tasks[0].start, 1);
      expect(tasks[1].target - tasks[1].start, -1);
    }
    expect(crownLibrarySizes.length * crownTasks(100).length * crownRepeats, 105);
  });

  test('brief endpoint task must actually visit the far end before returning', () {
    expect(crownQuickTasks(10000).map((task) => task.id), ['ends-release', 'one-back']);
    final attempt = CrownAttempt(count: 100, task: const CrownTask('ends-release', 0, 0, ''), repeat: 1)
      ..add(point('start', 0, 0))
      ..add(point('update', 100, 1))
      ..add(point('end', 200, 0));
    expect(attempt.finish(aborted: false, readable: null, hapticsHelpful: null)['success'], isFalse);
    attempt
      ..add(point('start', 300, 0))
      ..add(point('update', 400, 99))
      ..add(point('end', 500, 0));
    expect(attempt.finish(aborted: false, readable: null, hapticsHelpful: null)['success'], isTrue);
  });

  test('metrics count overshoot and corrections; feedback time is excluded', () {
    final attempt = CrownAttempt(count: 100, task: const CrownTask('forward', 10, 20, ''), repeat: 1);
    for (final p in [
      point('start', 100, 10),
      point('update', 200, 24),
      point('update', 300, 19),
      point('update', 400, 20.4),
      point('end', 500, 20.4),
      point('finish', 20000, 20.4),
    ]) {
      attempt.add(p);
    }
    final result = attempt.finish(aborted: false, readable: true, hapticsHelpful: false);
    expect(result['duration_us'], 400000);
    expect(result['overshoot_titles'], 4);
    expect(result['corrections'], 2);
    expect(result['success'], isTrue);
    expect(result['haptics_helpful'], isFalse);
  });

  test('failed and aborted attempts remain failures; reverse overshoot is measured', () {
    final attempt = CrownAttempt(count: 100, task: const CrownTask('back', 20, 10, ''), repeat: 1)
      ..add(point('start', 0, 20))
      ..add(point('update', 100, 7))
      ..add(point('end', 200, 8));
    final result = attempt.finish(aborted: false, readable: null, hapticsHelpful: null);
    expect(result['success'], isFalse);
    expect(result['overshoot_titles'], 3);
    expect(result['corrections'], 1);
    expect(attempt.finish(aborted: true, readable: null, hapticsHelpful: null)['success'], isFalse);
  });

  test('baseline replay remains anchored and event sampling does not change results', () {
    for (final count in crownLibrarySizes) {
      final max = (count - 1) * crownRowExtent;
      double map(double dy) => baselineOffsetForDrag(
        startPixels: max / 2,
        startY: 300,
        dragDelta: dy,
        railHeight: 600,
        minExtent: 0,
        maxExtent: max,
      );
      expect(map(0), max / 2);
      expect(map(252), max);
      expect(map(-252), 0);
      final sparse = [0.0, 120.0, 80.0, 80.0, -252.0].map(map).toList();
      final dense = <double>[];
      for (final end in [0.0, 120.0, 80.0, 80.0, -252.0]) {
        for (var i = 1; i <= 12; i++) {
          map(end * i / 12);
        }
        dense.add(map(end));
      }
      expect(dense, sparse);
      expect(map(80), map(80), reason: 'holding a finger cannot cause motion');
    }
  });

  testWidgets('calibration uses one actual wheel and captures recognizer samples', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: CrownCalibration(restoreSession: false)));
    await tester.pumpAndSettle();
    expect(find.byType(ScrollCrown), findsOneWidget);
    await tester.tap(find.text('Zet startpositie klaar'));
    await tester.pumpAndSettle();
    final rail = tester.getRect(find.byKey(const ValueKey('scroll_crown_rail')));
    final gesture = await tester.startGesture(Offset(rail.right - 20, rail.center.dy));
    await gesture.moveBy(const Offset(0, 35));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(find.textContaining('Sleep de kroon in één haal'), findsOneWidget);
    final finish = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Klaar / gestopt'));
    expect(finish.onPressed, isNull, reason: 'release observation must finish first');
  });

  testWidgets('ordinary list drag stays one-to-one and can finish a measurement', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: CrownCalibration(restoreSession: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zet startpositie klaar'));
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView));
    final controller = list.controller!;
    final bounds = tester.getRect(find.byType(ListView));
    final gesture = await tester.startGesture(bounds.center);
    await gesture.moveBy(const Offset(0, -30), timeStamp: const Duration(seconds: 1));
    await tester.pump();
    final before = controller.offset;
    await gesture.moveBy(const Offset(0, -72), timeStamp: const Duration(seconds: 3));
    await tester.pump();
    expect(controller.offset - before, closeTo(72, .001));
    await gesture.up(timeStamp: const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    final finish = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Klaar / gestopt'));
    expect(finish.onPressed, isNotNull, reason: 'normal list scrolling is valid input as well');
    expect(find.byType(ScrollCrown), findsOneWidget);
  });

  testWidgets('observer records real drag geometry and no motion after release', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final samples = <Map<String, Object>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ScrollCrown(
          controller: controller,
          enabled: true,
          onDragSample: samples.add,
          child: ListView.builder(
            controller: controller,
            itemCount: 1000,
            itemExtent: crownRowExtent,
            itemBuilder: (_, i) => Text('row $i'),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('scroll_crown_rail')), findsOneWidget);
    await tester.tapAt(const Offset(380, 300));
    await tester.pump();
    final gesture = await tester.startGesture(const Offset(380, 300));
    var eventTime = Duration.zero;
    for (final y in [340.0, 380.0, 365.0]) {
      eventTime += const Duration(milliseconds: 100);
      await gesture.moveTo(Offset(380, y), timeStamp: eventTime);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await gesture.up();
    await tester.pump();
    expect(samples.first['event'], 'start');
    expect(samples.last['event'], 'end');
    expect(samples.where((s) => s['event'] == 'update'), isNotEmpty);
    final start = samples.first;
    var expectedPixels = (start['pixels'] as num).toDouble();
    final motion = CrownDragMotion(
      y: (start['y'] as num).toDouble() - 48,
      time: Duration(microseconds: start['input_down_us'] as int),
    );
    for (final sample in samples.where((s) => s['event'] == 'update')) {
      double n(String key) => (sample[key] as num).toDouble();
      expectedPixels = motion.move(
        y: n('y') - 48,
        time: Duration(microseconds: sample['input_time_us'] as int),
        pixels: expectedPixels,
        minExtent: n('live_min'),
        maxExtent: n('live_max'),
        rangeExtent: n('range_extent'),
        travel: n('rail_height') - 96,
      );
      expect(n('pixels'), closeTo(expectedPixels, .01));
    }
    final stopped = controller.offset;
    await tester.pump(const Duration(seconds: 1));
    expect(controller.offset, stopped);
    const outputPath = String.fromEnvironment('CROWN_TRACE_OUTPUT');
    if (outputPath.isNotEmpty) {
      final attempt = CrownAttempt(count: 1000, task: const CrownTask('observer-fixture', 0, 100, ''), repeat: 1);
      for (final sample in samples) {
        attempt.add(sample);
      }
      File(outputPath).writeAsStringSync(
        jsonEncode({
          'schema': 1,
          'condition': CrownDragMotion.model,
          'source_commit': 'widget-synthetic',
          'physical_device': false,
          'complete': false,
          'attempts': [attempt.finish(aborted: false, readable: null, hapticsHelpful: null)],
        }),
      );
    }
  });

  for (final mismatch in ['source', 'hash']) {
    testWidgets('a previous-$mismatch session remains exportable and recovery preserves original bytes', (
      tester,
    ) async {
      final dir = (await tester.runAsync(() => Directory('/tmp').createTemp('pleya-crown-recovery-')))!;
      final paths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TestPaths(dir.path);
      addTearDown(() {
        PathProviderPlatform.instance = paths;
        dir.deleteSync(recursive: true);
      });
      final original = jsonEncode({
        'schema': 1,
        'condition': CrownDragMotion.model,
        'source_commit': mismatch == 'source'
            ? 'older-source'
            : const String.fromEnvironment('GIT_COMMIT', defaultValue: 'unknown'),
        'calibration_source_sha256': mismatch == 'hash'
            ? 'older-hash'
            : const String.fromEnvironment('CALIBRATION_SOURCE_SHA256', defaultValue: 'unknown'),
        'attempts': [],
        'started_utc': 'previous-session',
      });
      File('${dir.path}/crown-direct-current.json').writeAsStringSync(original);
      await tester.pumpWidget(const MaterialApp(home: CrownCalibration()));
      for (var i = 0; i < 100 && find.text('Bewaar oude meting en start nieuwe').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(find.text('Bewaar oude meting en start nieuwe'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate((widget) => widget is IconButton && widget.tooltip == 'Exporteer meting'),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Zet startpositie klaar')).onPressed,
        isNull,
      );
      await tester.tap(find.text('Bewaar oude meting en start nieuwe'));
      for (var i = 0; i < 100 && find.text('Bewaar oude meting en start nieuwe').evaluate().isNotEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      final preserved = dir.listSync().whereType<File>().where((f) => f.path.contains('crown-preserved-')).single;
      expect(preserved.readAsStringSync(), original);
      expect(File('${dir.path}/crown-direct-current.json').readAsStringSync(), original);
      expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Zet startpositie klaar')).onPressed,
        isNotNull,
      );
    });
  }

  const tracePath = String.fromEnvironment('CROWN_TRACE');
  if (tracePath.isNotEmpty) {
    test('replay actual recorded baseline drag updates against shipped mapping', () {
      final session = jsonDecode(File(tracePath).readAsStringSync()) as Map<String, dynamic>;
      expect(session['condition'], 'baseline-401');
      var updates = 0;
      for (final attempt in session['attempts'] as List) {
        for (final sample in (attempt as Map)['samples'] as List) {
          final s = sample as Map;
          if (s['event'] != 'update') continue;
          double n(String key) => (s[key] as num).toDouble();
          final expected = baselineOffsetForDrag(
            startPixels: n('start_pixels'),
            startY: n('start_y'),
            dragDelta: n('y') - n('start_y'),
            railHeight: n('rail_height'),
            minExtent: n('min'),
            maxExtent: n('max'),
          );
          expect(n('pixels'), closeTo(expected, 0.01));
          updates++;
        }
      }
      expect(updates, greaterThan(0), reason: 'an empty trace is no evidence');
    });
  }
}
