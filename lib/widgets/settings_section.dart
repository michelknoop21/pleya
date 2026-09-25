import 'package:flutter/material.dart';
import '../automation/automation_ids.dart';
import '../focus/card_focus_scope.dart';
import '../focus/focus_theme.dart';
import '../focus/focusable_wrapper.dart';
import '../theme/mono_tokens.dart';
import '../theme/tv_switch_theme.dart';
import '../utils/platform_detector.dart';
import '../utils/tv_hig.dart';
import 'app_icon.dart';
import 'settings_rows.dart';
import 'tv/tv_unified_layout.dart';

export 'settings_rows.dart';

/// Widest the settings content grows on desktop and TV. Full-width rows on a
/// 1440pt window put the switch a hand's width away from its label, so the
/// column stays readable instead of stretching.
const double kSettingsMaxWidth = 880;

/// Row inset used by every settings tile. Slightly wider than the Material
/// default so the icon badge does not touch the card edge.
const EdgeInsets kSettingRowPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 6);

/// The row inset a settings tile passes to its `ListTile`. On TV it is null,
/// so the tile takes [TvSettingsDensity]'s HIG inset from the theme instead of
/// a phone value that the TV wrapper would blow up 1.85 times.
EdgeInsetsGeometry? settingRowPadding() => PlatformDetector.isTV() ? null : kSettingRowPadding;

/// DENS1: settings rows on TV in Apple's tvOS HIG sizes. Title in Body (29 pt),
/// value line in Caption 1 (25 pt), a 10 pt vertical inset and no enforced
/// minimum height. VIS-0925-G (DEC-139) took the rows from 60/92 pt to 56/84:
/// the text stays at HIG size, the air around it shrinks. Without it a
/// two-line row inherited `ListTile`'s dense minimum of 64 logical pixels plus phone padding, which the TV wrapper turns
/// into a 138 pt row around 26/22 pt text: 4.5 rows on a screen that holds 9.
/// Off TV it returns [child] unchanged.
class TvSettingsDensity extends StatelessWidget {
  final Widget child;

  const TvSettingsDensity({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!PlatformDetector.isTV()) return child;
    final pt = TvHig.of(context);
    final t = tokens(context);
    // The TV switch theme (VIS-0925-C), shared with the overlay sheets.
    return TvSwitchTheme(
      child: ListTileTheme.merge(
        dense: false,
        visualDensity: VisualDensity.standard,
        minTileHeight: 0,
        minVerticalPadding: 0,
        minLeadingWidth: 0,
        horizontalTitleGap: 20 * pt,
        contentPadding: EdgeInsets.symmetric(horizontal: 24 * pt, vertical: 10 * pt),
        titleTextStyle: TextStyle(
          color: t.text,
          fontSize: TvHig.body * pt,
          height: TvHig.bodyLeading / TvHig.body,
          fontWeight: FontWeight.w500,
        ),
        subtitleTextStyle: TextStyle(
          color: t.textMuted,
          fontSize: TvHig.caption1 * pt,
          // 28 pt leading, not the table's 32: one line under a Body title needs
          // no extra lead of its own.
          height: 28 / TvHig.caption1,
        ),
        leadingAndTrailingTextStyle: TextStyle(color: t.textMuted, fontSize: TvHig.caption1 * pt),
        child: child,
      ),
    );
  }
}

/// Alpha of a [SettingsGroup]'s outer card border, against [MonoTokens.outline].
const double kSettingsOutlineAlpha = 0.6;

/// Alpha of the hairline [SettingsRows] paints between two visible rows.
const double kSettingsSeparatorAlpha = 0.5;

/// Alpha of the hairline between rows on TV (VIS-0925-C): lighter than the
/// focus ring, so a card reads as one surface and not as a table.
const double kTvSettingsSeparatorAlpha = 0.35;

/// Left inset of a row separator on TV, in HIG points: the row inset (24),
/// the icon badge (44) and the title gap (20), so the line starts under the
/// title as on tvOS.
const double kTvSettingsSeparatorIndentPt = 88;

/// Width of the leading focus marker a settings row paints instead of a border.
const double kSettingsFocusBarWidth = 3;

/// Alpha of the focus marker, against [MonoTokens.text].
const double kSettingsFocusBarAlpha = 0.85;

/// The one card-border colour every settings surface shares: [MonoTokens.outline]
/// at [kSettingsOutlineAlpha]. Anything that draws its own settings-style card
/// (there are a couple, outside [SettingsGroup] itself) reads this instead of
/// re-deriving the alpha by hand.
Color settingsOutlineColor(BuildContext context) => tokens(context).outline.withValues(alpha: kSettingsOutlineAlpha);

/// The row-separator colour every [SettingsRows] paints: [MonoTokens.outline]
/// at [kSettingsSeparatorAlpha]. Exposed so a [SettingsRows] built outside
/// [SettingsGroup] (e.g. a nested connections list) matches it exactly.
Color settingsSeparatorColor(BuildContext context) =>
    tokens(context).outline.withValues(alpha: kSettingsSeparatorAlpha);

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
    final tv = PlatformDetector.isTV();
    final pt = tv ? TvHig.of(context) : 1.0;
    return Padding(
      // VIS-0925-G: less air between the page title, this label and the card.
      padding: tv ? EdgeInsets.fromLTRB(24 * pt, 20 * pt, 24 * pt, 8 * pt) : const EdgeInsets.fromLTRB(20, 24, 20, 10),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: tokens(context).textMuted,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          // DENS1: HIG Caption 2 (23 pt) on TV, the tvOS minimum.
          fontSize: tv ? TvHig.caption2 * pt : null,
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
///
/// [children] is rendered as-is now, unlike the old implementation: a plain
/// `SizedBox(height: N)` used to be silently dropped (it was filtered by
/// type) and no longer is. [SettingsRows] instead decides visibility from
/// laid-out height, so any child with real height becomes a real row with
/// hairline separators around it. A spacer that only wants bottom margin
/// should not be a child here; the card's own margin already provides one.
class SettingsGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;

  const SettingsGroup({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    if (children.isEmpty) return const SizedBox.shrink();
    final radius = BorderRadius.circular(t.radiusMd);
    // VIS-0925-C: on TV no outer border and lighter, indented separators. The
    // bordered card with full-width hairlines read as a table on the tv.
    final tv = PlatformDetector.isTV();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) SettingsSectionHeader(title!),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          // The border lives in foregroundDecoration, painted after the rows
          // (see SettingsRows below) so it always wins over a full-bleed
          // focus fill instead of being painted over by the first/last row.
          decoration: BoxDecoration(color: t.surface, borderRadius: radius),
          foregroundDecoration: tv
              ? null
              : BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: settingsOutlineColor(context)),
                ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: SettingsRows(
              separatorColor: tv
                  ? t.outline.withValues(alpha: kTvSettingsSeparatorAlpha)
                  : settingsSeparatorColor(context),
              separatorIndent: tv ? kTvSettingsSeparatorIndentPt * TvHig.of(context) : kSettingsSeparatorIndent,
              children: children,
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
/// Pointer input is untouched: `descendantsAreFocusable` governs focus, not hit
/// testing, so the tile keeps its own `onTap`, ripple and hover.
class SettingRowFocus extends StatelessWidget {
  final Widget child;

  /// Runs on SELECT/Enter. Pass the same callback the tile's `onTap` uses.
  final VoidCallback? onSelect;

  final FocusNode? focusNode;
  final bool enabled;

  /// Registers the row as `my_pleya.section.tile[<automationInstance>]` for
  /// Pleya Verify, the id every other TV settings row already uses.
  final String? automationInstance;
  final Object? Function()? automationState;

  const SettingRowFocus({
    super.key,
    required this.child,
    required this.onSelect,
    this.focusNode,
    this.enabled = true,
    this.automationInstance,
    this.automationState,
  });

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
      mode: FocusIndicatorMode.delegated,
      onSelect: enabled ? onSelect : null,
      automationId: automationInstance == null ? null : AutomationIds.myPleyaSectionTile,
      automationInstance: automationInstance,
      automationRole: 'grid.item',
      automationState: automationState,
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
    if (PlatformDetector.isTV()) {
      // VIS-0925-C: on TV a row takes the same focus as every tile on the
      // page, the lighter ink fill plus the white ring, instead of a third
      // focus language (a leading bar). In foregroundDecoration, so the ring
      // never becomes padding and never nudges the row's content.
      return AnimatedContainer(
        duration: FocusTheme.getAnimationDuration(context),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: focused ? t.text.withValues(alpha: TvMyPleyaLayout.tileFocusedFillAlpha) : Colors.transparent,
          borderRadius: BorderRadius.circular(t.radiusMd),
        ),
        // Inside the card's clip, so the Light separator has to stay inside
        // the row (FocusRingBorder.separatorInside).
        foregroundDecoration: FocusTheme.focusDecoration(
          context,
          isFocused: focused,
          borderRadius: t.radiusMd,
          separatorInside: true,
        ),
        child: child,
      );
    }
    return AnimatedContainer(
      duration: FocusTheme.getAnimationDuration(context),
      curve: Curves.easeOutCubic,
      // The fill only, so it never competes with SettingsRows' separators or
      // SettingsGroup's outer border: both painted by an ancestor, after
      // this row.
      decoration: BoxDecoration(color: focused ? t.surfaceElevated : Colors.transparent),
      // A leading marker instead of a perimeter: it does not sit on the
      // group's own hairlines or corners, so it cannot double up with them.
      // In foregroundDecoration, so unlike the old full border it never
      // becomes implicit padding and never nudges the row's content.
      foregroundDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: focused ? t.text.withValues(alpha: kSettingsFocusBarAlpha) : Colors.transparent,
            width: kSettingsFocusBarWidth,
          ),
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
    // DENS1: on TV a 44 pt badge around a Body-sized (29 pt) glyph, where the
    // phone's 36/20 came out at 67/37 pt, taller than the text beside it.
    final pt = PlatformDetector.isTV() ? TvHig.of(context) : null;
    final box = pt == null ? 36.0 : 44 * pt;
    return Container(
      width: box,
      height: box,
      decoration: BoxDecoration(
        color: color.withValues(alpha: t.isLight ? 0.08 : 0.12),
        borderRadius: BorderRadius.circular(t.radiusSm),
      ),
      alignment: Alignment.center,
      child: AppIcon(icon, fill: 1, size: pt == null ? 20 : TvHig.body * pt, color: color),
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
