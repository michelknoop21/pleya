import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../focus/focus_theme.dart';
import '../../../media/external_rating.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/tv_hig.dart';
import '../../../widgets/app_icon.dart';
import 'tv_detail_layout.dart';

/// The white play pill. White at rest too: it is the page's primary action, so
/// the focus adds a ring and a lift rather than a colour.
class TvDetailPlayPill extends StatelessWidget {
  const TvDetailPlayPill({
    super.key,
    required this.label,
    required this.icon,
    required this.focused,
    this.progress,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final bool focused;

  /// How far through the title this is, drawn as a ring instead of [icon].
  final double? progress;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final height = TvDetailLayout.actionSize * pt;
    const ink = Color(0xFF101010);
    final fraction = progress;
    return AnimatedScale(
      scale: focused ? FocusTheme.focusScale : 1,
      duration: FocusTheme.getAnimationDuration(context),
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: 24 * pt),
        foregroundDecoration: FocusTheme.focusDecoration(context, isFocused: focused, borderRadius: height / 2),
        decoration: BoxDecoration(
          color: enabled ? Colors.white : Colors.white.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (fraction == null)
              AppIcon(icon, fill: 1, size: TvHig.body * pt, color: ink)
            else
              SizedBox.square(
                dimension: TvDetailLayout.progressRingSize * pt,
                child: CircularProgressIndicator(
                  value: fraction,
                  strokeWidth: 4 * pt,
                  color: ink,
                  backgroundColor: ink.withValues(alpha: 0.18),
                ),
              ),
            SizedBox(width: 16 * pt),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(color: ink, fontSize: TvHig.caption1 * pt, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// How far through a title, in place of the play glyph on a round button. Its
/// ink follows the button: white at rest, dark under the focus.
class TvDetailProgressRing extends StatelessWidget {
  const TvDetailProgressRing({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final ink = IconTheme.of(context).color ?? Colors.white;
    return SizedBox.square(
      dimension: TvDetailLayout.progressRingSize * pt,
      child: CircularProgressIndicator(
        value: value,
        strokeWidth: 4 * pt,
        color: ink,
        backgroundColor: ink.withValues(alpha: 0.18),
      ),
    );
  }
}

/// A round action beside the pill. Tonal at rest and inverted under focus,
/// which is what the page's other tonal buttons do too.
class TvDetailRoundButton extends StatelessWidget {
  const TvDetailRoundButton({super.key, required this.focused, required this.child});

  final bool focused;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tk = tokens(context);
    final size = TvDetailLayout.actionSize * TvHig.of(context);
    return AnimatedScale(
      scale: focused ? FocusTheme.focusScale : 1,
      duration: FocusTheme.getAnimationDuration(context),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: focused ? scheme.inverseSurface : tk.text.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: IconTheme.merge(
          data: IconThemeData(color: focused ? scheme.onInverseSurface : tk.text),
          child: child,
        ),
      ),
    );
  }
}

/// The outside scores, icon plus value per source.
class TvDetailScoreRow extends StatelessWidget {
  const TvDetailScoreRow({super.key, required this.ratings, required this.color});

  final List<ExternalRating> ratings;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    return Wrap(
      spacing: 20 * pt,
      runSpacing: 8 * pt,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final rating in ratings)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(rating.assetPath, height: TvHig.caption2 * pt),
              SizedBox(width: 8 * pt),
              Text(
                rating.label,
                style: TextStyle(color: color, fontSize: TvHig.caption2 * pt, fontWeight: FontWeight.w500),
              ),
            ],
          ),
      ],
    );
  }
}

/// What the file is, on the hero's bottom right: dark labels on any artwork.
class TvDetailTechLabels extends StatelessWidget {
  const TvDetailTechLabels({super.key, required this.labels});

  final List<({IconData? icon, String text})> labels;

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: TvDetailLayout.techLabelGap * pt,
      runSpacing: 8 * pt,
      children: [
        for (final label in labels)
          Container(
            height: TvDetailLayout.techLabelHeight * pt,
            padding: EdgeInsets.symmetric(horizontal: 10 * pt),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(8 * pt),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (label.icon case final icon?) ...[
                  AppIcon(icon, fill: 1, size: TvHig.caption2 * pt, color: Colors.white),
                  SizedBox(width: 6 * pt),
                ],
                Text(
                  label.text,
                  maxLines: 1,
                  style: TextStyle(color: Colors.white, fontSize: TvHig.caption2 * pt, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
