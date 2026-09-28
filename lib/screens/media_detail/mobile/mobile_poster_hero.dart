import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../media/media_item.dart';
import '../../../media/media_item_types.dart';
import '../../../services/image_cache_service.dart';
import '../../../utils/content_utils.dart';
import '../../../utils/formatters.dart';
import '../../../widgets/placeholder_container.dart';
import 'light_ink_plate.dart';

/// Mockup width the hero sizes below are taken from (D-01, D-03).
const double _kMockupWidth = 402;

/// The top of the iPhone detail page (D-01 film, D-03 series): the portrait
/// poster over the full width, starting under the back/more bar so the title
/// art at the top of the poster stays visible, fading out at the
/// bottom into [DetailAmbientBackground], with the meta line and [scoreRow]
/// over the fade. Without a poster it falls back to [fallbackArtUrl] in 16:9
/// with the title as text (Review Focus 1); with neither, only the text.
class MobilePosterHero extends StatelessWidget {
  const MobilePosterHero({
    super.key,
    required this.item,
    required this.posterUrl,
    required this.fallbackArtUrl,
    required this.scoreRow,
  });

  final MediaItem item;
  final String? posterUrl;
  final String? fallbackArtUrl;
  final Widget scoreRow;

  /// Room above the poster for the status bar and the back/more bar.
  static double topInset(BuildContext context) => MediaQuery.paddingOf(context).top + 60;

  /// Height of the poster hero at [width]. The poster starts under
  /// [topInset] and gives up that room at its bottom, where it fades out
  /// anyway, so the Play button and action row stay on the first screen.
  static double heightFor(double width) => 640 * width / _kMockupWidth;

  @override
  Widget build(BuildContext context) {
    final posterUrl = this.posterUrl;
    return LayoutBuilder(
      builder: (context, constraints) => posterUrl == null
          ? _buildFallback(context)
          : _buildPoster(context, posterUrl, constraints.maxWidth / _kMockupWidth),
    );
  }

  Widget _buildPoster(BuildContext context, String url, double scale) {
    // A series poster stops higher and fades faster (D-03), leaving room for
    // the meta line on the glow.
    final isShow = item.isShow;
    // Text over the fade: white on the dark themes, dark ink on the light
    // one, where the fade ends on a near-white page.
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final ink = theme.colorScheme.onSurface;
    final topInset = MobilePosterHero.topInset(context);
    return SizedBox(
      height: 640 * scale,
      child: Stack(
        children: [
          Positioned(
            top: topInset,
            left: 0,
            right: 0,
            height: (isShow ? 545 : 640) * scale - topInset,
            child: Semantics(
              image: true,
              label: item.displayTitle,
              child: _fade(
                _image(url, const Alignment(0, -1)),
                // A short fade at the top edge too, into the glow under the bar.
                colors: isShow
                    ? const [Colors.transparent, Colors.black, Colors.black, Colors.transparent]
                    : const [Colors.transparent, Colors.black, Colors.black, Color(0x99000000), Colors.transparent],
                stops: isShow ? const [0, 0.06, 0.7, 0.97] : const [0, 0.05, 0.55, 0.78, 1.0],
              ),
            ),
          ),
          // Status bar band and a touch of shade under the meta line, in the
          // page colour on the light theme. The ink there owns its contrast
          // through its own plates; the band only supports it.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: dark
                        ? const [
                            Color(0x8C000000),
                            Colors.transparent,
                            Colors.transparent,
                            Color(0x26000000),
                            Colors.transparent,
                          ]
                        : [
                            theme.scaffoldBackgroundColor.withAlpha(0x8C),
                            Colors.transparent,
                            Colors.transparent,
                            theme.scaffoldBackgroundColor.withAlpha(0x26),
                            Colors.transparent,
                          ],
                    stops: const [0, 0.14, 0.45, 0.8, 1],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 28,
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: ink,
                shadows: dark ? const [Shadow(blurRadius: 8, color: Color(0x80000000))] : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [_buildMeta(context, ink), const SizedBox(height: 24), scoreRow],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallback(BuildContext context) {
    final theme = Theme.of(context);
    final art = fallbackArtUrl;
    return Column(
      children: [
        if (art != null)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _fade(
              _image(art, Alignment.center),
              colors: const [Colors.black, Color(0x99000000), Colors.transparent],
              stops: const [0.55, 0.78, 1.0],
            ),
          )
        else
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

  /// Year · duration or seasons · genres, then the age rating in a frame, on
  /// its own plate in the light theme ([LightInkPlate]).
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
    final dot = Text('·', style: TextStyle(color: color.withValues(alpha: 0.5)));
    final line = Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 9,
      runSpacing: 4,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) dot,
          Text(parts[i], style: TextStyle(color: color, fontSize: 15)),
        ],
        if (rating.isNotEmpty)
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: color.withValues(alpha: 0.6)),
              borderRadius: BorderRadius.circular(5),
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
    return LightInkPlate(child: line);
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
