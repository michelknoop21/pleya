import 'package:flutter/scheduler.dart';

import 'automation_event_log.dart';
import 'automation_registry.dart';

/// Resolves a `POST /v1/wait` predicate: an event by name (optionally scoped
/// to a `since` cursor), a `/v1/ui_tree` node matching simple field checks,
/// or a plain frame-stability wait. Polls rather than blocks on a
/// notification — deterministic to test, and cheap since this only runs
/// while a caller is actively waiting.
class AutomationWait {
  const AutomationWait();

  Future<Map<String, Object?>> resolve(Map<String, Object?> body) async {
    final timeoutMs = (body['timeoutMs'] as num?)?.toInt() ?? 5000;
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));

    final eventSpec = (body['event'] as Map?)?.cast<String, Object?>();
    final nodeSpec = (body['node'] as Map?)?.cast<String, Object?>();
    if (eventSpec != null) return _waitForEvent(eventSpec, deadline);
    if (nodeSpec != null) return _waitForNode(nodeSpec, deadline);

    final stableFrames = (body['stableFrames'] as num?)?.toInt() ?? 2;
    await _waitFrames(stableFrames);
    return {'ok': true, 'reason': 'stableFrames'};
  }

  Future<Map<String, Object?>> _waitForEvent(Map<String, Object?> spec, DateTime deadline) async {
    final name = spec['name'] as String?;
    final since = (spec['since'] as num?)?.toInt() ?? 0;
    while (true) {
      final matches = AutomationEventLog.instance.since(since).where((e) => name == null || e.name == name);
      if (matches.isNotEmpty) return {'ok': true, 'event': matches.first.toJson()};
      if (DateTime.now().isAfter(deadline)) return {'ok': false, 'reason': 'timeout'};
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<Map<String, Object?>> _waitForNode(Map<String, Object?> spec, DateTime deadline) async {
    final id = spec['id'] as String?;
    final wantVisible = spec['visible'] as bool?;
    final wantFocused = spec['focused'] as bool?;
    while (true) {
      final snapshot = AutomationRegistry.instance.snapshot();
      final nodes = <Map<String, Object?>>[
        ...(snapshot['declared'] as List).cast<Map<String, Object?>>(),
        ...(snapshot['discovered'] as List).cast<Map<String, Object?>>(),
      ];
      final match = nodes.where((n) {
        if (id != null && n['id'] != id) return false;
        // The node's own answer, not `bounds != null`: an `IndexedStack`
        // lays out every tab it keeps mounted, so the old derivation called
        // the screen parked behind the visible one visible too. Nodes that
        // cannot report it (no mounted render object) fall back to the old
        // rule rather than dropping out of every wait.
        if (wantVisible != null && (n['visible'] as bool? ?? n['bounds'] != null) != wantVisible) return false;
        if (wantFocused != null && n['focused'] != wantFocused) return false;
        return true;
      });
      if (match.isNotEmpty) return {'ok': true, 'node': match.first};
      if (DateTime.now().isAfter(deadline)) return {'ok': false, 'reason': 'timeout'};
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _waitFrames(int count) async {
    try {
      for (var i = 0; i < count; i++) {
        await SchedulerBinding.instance.endOfFrame;
      }
    } catch (_) {
      // No live SchedulerBinding (app not booted / plain test) — nothing to
      // wait for.
    }
  }
}
