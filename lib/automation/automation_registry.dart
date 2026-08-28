import 'package:flutter/widgets.dart';

import '../utils/log_redaction_manager.dart';

/// A stable, agent-addressable UI node registered by a widget under
/// `kPleyaVerify`. Populated starting with the automation-ID rollout (A.2 in
/// the Pleya Verify plan); the registry works — and `/v1/ui_tree` reports
/// discovered focusables — before any widget registers one.
class AutomationDeclaredNode {
  final String id;
  final String role;
  final String? label;

  const AutomationDeclaredNode({required this.id, required this.role, this.label});
}

/// Declared nodes (explicit `AutomationDeclaredNode` registrations) merged
/// with discovered focusables (walked from `FocusManager`), the source both
/// `GET /v1/ui_tree` and the diagnostic overlay read from.
class AutomationRegistry {
  AutomationRegistry._();

  static final AutomationRegistry instance = AutomationRegistry._();

  // Keyed by an opaque registration token, not by `node.id` — two widgets
  // registering the same id (a bug upstream, or a missing instance suffix)
  // must both survive until `snapshot()` disambiguates them, rather than
  // silently colliding into a single map entry.
  final Map<int, AutomationDeclaredNode> _declared = {};
  int _nextToken = 0;

  int register(AutomationDeclaredNode node) {
    final token = _nextToken++;
    _declared[token] = node;
    return token;
  }

  void unregister(int token) => _declared.remove(token);

  /// Builds the full `/v1/ui_tree` payload. Declared nodes with a duplicate
  /// `id` get a `#2`, `#3`, … suffix and are listed under `duplicates` —
  /// never silently overwritten.
  Map<String, Object?> snapshot() {
    final declared = <Map<String, Object?>>[];
    final duplicates = <String>[];
    final seen = <String>{};
    for (final node in _declared.values) {
      var id = node.id;
      if (!seen.add(id)) {
        duplicates.add(node.id);
        id = '${node.id}#${seen.length}';
      }
      declared.add({
        'id': id,
        'role': node.role,
        if (node.label != null) 'label': LogRedactionManager.redact(node.label!),
      });
    }

    return {'declared': declared, 'discovered': _discoveredFocusables(), 'duplicates': duplicates};
  }

  List<Map<String, Object?>> _discoveredFocusables() {
    final discovered = <Map<String, Object?>>[];
    Iterable<FocusNode> focusNodes;
    try {
      // Requires a live WidgetsBinding — absent before the app has booted
      // (or in a plain, non-widget test). Degrade to an empty list rather
      // than fail the whole snapshot.
      focusNodes = FocusManager.instance.rootScope.traversalDescendants;
    } catch (_) {
      return discovered;
    }
    for (final focusNode in focusNodes) {
      final label = focusNode.debugLabel;
      Rect? bounds;
      final context = focusNode.context;
      if (context != null && context.mounted) {
        final renderObject = context.findRenderObject();
        if (renderObject is RenderBox && renderObject.attached && renderObject.hasSize) {
          bounds = renderObject.localToGlobal(Offset.zero) & renderObject.size;
        }
      }
      discovered.add({
        if (label != null) 'label': LogRedactionManager.redact(label),
        'focused': focusNode.hasFocus,
        'canRequestFocus': focusNode.canRequestFocus,
        if (bounds != null)
          'bounds': {'x': bounds.left, 'y': bounds.top, 'width': bounds.width, 'height': bounds.height},
      });
    }
    return discovered;
  }
}
