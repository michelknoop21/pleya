import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../media/media_item.dart';
import '../media/media_server_client.dart';
import '../media/unified/unified_media_group.dart';
import '../providers/local_library_provider.dart';
import '../providers/multi_server_provider.dart';
import '../services/unified_catalog/unified_artwork_sources.dart';
import '../utils/media_image_helper.dart';
import 'optimized_media_image.dart';

/// Bounded, bidirectional artwork fallback inside an already-proven group.
/// Every path stays paired with its owning server/client and local-cache key.
/// An image failure advances once through the remaining memberships; it never
/// changes the group's representative, playback selection or watch state.
class UnifiedMediaImage extends StatelessWidget {
  const UnifiedMediaImage({
    super.key,
    required this.group,
    required this.pathOf,
    this.clientFor,
    this.width,
    this.height,
    this.imageType = ImageType.poster,
    this.fallbackIcon,
    this.fit = BoxFit.cover,
  });

  final UnifiedMediaGroup group;
  final String? Function(MediaItem) pathOf;
  final MediaServerClient? Function(String)? clientFor;
  final double? width;
  final double? height;
  final ImageType imageType;
  final IconData? fallbackIcon;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final sources = unifiedArtworkSources(group).toList();
    final serverProvider = context.read<MultiServerProvider?>();
    final candidates = [
      for (final source in sources)
        if (pathOf(source.item) case final String path when path.trim().isNotEmpty)
          (
            source: source,
            path: path,
            client: clientFor != null
                ? clientFor!(source.serverId.value)
                : serverProvider?.getClientForServer(source.serverId),
            local: context.select<LocalLibraryProvider?, String?>((p) => p?.posterPath(source.serverId, path)),
          ),
    ];

    Widget render(int index) {
      final candidate = index < candidates.length ? candidates[index] : null;
      if (candidate != null && (candidate.local == null || !File(candidate.local!).existsSync())) {
        try {
          final url = MediaImageHelper.getOptimizedImageUrl(
            client: candidate.client,
            thumbPath: candidate.path,
            maxWidth: width ?? 300,
            maxHeight: height ?? 450,
            devicePixelRatio: 1,
            imageType: imageType,
          );
          if (url.isEmpty) return render(index + 1);
        } catch (_) {
          return render(index + 1);
        }
      }
      return OptimizedMediaImage(
        key: candidate == null
            ? const ValueKey('unified-artwork-exhausted')
            : ValueKey((candidate.source.sourceKey, candidate.path, candidate.client, candidate.local)),
        client: candidate?.client,
        imagePath: candidate?.path,
        localFilePath: candidate?.local,
        width: width,
        height: height,
        fit: fit,
        imageType: imageType,
        fallbackIcon: fallbackIcon,
        blurHash: candidate?.source.item.posterBlurHash,
        errorWidget: candidate == null ? null : (_, _, _) => render(index + 1),
      );
    }

    return render(0);
  }
}
