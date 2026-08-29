import 'package:flutter/widgets.dart';

import 'automation_registry.dart';
import 'pleya_verify.dart';

/// Registers a stable automation ID for a widget that doesn't go through
/// `FocusableWrapper` (e.g. `NavigationRailItem`, which uses a raw `Focus`).
/// Pure pass-through when `!kPleyaVerify` or [id] is null — wraps nothing,
/// costs nothing, and is entirely tree-shaken out of a release binary.
class AutomationNode extends StatefulWidget {
  final String? id;
  final String? instance;
  final String role;
  final String? label;
  final FocusNode? focusNode;
  final Object? Function()? state;
  final Widget child;

  const AutomationNode({
    super.key,
    required this.id,
    this.instance,
    required this.role,
    this.label,
    this.focusNode,
    this.state,
    required this.child,
  });

  @override
  State<AutomationNode> createState() => _AutomationNodeState();
}

class _AutomationNodeState extends State<AutomationNode> {
  int? _token;

  String? get _resolvedId => widget.instance != null ? '${widget.id}[${widget.instance}]' : widget.id;

  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void didUpdateWidget(AutomationNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    // `role`, `label` and `focusNode` are captured by value at registration
    // time, so a change to any of them needs a fresh registration. `state`
    // deliberately is not in this list: it is registered as an indirection
    // (see [_register]) and therefore always reads the current widget.
    if (oldWidget.id != widget.id ||
        oldWidget.instance != widget.instance ||
        oldWidget.role != widget.role ||
        oldWidget.label != widget.label ||
        !identical(oldWidget.focusNode, widget.focusNode)) {
      _unregister();
      _register();
    }
  }

  void _register() {
    if (!kPleyaVerify) return;
    final id = _resolvedId;
    if (id == null) return;
    _token = AutomationRegistry.instance.register(
      AutomationDeclaredNode(
        id: id,
        role: widget.role,
        label: widget.label,
        focusNode: widget.focusNode,
        contextGetter: () => mounted ? context : null,
        // Registered as an indirection through this State, not as the
        // closure `widget.state` happens to be right now — the same shape
        // `contextGetter` uses one line up, and for the same reason.
        // Callers build this closure inline over their own fields
        // (`NavigationRailItem` captures `selected`/`collapsed` that way),
        // so a rebuild hands us a *new* closure over *new* values while the
        // registry would keep answering from the first one. `/v1/ui_tree`
        // then reports the nav state from before the tab switch, and a
        // scenario asserting on it passes or fails against stale truth.
        state: () => widget.state?.call(),
      ),
    );
  }

  void _unregister() {
    final token = _token;
    if (token != null) AutomationRegistry.instance.unregister(token);
    _token = null;
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
