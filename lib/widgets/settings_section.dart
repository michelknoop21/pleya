import 'package:flutter/material.dart';
import '../theme/mono_tokens.dart';
import 'app_icon.dart';

/// Widest the settings content grows on desktop and TV. Full-width rows on a
/// 1440pt window put the switch a hand's width away from its label, so the
/// column stays readable instead of stretching.
const double kSettingsMaxWidth = 880;

/// Row inset used by every settings tile. Slightly wider than the Material
/// default so the icon badge does not touch the card edge.
const EdgeInsets kSettingRowPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 6);

/// Centers settings content once the window is wider than [kSettingsMaxWidth].
/// On phones it is a plain horizontal inset, so mobile layout is unchanged.
class SettingsWidthLimit extends StatelessWidget {
  final Widget child;
  final double horizontal;

  const SettingsWidthLimit({super.key, required this.child, this.horizontal = 0});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontal),
          child: child,
        ),
      ),
    );
  }
}

class SettingsSectionHeader extends StatelessWidget {
  /// Read back by [SettingsPage] when it folds a flat row list into cards.
  final String title;

  const SettingsSectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: tokens(context).textMuted,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

/// Groups settings rows into one card, the way system settings do. Rows keep
/// their own focus and hit targets; the card only supplies the surface, the
/// rounded edge and the hairlines between rows.
class SettingsGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;

  const SettingsGroup({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final rows = children.where((c) => c is! SizedBox).toList(growable: false);
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) SettingsSectionHeader(title!),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(t.radiusMd),
            border: Border.all(color: t.outline.withValues(alpha: 0.6)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, thickness: 1, indent: 68, endIndent: 0, color: t.outline.withValues(alpha: 0.5)),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Icon in a tinted rounded square. Gives every row the same optical weight and
/// keeps a long settings list from reading as undifferentiated text.
class SettingsIconBadge extends StatelessWidget {
  final IconData icon;
  final Color? tint;

  const SettingsIconBadge(this.icon, {super.key, this.tint});

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final color = tint ?? t.text;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: t.isLight ? 0.08 : 0.12),
        borderRadius: BorderRadius.circular(t.radiusSm),
      ),
      alignment: Alignment.center,
      child: AppIcon(icon, fill: 1, size: 20, color: color),
    );
  }
}

/// A setting with a label + icon row and a full-width SegmentedButton below.
/// Used for settings with 2-4 short options.
class SegmentedSetting<T> extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<ButtonSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  const SegmentedSetting({
    super.key,
    required this.icon,
    required this.title,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          Row(
            children: [
              AppIcon(icon, fill: 1),
              const SizedBox(width: 16),
              Text(title, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<T>(
              segments: segments,
              selected: {selected},
              onSelectionChanged: (Set<T> newSelection) {
                onChanged(newSelection.first);
              },
              showSelectedIcon: false,
            ),
          ),
        ],
      ),
    );
  }
}
