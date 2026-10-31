import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../focus/focus_theme.dart';
import '../../../focus/focusable_wrapper.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/media_review.dart';
import '../../../media/media_role.dart';
import '../../../media/media_server_client.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/media_image_helper.dart';
import '../../../utils/tv_hig.dart';
import '../../../widgets/optimized_media_image.dart';
import '../../../widgets/tv/tv_catalog_card_grid.dart';
import '../mobile/detail_reviews_section.dart';
import 'tv_detail_layout.dart';

/// Focus, ring and activation for a card that is not a catalog card. The ring
/// goes round [artwork] alone, as on [TvCatalogCard]; [below] stays outside it.
class TvDetailFocusCard extends StatefulWidget {
  const TvDetailFocusCard({
    super.key,
    required this.cell,
    required this.semanticLabel,
    required this.onSelect,
    required this.radius,
    required this.artwork,
    this.below,
    this.onContextMenu,
    this.onFocused,
  });

  final TvCatalogGridCell cell;
  final String semanticLabel;
  final VoidCallback onSelect;
  final double radius;
  final Widget artwork;
  final Widget? below;
  final VoidCallback? onContextMenu;

  /// The focus arrived, on top of what [TvCatalogGridCell.onFocusChange] does.
  final VoidCallback? onFocused;

  @override
  State<TvDetailFocusCard> createState() => _TvDetailFocusCardState();
}

class _TvDetailFocusCardState extends State<TvDetailFocusCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final cell = widget.cell;
    return SizedBox(
      width: cell.width,
      child: FocusableWrapper(
        focusNode: cell.focusNode,
        onSelect: widget.onSelect,
        onLongPress: widget.onContextMenu,
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          cell.onFocusChange(focused);
          if (focused) widget.onFocused?.call();
        },
        onNavigateUp: cell.onNavigateUp,
        onNavigateDown: cell.onNavigateDown,
        onNavigateLeft: cell.onNavigateLeft,
        onNavigateRight: cell.onNavigateRight,
        onBack: cell.onBack,
        borderRadius: widget.radius,
        focusScale: FocusTheme.fullCardFocusScale,
        autoScroll: false,
        mode: FocusIndicatorMode.delegated,
        semanticLabel: widget.semanticLabel,
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                foregroundDecoration: FocusTheme.focusDecoration(
                  context,
                  isFocused: _focused,
                  borderRadius: widget.radius,
                ),
                child: widget.artwork,
              ),
              ?widget.below,
            ],
          ),
        ),
      ),
    );
  }
}

/// Up to two letters from a name, for a person without a photo.
String tvDetailInitials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
  if (words.isEmpty) return '';
  final first = words.first.characters.first;
  return words.length == 1 ? first.toUpperCase() : '$first${words.last.characters.first}'.toUpperCase();
}

/// One person in Cast & Crew: a round portrait, the name, the role.
class TvDetailCastCard extends StatelessWidget {
  const TvDetailCastCard({
    super.key,
    required this.cell,
    required this.role,
    required this.client,
    required this.onSelect,
  });

  final TvCatalogGridCell cell;
  final MediaRole role;
  final MediaServerClient? client;
  final VoidCallback onSelect;

  /// The portrait, the gap under it, and the name and role lines.
  static double height(double pt) => (TvDetailLayout.portraitSize + TvDetailLayout.textGap + footer(pt) / pt) * pt;

  static double footer(double pt) => (TvHig.caption1Leading + TvHig.caption1Leading) * pt;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final pt = TvHig.of(context);
    final size = TvDetailLayout.portraitSize * pt;
    final character = role.role;
    final initials = Center(
      child: Text(
        tvDetailInitials(role.tag),
        style: TextStyle(color: tk.text, fontSize: TvHig.title2 * pt, fontWeight: FontWeight.w500),
      ),
    );
    return TvDetailFocusCard(
      cell: cell,
      semanticLabel: [role.tag, ?character].join(', '),
      onSelect: onSelect,
      radius: size / 2,
      artwork: ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: ColoredBox(
            color: tk.text.withValues(alpha: 0.10),
            child: role.thumbPath == null
                ? initials
                : OptimizedMediaImage(
                    client: client,
                    imagePath: role.thumbPath,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    imageType: ImageType.avatar,
                    errorWidget: (_, _, _) => initials,
                  ),
          ),
        ),
      ),
      below: Padding(
        padding: EdgeInsets.only(top: TvDetailLayout.textGap * pt),
        child: Column(
          children: [
            _centredLine(role.tag, tk.text, TvHig.caption1 * pt, pt),
            if (character != null && character.isNotEmpty)
              _centredLine(character, tk.textMuted, TvHig.caption2 * pt, pt),
          ],
        ),
      ),
    );
  }

  Widget _centredLine(String text, Color color, double size, double pt) => SizedBox(
    height: TvHig.caption1Leading * pt,
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(color: color, fontSize: size),
    ),
  );
}

/// One critic review: source, author, an excerpt. Select opens the full text.
class TvDetailReviewCard extends StatelessWidget {
  const TvDetailReviewCard({super.key, required this.cell, required this.review, required this.onSelect});

  final TvCatalogGridCell cell;
  final MediaReview review;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final pt = TvHig.of(context);
    final radius = TvDetailLayout.reviewCardRadius * pt;
    final icon = detailReviewIconAsset(review.imageUri);
    final source = review.source;
    final hasSource = source != null && source.isNotEmpty;
    return TvDetailFocusCard(
      cell: cell,
      semanticLabel: [?source, review.author, review.text].join(', '),
      onSelect: onSelect,
      radius: radius,
      artwork: Container(
        height: TvDetailLayout.reviewCardHeight * pt,
        padding: EdgeInsets.all(TvDetailLayout.reviewPadding * pt),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.34),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  SvgPicture.asset(icon, height: TvDetailLayout.reviewIconSize * pt),
                  SizedBox(width: 20 * pt),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasSource ? source : review.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: tk.text, fontSize: TvHig.caption1 * pt),
                      ),
                      if (hasSource)
                        Text(
                          review.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: tk.textMuted, fontSize: TvHig.caption2 * pt),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16 * pt),
            Expanded(
              child: Text(
                review.text,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: tk.text, fontSize: TvHig.caption2 * pt, height: 1.22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Alle bekijken" at the end of a row whose hub holds more than it sent, or
/// the same card with another [label].
class TvDetailViewAllCard extends StatelessWidget {
  const TvDetailViewAllCard({super.key, required this.cell, required this.height, required this.onSelect, this.label});

  final TvCatalogGridCell cell;
  final double height;
  final VoidCallback onSelect;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final pt = TvHig.of(context);
    final radius = TvDetailLayout.reviewCardRadius * pt;
    final text = label ?? t.common.viewAll;
    return TvDetailFocusCard(
      cell: cell,
      semanticLabel: text,
      onSelect: onSelect,
      radius: radius,
      artwork: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: tk.text.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(radius)),
        child: Text(
          text,
          style: TextStyle(color: tk.text, fontSize: TvHig.caption1 * pt, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
