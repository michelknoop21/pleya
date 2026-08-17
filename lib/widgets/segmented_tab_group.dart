import 'package:flutter/material.dart';

import '../theme/mono_tokens.dart';

/// Wraps a row of [FocusableTabChip]s in one surface so they read as a single
/// segmented control instead of four separate buttons. The chips keep their own
/// focus nodes and key handling; this only draws the enclosure.
class SegmentedTabGroup extends StatelessWidget {
  final List<Widget> children;

  const SegmentedTabGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final tk = tokens(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: tk.surface,
        borderRadius: BorderRadius.circular(tk.radiusMd),
        border: Border.all(color: tk.outline.withValues(alpha: 0.7)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}
