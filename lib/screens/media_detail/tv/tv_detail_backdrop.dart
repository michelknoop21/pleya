import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../media/media_item.dart';
import '../../../media/media_server_client.dart';
import '../../../services/device_performance.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/media_image_helper.dart';
import '../../../widgets/optimized_media_image.dart';
import 'tv_detail_layout.dart';

/// The fixed colour layer behind the film detail page.
///
/// The colour comes from the artwork itself: nothing in the app computes a
/// palette, and a blur this heavy leaves nothing of a backdrop but its colours:
/// a soft gradient that runs on behind every row and never moves. The reduced
/// tier draws the theme background: a full-screen blur is what an old Apple TV
/// cannot afford.
class TvDetailBackdrop extends StatelessWidget {
  const TvDetailBackdrop({super.key, required this.item, required this.client, this.localPath});

  final MediaItem item;
  final MediaServerClient? client;

  /// Resolves an artwork path to a downloaded file, on an offline page.
  final String? Function(String? path)? localPath;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final size = MediaQuery.sizeOf(context);
    final paths = item.heroArtCandidates(containerAspectRatio: size.width / size.height);
    final path = paths.isEmpty ? null : paths.first;
    if (path == null || DevicePerformance.isReduced) return ColoredBox(color: tk.bg);

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: tk.bg),
        ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: TvDetailLayout.backdropBlur,
            sigmaY: TvDetailLayout.backdropBlur,
            tileMode: TileMode.mirror,
          ),
          child: OptimizedMediaImage(
            client: client,
            imagePath: path,
            localFilePath: localPath?.call(path),
            width: size.width,
            height: size.height,
            requestSize: TvDetailLayout.backdropDecodeSize,
            fit: BoxFit.cover,
            imageType: ImageType.art,
            fadeInDuration: Duration.zero,
          ),
        ),
        ColoredBox(color: tk.bg.withValues(alpha: TvDetailLayout.scrimAlpha)),
      ],
    );
  }
}

/// A fade along [begin] to [end], from opaque to clear or back, without the
/// corner a straight ramp has at each end: on dark artwork that corner reads as
/// an edge, and a band where the picture stops.
LinearGradient _softFade({
  required Alignment begin,
  required Alignment end,
  required double from,
  required double to,
  required bool rising,
}) {
  const steps = 8;
  final stops = <double>[];
  final colors = <Color>[];
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    final eased = t * t * (3 - 2 * t);
    stops.add(from + (to - from) * t);
    colors.add(const Color(0xFF000000).withValues(alpha: rising ? eased : 1 - eased));
  }
  return LinearGradient(begin: begin, end: end, colors: colors, stops: stops);
}

/// The sharp artwork of the first screen: the whole width, so the picture has
/// no left edge of its own, gone towards the text and towards the rows. It
/// scrolls with the hero and leaves only the [TvDetailBackdrop] behind.
class TvDetailHeroArt extends StatelessWidget {
  const TvDetailHeroArt({super.key, required this.item, required this.client, this.localPath});

  final MediaItem item;
  final MediaServerClient? client;
  final String? Function(String? path)? localPath;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final paths = item.heroArtCandidates(containerAspectRatio: size.width / size.height);
    if (paths.isEmpty) return const SizedBox.shrink();
    return RepaintBoundary(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => _softFade(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          from: 0.3,
          to: 0.72,
          rising: true,
        ).createShader(bounds),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => _softFade(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            from: 0.4,
            to: 0.8,
            rising: false,
          ).createShader(bounds),
          child: OptimizedMediaImage(
            client: client,
            imagePath: paths.first,
            localFilePath: localPath?.call(paths.first),
            fit: BoxFit.cover,
            alignment: Alignment.topRight,
            imageType: ImageType.art,
          ),
        ),
      ),
    );
  }
}
