import 'dart:async';

/// Why a reconciliation was asked for.
///
/// The list is closed on purpose. Every moment the engine has to catch up with
/// the store is one of these, and naming them is what stopped the question
/// "does anything reconcile here?" from being answered per call site.
enum ReconcileTrigger {
  /// The app started with sync already on.
  boot,

  /// The user just switched sync on.
  enabled,

  /// The app came back to the foreground. A key-value store can change while
  /// the process is suspended, and the notification for it can be missed.
  foreground,

  /// The iCloud account changed underneath us.
  accountChanged,

  /// A different Pleya profile became active, so a different namespace applies.
  profileChanged,

  /// Settings were imported from a file.
  imported,

  /// Settings were reset.
  reset,
}

/// Turns a stream of triggers into non-overlapping reconciliation runs.
///
/// Two guarantees, and they are the whole reason this exists:
///
/// - triggers raised in the same turn produce **one** run. Boot alone can fire
///   three of them (the toggle is read, the profile is restored, the first
///   foreground arrives), and running three full passes over the store is both
///   wasteful and a way to race yourself;
/// - a trigger raised **during** a run produces exactly one follow-up run, not
///   one per trigger. The follow-up is needed — the run in flight read the
///   store before the change existed — but only once.
///
/// Nothing here waits on a clock. The coalescing window is a microtask, so it
/// closes when the current turn ends: deterministic in a test, and impossible
/// to tune into a correctness bug the way a `Future.delayed` debounce can be.
class PreferenceReconcileScheduler {
  PreferenceReconcileScheduler({required this.run, this.onError});

  final Future<void> Function(Set<ReconcileTrigger>) run;

  /// Where a failing run goes. The scheduler completes its waiters either way:
  /// a caller that asked for a reconcile is not the right place to handle a
  /// transport error, and leaving the future to fail would make an unawaited
  /// `request` an unhandled async error.
  final void Function(Object)? onError;

  final Set<ReconcileTrigger> _pending = {};
  Completer<void>? _waiters;
  bool _scheduled = false;
  bool _running = false;
  bool _disposed = false;

  /// Runs completed since construction. Test-facing: "one run, not three" is
  /// the property, so it has to be observable.
  int get runCount => _runCount;
  int _runCount = 0;

  /// Ask for a reconciliation. The future completes when a run that includes
  /// this trigger has finished.
  Future<void> request(ReconcileTrigger trigger) {
    if (_disposed) return Future<void>.value();
    _pending.add(trigger);
    final waiters = _waiters ??= Completer<void>();
    _schedule();
    return waiters.future;
  }

  void _schedule() {
    if (_scheduled || _running || _pending.isEmpty) return;
    _scheduled = true;
    scheduleMicrotask(_drain);
  }

  Future<void> _drain() async {
    _scheduled = false;
    if (_running || _pending.isEmpty || _disposed) return;
    final batch = Set<ReconcileTrigger>.unmodifiable(_pending);
    _pending.clear();
    final waiters = _waiters;
    _waiters = null;
    _running = true;
    try {
      await run(batch);
    } catch (e) {
      onError?.call(e);
    } finally {
      _running = false;
      _runCount++;
      waiters?.complete();
      // Anything that arrived while this run was in flight is one batch, and
      // it gets exactly one run.
      _schedule();
    }
  }

  /// Stop accepting work. Waiters for a run already in flight still complete.
  void dispose() {
    _disposed = true;
    _pending.clear();
    _waiters?.complete();
    _waiters = null;
  }
}
