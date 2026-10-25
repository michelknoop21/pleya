/// The small pieces of the TV settings layout (A-24): the accent eyebrow, the
/// large category heading, and the category pill on the rail. Split from
/// `tv_settings_categories.dart`, which keeps the layout and the focus walk.
library;

import 'package:flutter/material.dart';

import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../utils/tv_hig.dart';
import '../app_icon.dart';
import 'tv_settings_studio_style.dart';
import 'tv_unified_layout.dart';

/// VIS-0926-S1 (DEC-139), in HIG points. VIS-0925-G packed the rail to a
/// 12 pt pill inset with 8 pt between pills, which read as one stack on the
/// 77 inch set; 18 and 16 make it a list.
const double kTvCategoryPillInsetPt = 18;

/// The category name over the rows, in the Studio accent ink.
class TvStudioEyebrow extends StatelessWidget {
  const TvStudioEyebrow(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: TvMyPleyaLayout.groupLabelGap * scale),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: tvStudioEyebrow(tokens(context)),
          fontSize: TvMyPleyaLayout.groupLabelFontSize * scale,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

/// A-24b, anchor `02`: the large line under the eyebrow ("Zo ziet jouw Pleya
/// eruit"), HIG Title 3.
class TvStudioHeading extends StatelessWidget {
  const TvStudioHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 20 * pt),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: tokens(context).text,
          fontSize: TvHig.title3 * pt,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          height: 1.15,
        ),
      ),
    );
  }
}

/// A-24: one rule for chosen versus focused on the category rail.
///
/// Chosen is a secondary mark, never a focus: a brand-red bar on the leading
/// edge over the warm Studio fill, with the label in full ink and bold. Focus
/// is the ring from `FocusableWrapper` and nothing else, so with the remote in
/// the rows the rail shows the chosen category and no ring at all. A-24b: the
/// category's line glyph before the label, as anchor `02` draws it.
class TvStudioCategoryPill extends StatelessWidget {
  const TvStudioCategoryPill({
    super.key,
    required this.title,
    required this.selected,
    required this.focused,
    required this.pt,
    this.icon,
  });

  /// Finds the bar in a test.
  static const Key markerKey = Key('tv-studio-category-marker');

  final String title;
  final IconData? icon;
  final bool selected;
  final bool focused;
  final double pt;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final ink = tvStudioCategoryLabel(tk, selected: selected, focused: focused);
    final glyph = icon;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tvStudioCategoryFill(tk, selected: selected, focused: focused),
        borderRadius: BorderRadius.circular(tk.radiusMd),
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24 * pt, vertical: kTvCategoryPillInsetPt * pt),
            child: Row(
              children: [
                if (glyph != null) ...[
                  AppIcon(glyph, fill: 0, weight: 300, size: TvHig.body * pt, color: ink),
                  SizedBox(width: 20 * pt),
                ],
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink,
                      fontSize: TvHig.body * pt,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (selected)
            PositionedDirectional(
              key: markerKey,
              start: 0,
              top: 0,
              bottom: 0,
              width: kTvStudioMarkerWidthPt * pt,
              child: ColoredBox(color: tvStudioMarkerColor(tk)),
            ),
        ],
      ),
    );
  }
}
