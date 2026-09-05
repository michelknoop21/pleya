import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../utils/log_redaction_manager.dart';

/// A stable, process-scoped number for one `FocusNode`, handed out on first
/// sight and never reused.
///
/// `/v1/ui_tree`'s `discovered` list has no identity: `label` is
/// `'FocusableWrapper'` for most of the app, and `focused` is true for the
/// whole ancestor chain of the focused node, so two frames cannot be lined up
/// against each other by anything but a rect. That is exactly what a focus
/// walk needs and exactly what a rect cannot give it, because rects move under
/// the press being judged — rails scroll on focus, so the node that was at
/// `x=740` before is at `x=380` after, and matching by geometry across the
/// press silently pairs up the wrong two nodes.
///
/// An [Expando] is the right shape for it: the number lives as long as the
/// `FocusNode` does and disappears with it, so a rebuilt subtree gets new
/// numbers rather than a stale map growing for the life of the process. The
/// numbers are meaningful **within one app run only** — nothing persists them,
/// and a scenario must never hard-code one.
final Expando<int> _nodeNumbers = Expando<int>('pleyaVerifyNodeNumber');
int _nextNodeNumber = 1;

/// The number for [node], assigning one if this is the first time it is seen.
int automationNodeNumber(FocusNode node) => _nodeNumbers[node] ??= _nextNodeNumber++;

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
    for (final node in _reachableFirst(_declared.values)) {
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
        if (node.focusNode != null) 'node': automationNodeNumber(node.focusNode!),
        if (_boundsOf(node.contextGetter?.call()) case final bounds?) 'bounds': _boundsToJson(bounds),
        'state': ?node.state?.call(),
      });
    }

    return {'declared': declared, 'discovered': _discoveredFocusables(), 'duplicates': duplicates};
  }

  /// Registration order, except that a node on screen comes before an
  /// identically-named node that is not.
  ///
  /// Two screens in this app are mounted twice at once. `SettingsScreen` and
  /// `LibrariesScreen` are `MainScreen` destinations *and* Mijn Pleya
  /// sections, and `MainScreen` keeps its destinations alive in an
  /// `IndexedStack` with the inactive ones wrapped in `ExcludeFocus` and
  /// `TickerMode(enabled: false)`. Both copies register every id in them, and
  /// the suffix hands the second one `#2`.
  ///
  /// Which one got the bare id was decided by registration order, and the
  /// offstage copy registers first. Two scenarios were measured against the
  /// wrong screen because of it: `tvos.my-pleya.library-chooser` waited out
  /// its timeout on a chip that cannot take focus at all, and then read
  /// `library.header` as "Movies" from the copy nobody had touched while the
  /// page on screen had already switched to Shows. A scenario naming an id
  /// means the thing a viewer is looking at.
  ///
  /// Two signals, in that order:
  ///
  /// 1. **Is it painted?** [_isDisplayed] walks the render tree for an
  ///    ancestor that hides this subtree. That covers a node with no focus
  ///    node of its own, which is the case `library.header` needed.
  /// 2. **Can the remote reach it?** `ExcludeFocus` is how the shell says "not
  ///    this one", and it is the same signal `TvNestedSurface` relies on.
  ///
  /// Deliberately dependency-free: this runs from an HTTP handler, not from a
  /// build, so it reads the render tree directly rather than through
  /// `TickerMode.of` or any other inherited lookup that would register the
  /// registry as a dependent and schedule rebuilds behind a read-only call.
  Iterable<AutomationDeclaredNode> _reachableFirst(Iterable<AutomationDeclaredNode> nodes) {
    final byId = <String, int>{};
    for (final node in nodes) {
      byId.update(node.id, (n) => n + 1, ifAbsent: () => 1);
    }
    if (!byId.values.any((n) => n > 1)) return nodes;

    int rank(AutomationDeclaredNode n) {
      if (!_isDisplayed(n.contextGetter?.call())) return 2;
      return (n.focusNode?.canRequestFocus ?? true) ? 0 : 1;
    }

    // A stable partition per colliding id, so everything else keeps the order
    // it registered in.
    final ordered = nodes.toList();
    final result = <AutomationDeclaredNode>[];
    final placed = <AutomationDeclaredNode>{};
    for (final node in ordered) {
      if (placed.contains(node)) continue;
      if (byId[node.id] == 1) {
        result.add(node);
        placed.add(node);
        continue;
      }
      final group = ordered.where((n) => n.id == node.id).toList();
      for (var tier = 0; tier <= 2; tier++) {
        for (final n in group.where((n) => rank(n) == tier)) {
          result.add(n);
          placed.add(n);
        }
      }
    }
    return result;
  }

  /// Whether anything between this node and the root is hiding it.
  ///
  /// Only the two mechanisms this app actually hides things with, and
  /// unknown-shaped trees answer `true`: a wrong "displayed" leaves the
  /// ordering exactly as it was before, while a wrong "hidden" would push a
  /// real node behind a suffix.
  static bool _isDisplayed(BuildContext? context) {
    RenderObject? child;
    try {
      child = context?.findRenderObject();
    } catch (_) {
      return true;
    }
    if (child == null) return true;

    var parent = child.parent;
    while (parent != null) {
      // `Offstage`, and `Visibility`/`Visibility.maintain`, which compose it.
      if (parent is RenderOffstage && parent.offstage) return false;
      if (parent is RenderIndexedStack) {
        var seen = 0;
        var found = -1;
        final target = child;
        parent.visitChildren((c) {
          if (identical(c, target)) found = seen;
          seen++;
        });
        if (found >= 0 && found != parent.index) return false;
      }
      child = parent;
      parent = parent.parent;
    }
    return true;
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
      'node': automationNodeNumber(node),
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
      discovered.add({
        if (label != null) 'label': LogRedactionManager.redact(label),
        'focused': focusNode.hasFocus,
        'canRequestFocus': focusNode.canRequestFocus,
        'node': automationNodeNumber(focusNode),
        if (bounds != null) 'bounds': _boundsToJson(bounds),
      });
    }
    return discovered;
  }

  /// The node's rect, with position and size in the **same** space.
  ///
  /// This used to be `localToGlobal(Offset.zero) & size`, and those two halves
  /// do not live in the same coordinate system. `localToGlobal` resolves
  /// through every ancestor transform, `_AppleTvScale`'s `Transform.scale`
  /// included ([DEC-028] renders Apple TV at 1.85), so the offset came back in
  /// the 1920x1080 root space. `size` is the box's own local size and stayed in
  /// the 1038x584 logical space the `MediaQuery` under that transform reports.
  /// Every rect this endpoint published was therefore 1.85x out of step with
  /// itself: the hub's tile pitch agreed with the capture at `x * 2` while the
  /// same tile's painted width agreed at `w * 3.7`.
  ///
  /// Nothing caught it because no assertion compared the two halves. A left
  /// inset measured off `x` looked plausible, `insideViewport` compared a root
  /// space rect against a logical space viewport and passed anyway on a page
  /// with margins to spare, and the styling audit measured its inset table off
  /// screenshots instead.
  ///
  /// Transforming the whole rect fixes it in one place. The result is the root
  /// space, which is also the space hoofdstuk 8 states every TV measurement in
  /// ("een 1920x1080 TV *output* surface"), so a design token and a reported
  /// bound are finally the same kind of number. [_viewportSnapshot] reports the
  /// viewport in that space too, or the pair would just be inconsistent the
  /// other way round.
  Rect? _boundsOf(BuildContext? context) {
    if (context == null || !context.mounted) return null;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached || !renderObject.hasSize) return null;
    return MatrixUtils.transformRect(renderObject.getTransformTo(null), Offset.zero & renderObject.size);
  }

  Map<String, Object?> _boundsToJson(Rect bounds) => {
    'x': bounds.left,
    'y': bounds.top,
    'width': bounds.width,
    'height': bounds.height,
  };
}

/// How much bigger one logical pixel at [context] is in the root space.
///
/// 1.0 everywhere except Apple TV, where `_AppleTvScale`'s `Transform.scale`
/// sits between the app's `MediaQuery` and the render view ([DEC-028]). Read
/// off the render tree rather than from a constant, so it stays honest if that
/// factor changes or a second transform ever appears above the app.
///
/// `/v1/viewport` needs this because [AutomationRegistry] reports bounds in the
/// root space: a viewport in logical pixels next to root-space bounds is the
/// same mismatch, only moved. Returns null when it cannot be established.
double? rootSpaceScaleOf(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.attached || !renderObject.hasSize) return null;
  final unit = MatrixUtils.transformRect(renderObject.getTransformTo(null), const Rect.fromLTWH(0, 0, 1, 1));
  return unit.width.isFinite && unit.width > 0 ? unit.width : null;
}
