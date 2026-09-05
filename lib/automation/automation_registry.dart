import 'package:flutter/widgets.dart';

import '../utils/log_redaction_manager.dart';

/// A stable, agent-addressable UI node registered by a widget under
/// `kPleyaVerify`. Populated starting with the automation-ID rollout (A.2 in
/// the Pleya Verify plan); the registry works — and `/v1/ui_tree` reports
/// discovered focusables — before any widget registers one.
///
/// [focusNode] and [contextGetter] are how `snapshot()` resolves live focus
/// and bounds — the same pattern `_discoveredFocusables()` already uses for
/// nodes it walks off `FocusManager`, so a declared node ends up shaped the
/// same as a discovered one, just with a stable [id] besides.
class AutomationDeclaredNode {
  final String id;
  final String role;
  final String? label;
  final FocusNode? focusNode;
  final BuildContext? Function()? contextGetter;
  final Object? Function()? state;

  const AutomationDeclaredNode({
    required this.id,
    required this.role,
    this.label,
    this.focusNode,
    this.contextGetter,
    this.state,
  });
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
    // Per base id, not one shared counter. `seen.length` counts *all*
    // distinct ids emitted so far, so with several colliding ids in one
    // tree the same suffix can be handed out twice — `a`,`a`,`b`,`b`,`a`
    // produced `a#2`, `b#4`, `a#4` — and two nodes sharing an id in the
    // snapshot is precisely what this suffix exists to prevent.
    final occurrences = <String, int>{};
    for (final node in _declared.values) {
      var id = node.id;
      final seenBefore = occurrences.update(id, (n) => n + 1, ifAbsent: () => 1);
      if (seenBefore > 1) {
        duplicates.add(node.id);
        id = '${node.id}#$seenBefore';
      }
      declared.add({
        'id': id,
        'role': node.role,
        if (node.label != null) 'label': LogRedactionManager.redact(node.label!),
        'focused': node.focusNode?.hasFocus ?? false,
        if (node.focusNode != null) 'canRequestFocus': node.focusNode!.canRequestFocus,
        if (_boundsOf(node.contextGetter?.call()) case final bounds?) 'bounds': _boundsToJson(bounds),
        'visible': ?_visibilityOf(node.contextGetter?.call()),
        'state': ?node.state?.call(),
      });
    }

    return {'declared': declared, 'discovered': _discoveredFocusables(), 'duplicates': duplicates};
  }

  /// The `GET /v1/focus` payload: whatever `FocusManager` currently reports
  /// as primary focus, shaped like a discovered node. `null` when nothing is
  /// focused or no `WidgetsBinding` exists yet.
  Map<String, Object?>? focusSnapshot() {
    FocusNode? node;
    try {
      node = FocusManager.instance.primaryFocus;
    } catch (_) {
      return null;
    }
    if (node == null) return null;
    final label = node.debugLabel;
    final bounds = _boundsOf(node.context);
    return {
      if (label != null) 'label': LogRedactionManager.redact(label),
      'focused': node.hasFocus,
      'canRequestFocus': node.canRequestFocus,
      if (bounds != null) 'bounds': _boundsToJson(bounds),
    };
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
      final bounds = _boundsOf(focusNode.context);
      final visible = _visibilityOf(focusNode.context);
      discovered.add({
        if (label != null) 'label': LogRedactionManager.redact(label),
        'focused': focusNode.hasFocus,
        'canRequestFocus': focusNode.canRequestFocus,
        if (bounds != null) 'bounds': _boundsToJson(bounds),
        'visible': ?visible,
      });
    }
    return discovered;
  }

  /// Whether this node would end up on screen if a frame were painted now,
  /// or `null` when there is nothing mounted to answer the question with —
  /// the same "reported without the field rather than with a guess" rule
  /// [_boundsOf] follows.
  ///
  /// Two sources, because neither one alone is enough:
  ///
  /// * The render tree answers for everything that declares it skips its
  ///   child: `RenderOffstage`, a zero `RenderOpacity`, a collapsed box, a
  ///   sliver scrolled out of its viewport. `paintsChild` is exactly that
  ///   question, asked at every step up to the root.
  /// * `Visibility` is the hole in that: it skips `paint` without overriding
  ///   `paintsChild`, so the render walk calls a hidden child painted. That
  ///   would be a footnote if `IndexedStack` did not wrap every one of its
  ///   children in precisely that widget — which is how the shell keeps all
  ///   tabs mounted, and why a tab nobody is looking at reports the same
  ///   rect as the one on screen. So the element tree gets asked too.
  bool? _visibilityOf(BuildContext? context) {
    if (context == null || !context.mounted) return null;
    try {
      final renderObject = context.findRenderObject();
      if (renderObject == null || !renderObject.attached) return null;

      var child = renderObject;
      for (var parent = child.parent; parent != null; child = parent, parent = parent.parent) {
        if (!parent.paintsChild(child)) return false;
      }

      var visible = true;
      context.visitAncestorElements((element) {
        if (element.widget case Visibility(visible: false)) {
          visible = false;
          return false;
        }
        return true;
      });
      return visible;
    } catch (_) {
      // An element that is mounted but no longer active throws on an
      // ancestor lookup. Same degradation as the FocusManager walk above:
      // report nothing rather than fail the whole snapshot.
      return null;
    }
  }

  Rect? _boundsOf(BuildContext? context) {
    if (context == null || !context.mounted) return null;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached || !renderObject.hasSize) return null;
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  Map<String, Object?> _boundsToJson(Rect bounds) => {
    'x': bounds.left,
    'y': bounds.top,
    'width': bounds.width,
    'height': bounds.height,
  };
}
