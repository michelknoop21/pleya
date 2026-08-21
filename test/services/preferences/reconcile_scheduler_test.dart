import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/preferences/preference_reconcile_scheduler.dart';

/// A8 and review constraint R2: one scheduler owns every trigger, overlapping
/// requests collapse, and nothing waits on a clock.
void main() {
  test('three triggers in one turn produce one run', () async {
    final batches = <Set<ReconcileTrigger>>[];
    final scheduler = PreferenceReconcileScheduler(run: (t) async => batches.add(t));

    await Future.wait([
      scheduler.request(ReconcileTrigger.boot),
      scheduler.request(ReconcileTrigger.profileChanged),
      scheduler.request(ReconcileTrigger.foreground),
    ]);

    expect(scheduler.runCount, 1);
    expect(batches.single, {ReconcileTrigger.boot, ReconcileTrigger.profileChanged, ReconcileTrigger.foreground});
  });

  test('the same trigger twice in one turn is still one run', () async {
    final scheduler = PreferenceReconcileScheduler(run: (_) async {});

    await Future.wait([scheduler.request(ReconcileTrigger.foreground), scheduler.request(ReconcileTrigger.foreground)]);

    expect(scheduler.runCount, 1);
  });

  test('triggers arriving during a run produce exactly one follow-up run', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final batches = <Set<ReconcileTrigger>>[];
    late PreferenceReconcileScheduler scheduler;
    scheduler = PreferenceReconcileScheduler(
      run: (t) async {
        batches.add(t);
        if (batches.length == 1) {
          started.complete();
          await release.future;
        }
      },
    );

    final first = scheduler.request(ReconcileTrigger.boot);
    await started.future;

    // Three more while the first is still in flight.
    final queued = Future.wait([
      scheduler.request(ReconcileTrigger.foreground),
      scheduler.request(ReconcileTrigger.imported),
      scheduler.request(ReconcileTrigger.reset),
    ]);
    release.complete();
    await first;
    await queued;

    expect(scheduler.runCount, 2);
    expect(batches[0], {ReconcileTrigger.boot});
    expect(batches[1], {ReconcileTrigger.foreground, ReconcileTrigger.imported, ReconcileTrigger.reset});
  });

  test('runs never overlap', () async {
    var concurrent = 0;
    var maxConcurrent = 0;
    final scheduler = PreferenceReconcileScheduler(
      run: (_) async {
        concurrent++;
        maxConcurrent = concurrent > maxConcurrent ? concurrent : maxConcurrent;
        await Future<void>.delayed(Duration.zero);
        concurrent--;
      },
    );

    for (var i = 0; i < 5; i++) {
      unawaited(scheduler.request(ReconcileTrigger.foreground));
      await Future<void>.delayed(Duration.zero);
    }
    await scheduler.request(ReconcileTrigger.boot);

    expect(maxConcurrent, 1);
  });

  test('a failing run reaches the error sink and does not break the next one', () async {
    final errors = <Object>[];
    var runs = 0;
    final scheduler = PreferenceReconcileScheduler(
      run: (_) async {
        runs++;
        if (runs == 1) throw StateError('transport down');
      },
      onError: errors.add,
    );

    await scheduler.request(ReconcileTrigger.boot);
    await scheduler.request(ReconcileTrigger.foreground);

    expect(errors, hasLength(1));
    expect(runs, 2);
  });

  test('a waiter never hangs, even when the run throws', () async {
    final scheduler = PreferenceReconcileScheduler(run: (_) async => throw StateError('nope'), onError: (_) {});

    await expectLater(scheduler.request(ReconcileTrigger.boot), completes);
  });

  test('after dispose nothing runs again', () async {
    var runs = 0;
    final scheduler = PreferenceReconcileScheduler(run: (_) async => runs++);
    scheduler.dispose();

    await scheduler.request(ReconcileTrigger.boot);

    expect(runs, 0);
  });

  test('the scheduler itself contains no wall-clock delay', () {
    // The property this file exists to protect: coalescing rides on the
    // microtask queue, so it is deterministic and cannot be tuned into a
    // correctness bug the way a debounce interval can.
    final source = File('lib/services/preferences/preference_reconcile_scheduler.dart').readAsStringSync();
    // Comments are allowed to name what the code must not do.
    final code = source.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

    expect(code.contains('Future.delayed'), isFalse);
    expect(code.contains('Timer('), isFalse);
    expect(code.contains('scheduleMicrotask'), isTrue);
  });
}
