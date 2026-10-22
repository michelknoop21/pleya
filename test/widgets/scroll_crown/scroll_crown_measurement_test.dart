import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/library_first_character.dart';
import 'package:pleya/screens/libraries/alpha_scroll_handle.dart';
import 'package:pleya/widgets/scroll_crown/scroll_crown.dart';

const _screen = Size(400, 720);
const _rowHeight = 100.0;

String _title(int index) => 'Titel ${index.toString().padLeft(5, '0')}';

/// Fixed spatial samples; only their timestamps vary between replays.
/// A fast approach deliberately overshoots before four slow 1 px corrections.
List<({double y, int ms})> _motion(int approachMs) => [
  (y: 360, ms: 0),
  for (var step = 1; step <= 80; step++) (y: 360 + step * 2.0, ms: step * approachMs),
  for (var step = 1; step <= 4; step++) (y: 520 - step.toDouble(), ms: 80 * approachMs + step * 80),
];

class _Library extends StatefulWidget {
  const _Library({super.key, required this.count, required this.alphabet});

  final int count;
  final bool alphabet;

  @override
  State<_Library> createState() => _LibraryState();
}

class _LibraryState extends State<_Library> {
  final controller = ScrollController();
  final ticks = <Map<String, Object>>[];
  Duration now = Duration.zero;
  int? selected;

  double get fraction => controller.hasClients && controller.position.maxScrollExtent > 0
      ? controller.offset / controller.position.maxScrollExtent
      : 0;

  // Groups supply a changing position label, never a second drag model.
  String get letter => fraction < 0.5 ? 'A' : 'B';

  void tick(String kind) => ticks.add({'us': now.inMicroseconds, 'kind': kind});

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = ListView.builder(
      controller: controller,
      padding: EdgeInsets.zero,
      itemExtent: _rowHeight,
      itemCount: widget.count,
      itemBuilder: (_, index) => TextButton(
        onPressed: () => selected = index,
        child: Text(_title(index)),
      ),
    );
    return MaterialApp(
      home: Scaffold(
        body: widget.alphabet
            ? NotificationListener<ScrollNotification>(
                onNotification: (_) {
                  setState(() {});
                  return false;
                },
                child: Stack(
                  children: [
                    list,
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: 0,
                      child: AlphaScrollHandle(
                        firstCharacters: [
                          LibraryFirstCharacter(key: 'A', title: 'A', size: widget.count ~/ 2),
                          LibraryFirstCharacter(key: 'B', title: 'B', size: widget.count - widget.count ~/ 2),
                        ],
                        currentLetter: letter,
                        readScrollFraction: () => fraction,
                        onScrub: (value) => controller.jumpTo(value * controller.position.maxScrollExtent),
                        onJump: (_) => throw StateError('A drag must not jump by letter'),
                        clock: () => now,
                        onToothTick: () => tick('tooth'),
                        onLetterTick: () => tick('letter'),
                      ),
                    ),
                  ],
                ),
              )
            : ScrollCrown(
                enabled: true,
                controller: controller,
                clock: () => now,
                onToothTick: () => tick('tooth'),
                child: list,
              ),
      ),
    );
  }
}

Future<List<Map<String, Object>>> _replay(
  WidgetTester tester, {
  required int count,
  required bool alphabet,
  required int approachMs,
}) async {
  await tester.pumpWidget(const SizedBox());
  final key = GlobalKey<_LibraryState>();
  await tester.pumpWidget(_Library(key: key, count: count, alphabet: alphabet));
  await tester.pump();
  final state = key.currentState!;
  final samples = <Map<String, Object>>[];
  final path = _motion(approachMs);
  // Wake the generic rail with the same tap before every trial.
  await tester.tapAt(const Offset(378, 360));
  await tester.pump();
  state.selected = null;
  state.ticks.clear();
  final epoch = tester.binding.clock.now();
  final gesture = await tester.startGesture(
    Offset(378, path.first.y),
    timeStamp: Duration.zero,
  );
  void sample(double y, String phase) => samples.add({
    'us': state.now.inMicroseconds,
    'y': y,
    'phase': phase,
    'pixels': state.controller.offset,
    'maxPixels': state.controller.position.maxScrollExtent,
    'topTitle': _title((state.controller.offset / _rowHeight).floor()),
    'tickCount': state.ticks.length,
  });
  sample(path.first.y, 'down');
  for (var index = 1; index < path.length; index++) {
    final point = path[index];
    final elapsed = Duration(milliseconds: point.ms);
    // Advance frame time, pointer time and haptic clock together.
    final delay = elapsed - tester.binding.clock.now().difference(epoch);
    if (delay > Duration.zero) await tester.pump(delay);
    state.now = elapsed;
    await gesture.moveTo(Offset(378, point.y), timeStamp: elapsed);
    await tester.pump();
    sample(point.y, index <= 80 ? 'approach' : 'correction');
  }
  await gesture.up(timeStamp: state.now);
  await tester.pump();
  sample(path.last.y, 'up');
  // Concrete choose task, using an actually visible title without ensureVisible.
  final target = count ~/ 2;
  final choice = find.text(_title(target)).hitTestable();
  expect(choice, findsOneWidget, reason: 'choose the middle numbered title after correcting');
  await tester.tap(choice);
  await tester.pump();
  expect(state.selected, target);
  final tickCount = state.ticks.length;
  expect(state.ticks.where((tick) => tick['kind'] == 'tooth'), isNotEmpty);
  await tester.pump(const Duration(milliseconds: 200));
  expect(state.ticks.length, tickCount, reason: 'haptics must not queue after release');
  debugPrintSynchronously(
    'CROWN_BASELINE ${jsonEncode({
      'schema': 1,
      'model': 'baseline',
      'surface': alphabet ? 'alphabet' : 'generic',
      'count': count,
      'viewport': [400, 720],
      'rowHeight': _rowHeight,
      'approachMsPerSample': approachMs,
      'target': _title(target),
      'selected': _title(state.selected!),
      'samples': samples,
      'ticks': state.ticks,
    })}',
  );
  await tester.pumpWidget(const SizedBox());
  return samples;
}

void main() {
  for (final count in [100, 1000, 10000]) {
    testWidgets('baseline: $count numbered titles, both crowns, three replay speeds', (tester) async {
      tester.view.physicalSize = _screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      List<Map<String, Object>>? reference;
      for (final alphabet in [false, true]) {
        for (final approachMs in [5, 20, 80]) {
          final samples = await _replay(tester, count: count, alphabet: alphabet, approachMs: approachMs);
          if (reference != null) {
            for (var index = 0; index < samples.length; index++) {
              expect(
                samples[index]['pixels'] as double,
                closeTo(reference[index]['pixels'] as double, 0.01),
                reason: 'baseline position at sample $index: speed and label do not change the drag model',
              );
            }
          }
          reference ??= samples;
          final approach = samples.where((sample) => sample['phase'] == 'approach').last;
          final corrected = samples.where((sample) => sample['phase'] == 'correction').last;
          expect(corrected['pixels'] as double, lessThan(approach['pixels'] as double));
          expect(corrected['pixels'] as double, greaterThan(0));
          expect(corrected['pixels'] as double, lessThan(corrected['maxPixels'] as double));
        }
      }
    });
  }
}
