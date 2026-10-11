import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../theme/mono_tokens.dart';
import '../../../utils/platform_detector.dart';
import '../../../widgets/app_icon.dart';
import 'memory_style.dart';

export 'memory_style.dart';

/// The shared pieces of the memory screens on a phone and a tablet (mockup
/// 43): cards, rows, pills and chips. Every colour comes from the theme
/// tokens, so the screens read in the light theme as well.

enum MemoryPillKind { primary, tonal, danger }

/// A full-width pill button (`.btn`, `.tbtn.danger`): the white primary, the
/// grey second choice, or the red text action.
class MemoryPillButton extends StatelessWidget {
  const MemoryPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = MemoryPillKind.tonal,
    this.icon,
    this.focusNode,
    this.autofocus = false,
    this.automationId,
    this.automationInstance,
    this.onNavigateUp,
    this.onNavigateLeft,
    this.onNavigateRight,
  });

  final String label;
  final VoidCallback? onPressed;
  final MemoryPillKind kind;
  final IconData? icon;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? automationId;
  final String? automationInstance;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final k = MemoryScale.of(context);
    // On TV the focus is the white button: at rest every choice has the
    // resting fill, the destructive one included, so only one is ever white.
    final remote = PlatformDetector.isTV();
    return MemoryPressable(
      onPressed: onPressed,
      shape: const StadiumBorder(),
      focusNode: focusNode,
      autofocus: autofocus,
      semanticLabel: label,
      automationId: automationId,
      automationInstance: automationInstance,
      automationState: () => {'enabled': enabled},
      onNavigateUp: onNavigateUp,
      onNavigateLeft: onNavigateLeft,
      onNavigateRight: onNavigateRight,
      child: Builder(
        builder: (context) {
          final tk = tokens(context);
          final focused = remote && Focus.of(context).hasFocus;
          final (fill, ink) = switch (kind) {
            // A text action that is off stays text; a pill that is off stays a pill.
            _ when !enabled => (
              kind == MemoryPillKind.danger && !remote ? Colors.transparent : tk.text.withValues(alpha: 0.14),
              memoryFaint(context),
            ),
            _ when focused => (tk.text, tk.bg),
            _ when remote => (tk.text.withValues(alpha: 0.16), tk.text),
            MemoryPillKind.primary => (tk.text, tk.bg),
            MemoryPillKind.tonal => (tk.text.withValues(alpha: 0.16), tk.text),
            MemoryPillKind.danger => (Colors.transparent, tk.accent),
          };
          return Container(
            constraints: BoxConstraints(minHeight: 48 * k),
            padding: EdgeInsets.symmetric(horizontal: 18 * k, vertical: 10 * k),
            decoration: ShapeDecoration(shape: const StadiumBorder(), color: fill),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[AppIcon(icon, size: 19 * k, color: ink), SizedBox(width: 8 * k)],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: memoryText(
                      context,
                      16,
                      weight: kind == MemoryPillKind.danger && !remote ? FontWeight.w500 : FontWeight.w700,
                      color: ink,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Two pill buttons side by side (`.btnrow`). At a large text size they
/// stand under each other, the first on top, so no label breaks inside a
/// word.
class MemoryButtonPair extends StatelessWidget {
  const MemoryButtonPair({super.key, required this.first, this.second});

  final Widget first;
  final Widget? second;

  /// From this text size a label no longer fits half the width of a phone.
  static const double stackAbove = 1.3;

  @override
  Widget build(BuildContext context) {
    final other = second;
    if (other == null) return first;
    final k = MemoryScale.of(context);
    if (!PlatformDetector.isTV() && MediaQuery.textScalerOf(context).scale(1) > stackAbove) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          first,
          SizedBox(height: 4 * k),
          other,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: first),
        SizedBox(width: 10 * k),
        Expanded(child: other),
      ],
    );
  }
}

/// A category chip (`.chip`): the chosen one is filled with the ink colour.
class MemoryChoiceChip extends StatelessWidget {
  const MemoryChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.onSurface = false,
    this.automationId,
    this.automationInstance,
    this.focusNode,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
    this.onNavigateRight,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;

  /// Inside a sheet, where the resting fill is the page colour.
  final bool onSurface;
  final String? automationId;
  final String? automationInstance;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final k = MemoryScale.of(context);
    return MemoryPressable(
      onPressed: onPressed,
      shape: const StadiumBorder(),
      semanticLabel: label,
      automationId: automationId,
      automationInstance: automationInstance,
      automationState: () => {'selected': selected},
      focusNode: focusNode,
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
      onNavigateLeft: onNavigateLeft,
      onNavigateRight: onNavigateRight,
      // A 44 pt touch area around the 34 pt chip.
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 5 * k),
        child: Container(
          constraints: BoxConstraints(minHeight: 34 * k),
          padding: EdgeInsets.symmetric(horizontal: 14 * k, vertical: 6 * k),
          decoration: ShapeDecoration(
            color: selected ? tk.text : (onSurface ? tk.bg : tk.surface),
            shape: StadiumBorder(side: BorderSide(color: selected ? tk.text : tk.outline)),
          ),
          child: Text(
            label,
            style: memoryText(
              context,
              14,
              weight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? tk.bg : tk.textMuted,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

/// A grouped card (`.card`).
class MemoryCard extends StatelessWidget {
  const MemoryCard({super.key, required this.children, this.color});

  final List<Widget> children;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return Material(
      color: color ?? tk.surface,
      borderRadius: BorderRadius.circular(14 * MemoryScale.of(context)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: tk.text.withValues(alpha: 0.07)),
            child,
          ],
        ],
      ),
    );
  }
}

/// A row of a card (`.srow`): title, an optional second line, an optional
/// value and a chevron.
class MemoryRow extends StatelessWidget {
  const MemoryRow({
    super.key,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onPressed,
    this.chevron = true,
    this.automationId,
    this.automationInstance,
    this.automationRole = 'button',
    this.automationState,
  });

  final String title;
  final String? subtitle;
  final String? value;

  /// Replaces the chevron, for a switch.
  final Widget? trailing;
  final VoidCallback? onPressed;
  final bool chevron;
  final String? automationId;
  final String? automationInstance;
  final String automationRole;
  final Object? Function()? automationState;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final k = MemoryScale.of(context);
    return MemoryPressable(
      onPressed: onPressed,
      semanticLabel: [title, subtitle, value].nonNulls.join('. '),
      automationId: automationId,
      automationInstance: automationInstance,
      automationRole: automationRole,
      automationState: automationState,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 54 * k),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14 * k, vertical: 12 * k),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: memoryText(context, 16, weight: FontWeight.w500, height: 1.3)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: memoryText(context, 13, color: tk.textMuted, height: 1.35)),
                    ],
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 12),
                Text(value!, style: memoryText(context, 15, color: tk.textMuted)),
              ],
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              if (trailing == null && chevron) ...[
                SizedBox(width: 12 * k),
                AppIcon(Symbols.chevron_right_rounded, size: 18 * k, color: memoryFaint(context)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The small capital label above a group (`.glabel`), with an optional count
/// on the right.
class MemoryGroupLabel extends StatelessWidget {
  const MemoryGroupLabel(this.label, {super.key, this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    // The count drops under the label when a large text size leaves no room
    // for both on one line.
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 12,
      runSpacing: 2,
      children: [
        Text(
          label.toUpperCase(),
          style: memoryText(
            context,
            12.5,
            weight: FontWeight.w700,
            color: memoryFaint(context),
          ).copyWith(letterSpacing: 1),
        ),
        if (trailing != null) Text(trailing!, style: memoryText(context, 13, color: memoryFaint(context))),
      ],
    ),
  );
}

/// The switch of 43 C as a picture of the state: the row around it is the
/// control, so this takes no focus and no tap of its own.
class MemorySwitchMark extends StatelessWidget {
  const MemorySwitchMark({super.key, required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return AnimatedContainer(
      duration: reduceMotion(context, tk.fast),
      width: 50,
      height: 30,
      padding: const EdgeInsets.all(3),
      alignment: on ? Alignment.centerRight : Alignment.centerLeft,
      decoration: ShapeDecoration(shape: const StadiumBorder(), color: on ? tk.text : tk.text.withValues(alpha: 0.2)),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(shape: BoxShape.circle, color: on ? tk.bg : memoryFaint(context)),
      ),
    );
  }
}

/// The grab bar at the top of a sheet (`.sheet .grab`).
class MemorySheetGrab extends StatelessWidget {
  const MemorySheetGrab({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 36,
      height: 5,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: tokens(context).text.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(3),
      ),
    ),
  );
}
