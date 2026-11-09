import 'package:flutter/material.dart';

import '../automation/automation_ids.dart';
import '../automation/automation_node.dart';
import '../focus/focusable_wrapper.dart';
import '../theme/mono_theme.dart';
import '../theme/mono_tokens.dart';

/// What a Regiekamer tile is about. The tone colours the number only: amber for
/// what waits on the viewer, ink for the rest.
enum SeerrCockpitTone { waiting, neutral }

/// One count tile above the Regiekamer list (mockup C1): a big number and what
/// it counts. [count] null is a count that is not known: the tile shows a
/// dash, never a zero, because a zero is a count.
class SeerrCockpitTile extends StatelessWidget {
  const SeerrCockpitTile({
    super.key,
    required this.instance,
    required this.count,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.tone = SeerrCockpitTone.neutral,
  });

  final String instance;
  final int? count;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final SeerrCockpitTone tone;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final theme = Theme.of(context);
    final number = count == null ? '–' : '$count';
    return AutomationNode(
      id: AutomationIds.requestsListTile,
      instance: instance,
      role: 'button',
      label: '$number $label',
      state: () => {'selected': selected, 'count': count},
      child: FocusableWrapper(
        disableScale: true,
        borderRadius: tk.radiusMd,
        onSelect: onTap,
        semanticLabel: '$number $label',
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: BoxDecoration(
              color: tk.surface,
              borderRadius: BorderRadius.circular(tk.radiusMd),
              border: Border.all(color: selected ? tk.text : Colors.transparent, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  number,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 26,
                    height: 1.15,
                    letterSpacing: -0.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: tone == SeerrCockpitTone.waiting && (count ?? 0) > 0 ? kAccentAlt : tk.text,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: tk.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The tiles in one row of equal columns, with the list's 16 pt margin.
class SeerrCockpitTiles extends StatelessWidget {
  const SeerrCockpitTiles({super.key, required this.tiles});

  final List<SeerrCockpitTile> tiles;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: tiles[i])],
        ],
      ),
    );
  }
}
