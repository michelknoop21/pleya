import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../media/media_item.dart';
import '../../../media/media_item_types.dart';
import '../../../services/image_cache_service.dart';
import '../../../utils/content_utils.dart';
import '../../../utils/formatters.dart';
import '../../../widgets/placeholder_container.dart';
import 'detail_dark_style.dart';

/// Mockup width the hero sizes below are taken from (D-01, D-03).
const double _kMockupWidth = 402;

/// The top of the iPhone detail page (D-01 film, D-03 series), laid out the
/// way Plex does it: textless art ([artUrl], see [textlessArtPath]) over the
/// full width from the very top, under the status bar and the back/more bar,
/// fading out into [DetailAmbientBackground]. The app draws the title over
/// the bottom of the art: the clear logo ([logoUrl]) centred, or the title as
/// bold text without one. The meta line and [scoreRow] follow, white on the
/// always-dark page (Plex look, variant B).
///
/// Without textless art it falls back to the portrait poster, which carries
/// its own title: that also runs from the very top, under the status bar and
/// the back/more buttons, and gets no logo or text title on top. With
/// neither, only the text.
class MobilePosterHero extends StatelessWidget {
  const MobilePosterHero({
    super.key,
    required this.item,
    required this.artUrl,
    required this.posterUrl,
    required this.logoUrl,
    required this.scoreRow,
  });

  final MediaItem item;

  /// Textless art for the hero, from [textlessArtPath].
  final String? artUrl;

  /// The portrait poster, only used when there is no [artUrl].
  final String? posterUrl;

  /// The item's clear logo, drawn over [artUrl].
  final String? logoUrl;
  final Widget scoreRow;

  /// The textless art for the hero: square art first, then the 16:9 backdrop
  /// cropped to the hero box, never the poster (it has the title baked in).
  /// The fill order of [MediaItem.heroArtCandidates] on a narrow box.
  static String? textlessArtPath(MediaItem item) =>
      item.heroArtCandidates(containerAspectRatio: _kMockupWidth / 640).firstOrNull;

  /// Room above the poster for the status bar and the back/more bar.
  static double topInset(BuildContext context) => MediaQuery.paddingOf(context).top + 60;

  /// Height of the poster hero at [width], so the Play button and action row
  /// stay on the first screen.
  static double heightFor(double width) => 640 * width / _kMockupWidth;

  @override
  Widget build(BuildContext context) {
    final artUrl = this.artUrl;
    final posterUrl = this.posterUrl;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (artUrl != null) return _buildArt(context, artUrl, width);
        if (posterUrl != null) return _buildPoster(context, posterUrl, width / _kMockupWidth);
        return _buildFallback(context);
      },
    );
  }

  Widget _buildArt(BuildContext context, String url, double width) {
    final scale = width / _kMockupWidth;
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    return SizedBox(
      height: 640 * scale,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 520 * scale,
            child: _fade(
              _image(url, Alignment.topCenter),
              colors: const [Colors.black, Colors.black, Color(0x99000000), Colors.transparent],
              stops: const [0, 0.6, 0.82, 1],
            ),
          ),
          _statusBand(),
          Positioned(
            left: 16,
            right: 16,
            bottom: 28,
            child: _foreground(
              context,
              ink,
              title: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildLogoOrTitle(context, ink, maxWidth: width * 0.85, maxHeight: 110 * scale),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The clear logo, or the title as bold white text when there is none or
  /// it fails to load.
  Widget _buildLogoOrTitle(BuildContext context, Color ink, {required double maxWidth, required double maxHeight}) {
    final title = Text(
      item.displayTitle,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: ink, fontWeight: FontWeight.bold),
    );
    final logoUrl = this.logoUrl;
    if (logoUrl == null) return title;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
      child: Image(
        image: CachedNetworkImageProvider(logoUrl, cacheManager: PlexImageCacheManager.instance),
        semanticLabel: item.displayTitle,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => title,
      ),
    );
  }

  Widget _buildPoster(BuildContext context, String url, double scale) {
    // A series poster stops higher and fades faster (D-03), leaving room for
    // the meta line on the glow.
    final isShow = item.isShow;
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    return SizedBox(
      height: 640 * scale,
      child: Stack(
        children: [
          // Variant B: the poster fills the screen from the very top, under
          // the status bar and the back/more buttons.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: (isShow ? 545 : 640) * scale,
            child: Semantics(
              image: true,
              label: item.displayTitle,
              child: _fade(
                _image(url, const Alignment(0, -1)),
                colors: isShow
                    ? const [Colors.black, Colors.black, Colors.transparent]
                    : const [Colors.black, Colors.black, Color(0x99000000), Colors.transparent],
                stops: isShow ? const [0, 0.7, 0.97] : const [0, 0.55, 0.78, 1.0],
              ),
            ),
          ),
          _statusBand(),
          Positioned(left: 16, right: 16, bottom: 28, child: _foreground(context, ink)),
        ],
      ),
    );
  }

  /// Status bar band and a touch of shade under the meta line. The page is
  /// always dark, so the band is always black.
  static Widget _statusBand() {
    return const Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x8C000000),
                Colors.transparent,
                Colors.transparent,
                Color(0x26000000),
                Colors.transparent,
              ],
              stops: [0, 0.14, 0.45, 0.8, 1],
            ),
          ),
        ),
      ),
    );
  }

  /// [title] (if any), the meta line and [scoreRow] over the fade, white with
  /// a soft shadow.
  Widget _foreground(BuildContext context, Color ink, {Widget? title}) {
    return DefaultTextStyle.merge(
      style: TextStyle(
        color: ink,
        shadows: const [Shadow(blurRadius: 8, color: Color(0x80000000))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [?title, _buildMeta(context, ink), const SizedBox(height: 14), scoreRow],
      ),
    );
  }

  Widget _buildFallback(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // Room for the back/more bar over the status bar.
        SizedBox(height: MobilePosterHero.topInset(context)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            children: [
              Text(
                item.displayTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildMeta(context, theme.colorScheme.onSurface),
              const SizedBox(height: 16),
              scoreRow,
            ],
          ),
        ),
      ],
    );
  }

  /// Year, duration or seasons, genres, then the age rating in a dark framed
  /// badge, centred and without separators, the way Plex sets it.
  Widget _buildMeta(BuildContext context, Color color) {
    final seasons = item.isShow ? item.childCount : null;
    final genres = item.genres ?? const <String>[];
    final parts = [
      if (item.year != null) '${item.year}',
      if (!item.isShow && item.durationMs != null) formatDurationTextual(item.durationMs!),
      if (seasons != null && seasons > 0)
        seasons == 1 ? t.unifiedCatalog.oneSeason : t.unifiedCatalog.seasons(count: seasons),
      if (genres.isNotEmpty) genres.take(2).join(', '),
    ];
    final rating = item.contentRating == null ? '' : formatContentRating(item.contentRating);
    if (parts.isEmpty && rating.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final part in parts) Text(part, style: TextStyle(color: color, fontSize: 15)),
        if (rating.isNotEmpty)
          DecoratedBox(
            decoration: BoxDecoration(
              color: kDetailPillColor,
              border: Border.all(color: color.withValues(alpha: 0.6)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              child: Text(
                rating,
                style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }

  static Widget _fade(Widget child, {required List<Color> colors, required List<double> stops}) => ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: (bounds) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: colors,
      stops: stops,
    ).createShader(bounds),
    child: child,
  );

  static Widget _image(String url, Alignment alignment) => CachedNetworkImage(
    imageUrl: url,
    cacheManager: PlexImageCacheManager.instance,
    fit: BoxFit.cover,
    alignment: alignment,
    placeholder: (context, url) => const PlaceholderContainer(),
    errorBuilder: (context, error, stackTrace) => const PlaceholderContainer(),
  );
}
