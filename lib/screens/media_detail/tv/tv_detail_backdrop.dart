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
/// palette, and a blur this heavy leaves nothing of a backdrop but its colours.
/// Same recipe as `tv_hero_artwork.dart`'s poster fill. The reduced tier draws
/// the theme background: a full-screen blur is what an old Apple TV cannot
/// afford.
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
          imageFilter: ImageFilter.blur(sigmaX: 34, sigmaY: 34, tileMode: TileMode.mirror),
          child: OptimizedMediaImage(
            client: client,
            imagePath: path,
            localFilePath: localPath?.call(path),
            width: size.width,
            height: size.height,
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

/// The sharp artwork in the top right of the first screen. It scrolls with the
/// hero and fades into the backdrop towards the text.
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
    // Two fades, because the art ends on two sides: towards the text and at the
    // foot of the hero, where a single diagonal left a hard edge.
    return RepaintBoundary(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0x00000000), Color(0xFF000000)],
          stops: [0, 0.5],
        ).createShader(bounds),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF000000), Color(0x00000000)],
            stops: [0.45, 1],
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
