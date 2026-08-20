import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../utils/app_logger.dart';
import 'notice.dart';

/// One notice plus its live queue/dedupe state. Never exposed directly —
/// [NoticeController.visible] projects it to the read-only [NoticeEntry].
class _Slot {
  final String id;
  Notice notice;
  int count;
  DateTime lastSeen;
  Timer? _timer;

  _Slot({required this.id, required this.notice, required this.lastSeen}) : count = 1;

  String get dedupeKey => '${notice.level.name}:${notice.groupKey}';

  void cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Read-only view of a queued/visible notice for widgets to render.
@immutable
class NoticeEntry {
  final String id;
  final Notice notice;

  /// How many times this group has fired within the dedupe window. 1 for a
  /// notice shown once; the card renders a "×N" counter when > 1.
  final int count;

  const NoticeEntry({required this.id, required this.notice, required this.count});
}

/// Queue + dedupe + auto-dismiss for [Notice]s, decoupled from any widget
/// tree. A single global instance ([noticeController]) backs [NoticeHost];
/// nothing about showing a notice requires a [BuildContext], which is what
/// lets [NoticeAction] callbacks stay the caller's responsibility instead of
/// the host's — see the doc comment on [NoticeAction].
class NoticeController extends ChangeNotifier {
  /// At most this many notices render on screen at once; the rest wait in
  /// [_queued] and are promoted in FIFO order as visible ones clear.
  static const int maxVisible = 3;

  /// Hard ceiling on the queue so a sustained error loop (e.g. a retrying
  /// background sync) can't grow this into an unbounded buffer. Dropping the
  /// oldest queued entry past this point is logged — never fully silent —
  /// but errors are not specially protected: a genuine flood is a bug
  /// elsewhere, not something this queue should paper over by growing
  /// forever.
  static const int maxQueued = 50;

  /// Two notices with the same level + groupKey within this window are
  /// folded into one entry with an incrementing counter instead of stacking.
  static const Duration dedupeWindow = Duration(seconds: 10);

  final List<_Slot> _visible = [];
  final List<_Slot> _queued = [];
  int _seq = 0;

  List<NoticeEntry> get visible =>
      List.unmodifiable(_visible.map((s) => NoticeEntry(id: s.id, notice: s.notice, count: s.count)));

  /// Shows [notice], returning the id of the slot it landed in (new, or an
  /// existing one it was folded into).
  String show(Notice notice) {
    final now = DateTime.now();
    final key = '${notice.level.name}:${notice.groupKey}';

    final foldTarget = _findFoldTarget(key, now);
    if (foldTarget != null) {
      foldTarget.count++;
      foldTarget.lastSeen = now;
      if (_visible.contains(foldTarget)) _restartTimer(foldTarget);
      notifyListeners();
      return foldTarget.id;
    }

    final slot = _Slot(id: 'notice-${_seq++}', notice: notice, lastSeen: now);
    if (_visible.length < maxVisible) {
      _visible.add(slot);
      _restartTimer(slot);
    } else {
      if (_queued.length >= maxQueued) {
        final dropped = _queued.removeAt(0);
        appLogger.w(
          'NoticeController: queue full ($maxQueued), dropping oldest queued notice "${dropped.notice.title}"',
        );
      }
      _queued.add(slot);
    }
    notifyListeners();
    return slot.id;
  }

  _Slot? _findFoldTarget(String dedupeKey, DateTime now) {
    for (final slot in _visible.followedBy(_queued)) {
      if (slot.dedupeKey == dedupeKey && now.difference(slot.lastSeen) < dedupeWindow) {
        return slot;
      }
    }
    return null;
  }

  void _restartTimer(_Slot slot) {
    slot.cancelTimer();
    final duration = slot.notice.duration;
    if (duration == null) return; // persistent (errors)
    slot._timer = Timer(duration, () => dismiss(slot.id));
  }

  /// Dismisses the notice in [id] (visible or still queued) and promotes the
  /// oldest queued notice into its place if one is waiting.
  void dismiss(String id) {
    final visibleIndex = _visible.indexWhere((s) => s.id == id);
    if (visibleIndex != -1) {
      _visible.removeAt(visibleIndex).cancelTimer();
      _promoteFromQueue();
      notifyListeners();
      return;
    }
    final queuedIndex = _queued.indexWhere((s) => s.id == id);
    if (queuedIndex != -1) {
      _queued.removeAt(queuedIndex);
      notifyListeners();
    }
  }

  void _promoteFromQueue() {
    if (_queued.isEmpty || _visible.length >= maxVisible) return;
    final next = _queued.removeAt(0);
    _visible.add(next);
    _restartTimer(next);
  }

  /// Runs [action]'s callback, then dismisses the notice it belongs to — the
  /// plan's "blijft staan tot wegklikken of tot de actie is uitgevoerd".
  ///
  /// [NoticeAction.onPressed] is declared as a [VoidCallback], but a caller
  /// can still assign an `async` closure to it (Dart allows a
  /// `Future<void> Function()` where a `void Function()` is expected) — most
  /// retry actions in this codebase do exactly that. [Future.sync] catches
  /// both a synchronous throw and, because it detects when the call returns
  /// a `Future`, an asynchronous rejection from that closure too, so either
  /// failure mode is logged here instead of becoming an unhandled Future
  /// error in whatever zone happens to be current. This is a backstop, not
  /// the primary error path: every current caller already handles its own
  /// failures (typically by showing a fresh [Notice] from inside a `catch`,
  /// the way `noticeForError`'s retry callers do) — this only fires for a
  /// callback that forgot to.
  void runAction(String id, NoticeAction action) {
    Future.sync(action.onPressed).catchError((Object error, StackTrace stackTrace) {
      appLogger.e('NoticeAction callback failed', error: error, stackTrace: stackTrace);
    });
    dismiss(id);
  }

  @override
  void dispose() {
    for (final s in _visible.followedBy(_queued)) {
      s.cancelTimer();
    }
    super.dispose();
  }
}

/// Global controller backing [NoticeHost]. A singleton mirrors the existing
/// `rootScaffoldMessengerKey` / `profileNavigationRegistry` pattern: showing
/// a notice never needs a [BuildContext].
final noticeController = NoticeController();
