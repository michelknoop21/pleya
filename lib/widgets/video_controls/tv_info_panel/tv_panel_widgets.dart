import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../focus/focusable_wrapper.dart';
import '../../app_icon.dart';

/// Shared visual tokens for the Infuse-style TV info panel.
class TvPanelTheme {
  const TvPanelTheme._();

  /// Translucent near-black backdrop, consistent with the Netflix restyle.
  static const Color surface = Color(0xF0141414);
  static const Color activePill = Colors.white;
  static const Color inactivePill = Color(0x33FFFFFF);
  static const Color accent = Color(0xFFF42B1F);
  static const Color textMuted = Color(0xB3FFFFFF);
  static const Color textFaint = Color(0x80FFFFFF);
}

/// A single focusable row in a TV info panel tab (leading icon, title, trailing
/// value / chevron / check / custom widget). Vertical D-pad navigation between
/// rows is handled by the enclosing [FocusScope]'s directional traversal; only
/// the top row wires [onNavigateUp] to return focus to the pill tab bar.
class TvPanelRow extends StatelessWidget {
  final FocusNode? focusNode;
  final IconData? icon;
  final String title;
  final String? value;
  final bool selected;
  final bool showChevron;
  final bool highlighted;
  final Widget? trailing;
  final VoidCallback? onSelect;
  final VoidCallback? onNavigateUp;
  final bool autofocus;

  const TvPanelRow({
    super.key,
    this.focusNode,
    this.icon,
    required this.title,
    this.value,
    this.selected = false,
    this.showChevron = false,
    this.highlighted = false,
    this.trailing,
    this.onSelect,
    this.onNavigateUp,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final valueColor = highlighted ? TvPanelTheme.accent : TvPanelTheme.textMuted;

    Widget? trailingWidget = trailing;
    trailingWidget ??= () {
      if (selected) {
        return const AppIcon(Symbols.check_rounded, fill: 1, color: Colors.white, size: 22);
      }
      final children = <Widget>[];
      if (value != null) {
        children.add(
          Flexible(
            child: Text(
              value!,
              style: TextStyle(color: valueColor, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
      if (showChevron) {
        if (children.isNotEmpty) children.add(const SizedBox(width: 8));
        children.add(const AppIcon(Symbols.chevron_right_rounded, fill: 1, color: TvPanelTheme.textFaint, size: 20));
      }
      if (children.isEmpty) return null;
      return Row(mainAxisSize: MainAxisSize.min, children: children);
    }();

    return FocusableWrapper(
      focusNode: focusNode,
      autofocus: autofocus,
      onSelect: onSelect,
      onNavigateUp: onNavigateUp,
      borderRadius: 10,
      autoScroll: true,
      mode: FocusIndicatorMode.fill,
      // Rows already show a background highlight on focus; the default scale-up
      // pushes the trailing value past the panel's clip edge, truncating it
      // mid-word ("Letterbo…"). Disable scaling here.
      disableScale: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            if (icon != null) ...[
              AppIcon(icon!, fill: 1, color: highlighted ? TvPanelTheme.accent : Colors.white, size: 22),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Cap the trailing (value / chevron) width so a long value ellipsizes
            // inside the row instead of overflowing past the panel's clipped edge.
            if (trailingWidget != null) ...[
              const SizedBox(width: 12),
              ConstrainedBox(constraints: const BoxConstraints(maxWidth: 280), child: trailingWidget),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small uppercase section header (SPOREN / OPTIES).
class TvPanelSectionHeader extends StatelessWidget {
  final String label;
  const TvPanelSectionHeader({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: TvPanelTheme.textFaint,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}
