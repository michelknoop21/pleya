/// The leading icon of a settings row, in one of two treatments.
library;

import 'package:flutter/material.dart';

import '../../theme/mono_tokens.dart';
import '../../utils/platform_detector.dart';
import '../../utils/tv_hig.dart';
import '../app_icon.dart';

/// How a settings row draws its leading icon.
///
/// [badge] is the glyph in a tinted rounded square, which gives every row the
/// same optical weight. [line] is the A-24b Studio row (anchor `01`): an
/// outline glyph with no square around it, so a row reads as a title with a
/// small mark rather than as a button. Both take the same width, so titles,
/// separators and value labels line up whichever is drawn. [none] is the
/// Studio subpage row (series `ios/02`-`14`): no icon at all, the title starts
/// at the row inset and so does the separator.
enum SettingsIconStyle { badge, line, none }

/// Sets the [SettingsIconStyle] for the rows below it, and whether the rows
/// show their explanatory line. Without one, rows draw
/// [SettingsIconStyle.badge] with their descriptions.
class SettingsIconStyleScope extends InheritedWidget {
  const SettingsIconStyleScope({super.key, required this.style, this.hideDescriptions = false, required super.child});

  final SettingsIconStyle style;

  /// A-24b Studio rows: a title, the value right and a chevron or switch, no
  /// explanation under the title (series `ios/02`-`14`). The explanation is
  /// still read by VoiceOver as the row's hint, and a disabled row keeps it
  /// on screen, because there it says why ([settingsRowDescription]).
  final bool hideDescriptions;

  static SettingsIconStyle of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsIconStyleScope>()?.style ?? SettingsIconStyle.badge;

  /// Whether rows below [context] leave their description off screen.
  static bool hidesDescriptions(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsIconStyleScope>()?.hideDescriptions ?? false;

  @override
  bool updateShouldNotify(SettingsIconStyleScope oldWidget) =>
      style != oldWidget.style || hideDescriptions != oldWidget.hideDescriptions;
}

/// A [SettingsIconStyleScope] for a subtree that keeps everything from the
/// scope above it except the ones given here.
Widget settingsIconStyleOverride(
  BuildContext context, {
  SettingsIconStyle? style,
  bool? hideDescriptions,
  required Widget child,
}) => SettingsIconStyleScope(
  style: style ?? SettingsIconStyleScope.of(context),
  hideDescriptions: hideDescriptions ?? SettingsIconStyleScope.hidesDescriptions(context),
  child: child,
);

/// The leading slot of a settings row: the badge or line glyph, or null when
/// the scope draws no icon, so the `ListTile` reserves no width for one.
Widget? settingsRowLeading(BuildContext context, IconData icon) =>
    SettingsIconStyleScope.of(context) == SettingsIconStyle.none ? null : SettingsIconBadge(icon);

/// Where a row's text, and so its separator, starts off TV: after the row
/// inset, the icon slot and the title gap, or at the row inset alone when the
/// scope draws no icon.
double settingsRowTextInset(BuildContext context) =>
    SettingsIconStyleScope.of(context) == SettingsIconStyle.none ? 16 : 16 + kSettingsIconBox + 16;

/// What a row shows under its title: [description] unless the scope hides
/// descriptions, in which case only a disabled row keeps it, since there it
/// explains why the row does nothing.
String? settingsRowDescription(BuildContext context, String? description, {bool enabled = true}) {
  if (description == null) return null;
  if (!enabled || !SettingsIconStyleScope.hidesDescriptions(context)) return description;
  return null;
}

/// The hint VoiceOver reads for a row whose description is off screen, so
/// hiding it changes what is drawn and not what is said.
String? settingsRowHint(BuildContext context, String? description, {bool enabled = true}) =>
    settingsRowDescription(context, description, enabled: enabled) == null ? description : null;

/// [child] with [hint] as its VoiceOver hint, or [child] alone without one.
Widget settingsRowWithHint(String? hint, Widget child) => hint == null ? child : Semantics(hint: hint, child: child);

/// Width of the leading icon slot off TV, in either style. The row's title
/// starts after it (`kSettingsSeparatorIndent` = 16 + 36 + 16).
const double kSettingsIconBox = 36;

/// Size of a [SettingsIconStyle.line] glyph off TV.
const double kSettingsLineIconSize = 22;

class SettingsIconBadge extends StatelessWidget {
  final IconData icon;
  final Color? tint;

  /// Overrides the [SettingsIconStyleScope] for this one icon.
  final SettingsIconStyle? style;

  const SettingsIconBadge(this.icon, {super.key, this.tint, this.style});

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final color = tint ?? t.text;
    final resolved = style ?? SettingsIconStyleScope.of(context);
    if (resolved == SettingsIconStyle.none) return const SizedBox.shrink();
    // DENS1: on TV a 44 pt badge around a Body-sized (29 pt) glyph, where the
    // phone's 36/20 came out at 67/37 pt, taller than the text beside it.
    final pt = PlatformDetector.isTV() ? TvHig.of(context) : null;
    final box = pt == null ? kSettingsIconBox : 44 * pt;
    if (resolved == SettingsIconStyle.line) {
      return SizedBox(
        width: box,
        height: box,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppIcon(
            icon,
            fill: 0,
            weight: 300,
            size: pt == null ? kSettingsLineIconSize : TvHig.body * pt,
            color: tint ?? t.text.withValues(alpha: 0.82),
          ),
        ),
      );
    }
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
