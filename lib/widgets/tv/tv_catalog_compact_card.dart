/// The catalog card of Alle films and Alle series with nothing above the grid
/// (A-06c), opt-in through [TvUnifiedMediaCard.compact].
///
/// Three differences with [TvCatalogCard], all in service of the poster size:
///
/// * **No inset.** The poster is the column, so the ring has to be drawn
///   outside it, in the gutter.
/// * **One title line under a meta line, centred**, in a footer of a fixed
///   height ([TvCatalogFullBleedLayout.footerHeight]).
/// * **Focus scales the poster alone.** [FocusableWrapper] scales its whole
///   child, so it is told not to and the poster scales itself. The footer steps
///   down out of the ring's way, the way a native tvOS lockup moves its label.
///   That shift is paint only, so a focused card lays out exactly like its
///   neighbours and no row moves under the remote.
library;

import 'package:flutter/material.dart';

import '../../focus/focus_theme.dart';
import '../../focus/focusable_wrapper.dart';
import '../../services/settings_service.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import 'tv_catalog_card.dart';
import 'tv_unified_layout.dart';

class TvCatalogCompactCard extends StatefulWidget {
  const TvCatalogCompactCard({
    super.key,
    required this.width,
    required this.artwork,
    required this.title,
    required this.meta,
    required this.onSelect,
    this.topLeftMarker,
    this.topRightMarker,
    this.progressFraction,
    this.onContextMenu,
    this.focusNode,
    this.autofocus = false,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onBack,
    this.onFocusChange,
    this.semanticLabel,
  });

  final double width;
  final Widget artwork;
  final String title;
  final String meta;
  final VoidCallback onSelect;
  final Widget? topLeftMarker;
  final Widget? topRightMarker;
  final double? progressFraction;
  final VoidCallback? onContextMenu;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;
  final VoidCallback? onBack;
  final ValueChanged<bool>? onFocusChange;
  final String? semanticLabel;

  @override
  State<TvCatalogCompactCard> createState() => _TvCatalogCompactCardState();
}

class _TvCatalogCompactCardState extends State<TvCatalogCompactCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final radius = TvCatalogLayout.cardRadius * scale;
    final isFocused = _isFocused;
    final posterHeight = widget.width / TvCatalogLayout.posterAspectRatio;
    final duration = reduceMotion(context, TvCatalogFullBleedLayout.footerFocusDuration);
    final footerShift = TvCatalogFullBleedLayout.focusedFooterShift(posterHeight, scale);

    return SizedBox(
      width: widget.width,
      child: FocusableWrapper(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onSelect: widget.onSelect,
        onLongPress: widget.onContextMenu,
        enableLongPress: widget.onContextMenu != null,
        onFocusChange: (focused) {
          setState(() => _isFocused = focused);
          widget.onFocusChange?.call(focused);
        },
        onNavigateUp: widget.onNavigateUp,
        onNavigateDown: widget.onNavigateDown,
        onNavigateLeft: widget.onNavigateLeft,
        onNavigateRight: widget.onNavigateRight,
        onBack: widget.onBack,
        borderRadius: radius,
        disableScale: true,
        mode: FocusIndicatorMode.delegated,
        semanticLabel: widget.semanticLabel,
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedScale(
                scale: isFocused ? TvCatalogFullBleedLayout.posterFocusScale : 1,
                duration: duration,
                curve: Curves.easeOut,
                child: _Poster(
                  radius: radius,
                  scale: scale,
                  isFocused: isFocused,
                  artwork: widget.artwork,
                  topLeftMarker: widget.topLeftMarker,
                  topRightMarker: widget.topRightMarker,
                  progressFraction: widget.progressFraction,
                ),
              ),
              AnimatedSlide(
                offset: Offset(0, isFocused ? footerShift / (TvCatalogFullBleedLayout.footerHeight * scale) : 0),
                duration: duration,
                curve: Curves.easeOut,
                child: _Footer(title: widget.title, meta: widget.meta, scale: scale, tk: tk),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The poster, its shadow and the ring outside it.
class _Poster extends StatelessWidget {
  const _Poster({
    required this.radius,
    required this.scale,
    required this.isFocused,
    required this.artwork,
    required this.topLeftMarker,
    required this.topRightMarker,
    required this.progressFraction,
  });

  final double radius;
  final double scale;
  final bool isFocused;
  final Widget artwork;
  final Widget? topLeftMarker;
  final Widget? topRightMarker;
  final double? progressFraction;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return AnimatedContainer(
      duration: tk.fast,
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: isFocused ? TvCatalogLayout.cardFocusShadowAlpha : TvCatalogLayout.cardShadowAlpha,
            ),
            blurRadius: (isFocused ? TvCatalogLayout.cardFocusShadowBlur : TvCatalogLayout.cardShadowBlur) * scale,
            offset: Offset(
              0,
              (isFocused ? TvCatalogLayout.cardFocusShadowOffsetY : TvCatalogLayout.cardShadowOffsetY) * scale,
            ),
          ),
        ],
      ),
      // Outside the clip and with its own gap: the card has no inset for a
      // ring to sit in, and a white ring flush against a bright poster reads
      // as no ring at all.
      foregroundDecoration: FocusTheme.shapeFocusRing(
        context,
        isFocused: isFocused,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        gap: TvCatalogFullBleedLayout.ringGap * scale,
      ),
      child: ClipRRect(
        key: tvCatalogPosterKey,
        borderRadius: BorderRadius.circular(radius),
        child: TvCatalogArtworkBox(
          scale: scale,
          isFocused: isFocused,
          artwork: artwork,
          topLeftMarker: topLeftMarker,
          topRightMarker: topRightMarker,
          bottomLeftMarker: null,
          progressFraction: progressFraction,
          aspectRatio: TvCatalogLayout.posterAspectRatio,
          overlay: null,
        ),
      ),
    );
  }
}

/// The title and the line under it, centred under the poster.
///
/// The height never depends on the text: a fixed box is what makes
/// [TvCatalogFullBleedLayout.cardHeight] a promise instead of an estimate, and
/// the row alignment measures on it. With titles switched off (PB-10) the meta
/// line moves up and the box stays.
class _Footer extends StatelessWidget {
  const _Footer({required this.title, required this.meta, required this.scale, required this.tk});

  final String title;
  final String meta;
  final double scale;
  final MonoTokens tk;

  @override
  Widget build(BuildContext context) {
    final showTitle = SettingsService.instanceOrNull?.read(SettingsService.tvShowTitlesUnderPosters) ?? true;
    return SizedBox(
      height: TvCatalogFullBleedLayout.footerHeight * scale,
      child: Padding(
        padding: EdgeInsets.only(top: TvCatalogFullBleedLayout.footerTopGap(scale)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showTitle)
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: TvCatalogLayout.cardTitleFontSize * scale,
                  fontWeight: FontWeight.w500,
                  color: tk.text.withValues(alpha: TvCatalogLayout.inkPrimary),
                  height: TvCatalogFullBleedLayout.titleLineHeight,
                ),
              ),
            Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: TvCatalogLayout.cardMetaFontSize * scale,
                color: tk.text.withValues(alpha: TvCatalogLayout.inkSecondary),
                height: TvCatalogFullBleedLayout.metaLineHeight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
