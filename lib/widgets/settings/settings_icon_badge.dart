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
/// separators and value labels line up whichever is drawn.
enum SettingsIconStyle { badge, line }

/// Sets the [SettingsIconStyle] for the rows below it. Without one, rows draw
/// [SettingsIconStyle.badge].
class SettingsIconStyleScope extends InheritedWidget {
  const SettingsIconStyleScope({super.key, required this.style, required super.child});

  final SettingsIconStyle style;

  static SettingsIconStyle of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsIconStyleScope>()?.style ?? SettingsIconStyle.badge;

  @override
  bool updateShouldNotify(SettingsIconStyleScope oldWidget) => style != oldWidget.style;
}

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
    // DENS1: on TV a 44 pt badge around a Body-sized (29 pt) glyph, where the
    // phone's 36/20 came out at 67/37 pt, taller than the text beside it.
    final pt = PlatformDetector.isTV() ? TvHig.of(context) : null;
    final box = pt == null ? kSettingsIconBox : 44 * pt;
    if ((style ?? SettingsIconStyleScope.of(context)) == SettingsIconStyle.line) {
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
