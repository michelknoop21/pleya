import 'package:flutter/material.dart';
import '../focus/card_focus_scope.dart';
import '../focus/focus_theme.dart';
import '../focus/focusable_wrapper.dart';
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

/// Groups settings rows into one card, the way system settings do. The card
/// supplies the surface, the rounded edge and the hairlines between rows.
///
/// The inner [Material] is load-bearing, not decoration. Ink features (ripple,
/// hover, the Material focus highlight) are painted by the nearest enclosing
/// Material *before* its descendants, so without one here they land on the
/// Scaffold underneath and this card's opaque surface paints straight over
/// them. That is what made focus in settings invisible.
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
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
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
        ),
      ],
    );
  }
}

/// One settings row, carrying the focus treatment the rest of the TV UI uses.
///
/// This wrapper is the row's single focus owner. `descendantsAreFocusable:
/// false` keeps the tile's own `InkWell` out of the focus tree, so the D-pad
/// gets exactly one stop per row and SELECT runs the same callback a tap does.
/// Leaving the tile focusable underneath would give two targets per row: an
/// extra press on the way down, and focus visuals on the wrapper while Enter is
/// handled by the child.
///
/// Pointer input is untouched — `descendantsAreFocusable` governs focus, not hit
/// testing, so the tile keeps its own `onTap`, ripple and hover.
class SettingRowFocus extends StatelessWidget {
  final Widget child;

  /// Runs on SELECT/Enter. Pass the same callback the tile's `onTap` uses.
  final VoidCallback? onSelect;

  final FocusNode? focusNode;
  final bool enabled;

  const SettingRowFocus({super.key, required this.child, required this.onSelect, this.focusNode, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return FocusableWrapper(
      focusNode: focusNode,
      canRequestFocus: enabled,
      descendantsAreFocusable: false,
      // A row that grows on focus would push the rows under it down the card.
      disableScale: true,
      // The fill and border come from the theme tokens below rather than from
      // the wrapper's white-on-artwork defaults: a settings row sits on an
      // opaque card that flips with the theme, where a white ring on white is
      // no ring at all.
      delegateFocusBorder: true,
      onSelect: enabled ? onSelect : null,
      child: _SettingRowSurface(child: child),
    );
  }
}

class _SettingRowSurface extends StatelessWidget {
  final Widget child;

  const _SettingRowSurface({required this.child});

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final focused = CardFocusScope.maybeOf(context) ?? false;
    return AnimatedContainer(
      duration: FocusTheme.getAnimationDuration(context),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(t.radiusSm),
        color: focused ? t.surfaceElevated : Colors.transparent,
        // The border is present in both states and only changes colour. One
        // that appears on focus would inset the content and make the row jump.
        border: Border.all(
          color: focused ? t.text.withValues(alpha: 0.85) : Colors.transparent,
          width: FocusTheme.focusBorderWidth,
        ),
      ),
      child: child,
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
