/// What the catalog is currently narrowed to, as a row of quiet tags
/// (CAT5 / [DEC-093](../../../docs/DECISIONS.md#dec-093)).
///
/// One statement, drawn in two places: beside the page heading while the rail
/// is closed, and inside the rail while it is open. Michel's requirement when
/// he chose the rail was that the selection stay visible in the grid: "moet
/// wel subtiel zichtbaar zijn in de bibliotheek wat je als filter gekozen
/// hebt", and a rail that hides itself would otherwise take the answer with
/// it. The two copies share this file so they cannot drift into two different
/// vocabularies for the same selection.
///
/// **Tags are not operable, deliberately.** They moved to the top right
/// precisely because that corner no longer has to be reachable: everything
/// that changes the selection lives in the rail. That is also why the heading
/// caps them instead of scrolling, because a row nobody can move through has no way
/// to reveal what scrolled off.
library;

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../services/unified_catalog/unified_catalog_filters.dart';
import '../../theme/mono_tokens.dart';
import 'tv_catalog_sort_panel.dart';
import 'tv_unified_layout.dart';

/// One tag: a label, and whether it reads as a filter or as the sort.
class TvCatalogSelectionTag {
  const TvCatalogSelectionTag(this.label, {this.muted = false});

  final String label;

  /// Drawn with a dashed outline. The sort is always set, because there is no such
  /// thing as an unsorted catalog, so a solid tag would claim the viewer
  /// narrowed something they did not. Mockup 28 D1 stipples it for exactly
  /// that reason.
  final bool muted;

  @override
  bool operator ==(Object other) => other is TvCatalogSelectionTag && other.label == label && other.muted == muted;

  @override
  int get hashCode => Object.hash(label, muted);

  @override
  String toString() => 'TvCatalogSelectionTag($label${muted ? ', muted' : ''})';
}

/// The selection as tags, filters first and the sort last.
///
/// [sourcesLabel] is the page's own phrasing of a source restriction ("3
/// sources"), or null when every source takes part; the screen owns that string
/// because only it knows how many libraries actually participated.
///
/// [overflowAfter] caps the number of *filter* tags and replaces the rest with
/// a single `+N`. Null means no cap, which is what the rail panel wants: it
/// wraps, so it can show everything.
List<TvCatalogSelectionTag> tvCatalogSelectionTags({
  required UnifiedCatalogFilterSelection filters,
  required UnifiedCatalogSort sort,
  String? sourcesLabel,
  int? overflowAfter = TvCatalogLayout.tagOverflowThreshold,
}) {
  final tags = <TvCatalogSelectionTag>[
    if (filters.watchState != UnifiedWatchFilter.all) TvCatalogSelectionTag(t.unifiedCatalog.filters.unwatched),
    // Sorted, so the same selection always produces the same row: the sets
    // behind these are unordered, and an order that changed between builds
    // would make a golden and a screenshot disagree for no reason.
    for (final genre in filters.genres.toList()..sort()) TvCatalogSelectionTag(genre),
    for (final year in filters.years.toList()..sort()) TvCatalogSelectionTag('$year'),
    if (sourcesLabel != null) TvCatalogSelectionTag(sourcesLabel),
  ];

  final capped = overflowAfter != null && tags.length > overflowAfter
      ? [...tags.take(overflowAfter), TvCatalogSelectionTag('+${tags.length - overflowAfter}')]
      : tags;

  return [...capped, TvCatalogSelectionTag(sortLabel(sort), muted: true)];
}

/// Draws [tags] on one line, or wrapped over several.
class TvCatalogSelectionTagStrip extends StatelessWidget {
  const TvCatalogSelectionTagStrip({super.key, required this.tags, required this.scale, this.wrap = false});

  final List<TvCatalogSelectionTag> tags;
  final double scale;

  /// The rail panel wraps; the heading keeps its single line.
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final gap = TvCatalogLayout.tagGap * scale;
    final children = [for (final tag in tags) _Tag(tag: tag, scale: scale)];
    if (wrap) return Wrap(spacing: gap, runSpacing: gap, children: children);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(width: gap), children[i]],
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.tag, required this.scale});

  final TvCatalogSelectionTag tag;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final ink = tk.text.withValues(
      alpha: tag.muted ? TvCatalogLayout.inkSecondary * 0.8 : TvCatalogLayout.inkSecondary,
    );

    return CustomPaint(
      painter: _TagOutlinePainter(
        color: tk.text.withValues(alpha: TvCatalogLayout.tagOutline),
        radius: TvCatalogLayout.tagRadius * scale,
        dashed: tag.muted,
        scale: scale,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: TvCatalogLayout.tagPaddingHorizontal * scale),
        child: SizedBox(
          height: TvCatalogLayout.tagHeight * scale,
          // `Align` with a width factor rather than `Center`: in the heading the
          // tags sit in a `Row` that hands them unbounded width, but in the rail
          // they sit in a `Wrap` inside a stretched `Column`, and there a
          // centring box takes the whole panel width, and every tag became a
          // full-width bar with its label in the middle.
          child: Align(
            alignment: Alignment.center,
            widthFactor: 1,
            child: Text(
              tag.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: TvCatalogLayout.tagFontSize * scale,
                fontWeight: FontWeight.w500,
                color: ink,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tag's outline, solid or dashed.
///
/// Painted rather than expressed as a `Border`, because Flutter's box borders
/// have no dash: the stipple is what separates the sort from the filters, and
/// approximating it with a fainter solid line loses the distinction at three
/// metres: a paler outline reads as a quieter filter, not as a different kind
/// of thing.
class _TagOutlinePainter extends CustomPainter {
  const _TagOutlinePainter({required this.color, required this.radius, required this.dashed, required this.scale});

  final Color color;
  final double radius;
  final bool dashed;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      Radius.circular(radius),
    );
    if (!dashed) {
      canvas.drawRRect(rect, stroke);
      return;
    }
    final dash = 3.0 * scale;
    final gap = 2.5 * scale;
    for (final metric in (Path()..addRRect(rect)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), stroke);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_TagOutlinePainter old) =>
      old.color != color || old.radius != radius || old.dashed != dashed || old.scale != scale;
}
