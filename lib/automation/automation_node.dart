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
    if (oldWidget.id != widget.id || oldWidget.instance != widget.instance) {
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
        state: widget.state,
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
