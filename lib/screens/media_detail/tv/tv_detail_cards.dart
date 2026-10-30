import 'package:flutter/material.dart';

import '../../../focus/focus_theme.dart';
import '../../../focus/focusable_wrapper.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/media_role.dart';
import '../../../media/media_server_client.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/media_image_helper.dart';
import '../../../utils/tv_hig.dart';
import '../../../widgets/optimized_media_image.dart';
import '../../../widgets/tv/tv_catalog_card_grid.dart';
import 'tv_detail_layout.dart';

/// Focus, ring and activation for a card that is not a catalog card. The ring
/// goes round [artwork] alone, as on [TvCatalogCard]; [below] stays outside it.
class _TvDetailFocusCard extends StatefulWidget {
  const _TvDetailFocusCard({
    required this.cell,
    required this.semanticLabel,
    required this.onSelect,
    required this.radius,
    required this.artwork,
    this.below,
  });

  final TvCatalogGridCell cell;
  final String semanticLabel;
  final VoidCallback onSelect;
  final double radius;
  final Widget artwork;
  final Widget? below;

  @override
  State<_TvDetailFocusCard> createState() => _TvDetailFocusCardState();
}

class _TvDetailFocusCardState extends State<_TvDetailFocusCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final cell = widget.cell;
    return SizedBox(
      width: cell.width,
      child: FocusableWrapper(
        focusNode: cell.focusNode,
        onSelect: widget.onSelect,
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          cell.onFocusChange(focused);
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
    return _TvDetailFocusCard(
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

/// "Alle bekijken" at the end of a row whose hub holds more than it sent.
class TvDetailViewAllCard extends StatelessWidget {
  const TvDetailViewAllCard({super.key, required this.cell, required this.height, required this.onSelect});

  final TvCatalogGridCell cell;
  final double height;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final pt = TvHig.of(context);
    final radius = TvDetailLayout.reviewCardRadius * pt;
    return _TvDetailFocusCard(
      cell: cell,
      semanticLabel: t.common.viewAll,
      onSelect: onSelect,
      radius: radius,
      artwork: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: tk.text.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(radius)),
        child: Text(
          t.common.viewAll,
          style: TextStyle(color: tk.text, fontSize: TvHig.caption1 * pt, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
