import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/download_artwork_helpers.dart';
import '../services/image_cache_service.dart';
import '../utils/initials_palette.dart';

/// A round avatar for someone Tautulli or Plex told us about, with initials as
/// the fallback.
///
/// The fallback is the normal case on a Plex Media Server, whose `/accounts`
/// returned an empty thumb for every account on the measured server; Tautulli
/// is the source that actually carries avatars.
///
/// Shared by the "Watched by" row and the now-watching surfaces so both draw
/// the same person the same way.
class WatcherAvatar extends StatelessWidget {
  const WatcherAvatar({super.key, required this.displayName, this.thumbUrl, this.size = 30});

  final String displayName;
  final String? thumbUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thumb = thumbUrl;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: thumb != null && thumb.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: thumb,
                // Same rule as ProfileAvatar: hash the token-free URL so a
                // rotating token can never end up in a persistent cache key.
                cacheKey: artworkStorageKey(thumb),
                cacheManager: PlexImageCacheManager.instance,
                fit: BoxFit.cover,
                placeholder: (_, _) => _initials(theme),
                errorBuilder: (_, _, _) => _initials(theme),
              )
            : _initials(theme),
      ),
    );
  }

  Widget _initials(ThemeData theme) => Container(
    color: colorForName(displayName, theme),
    alignment: .center,
    child: Text(
      initialOf(displayName),
      style: TextStyle(color: Colors.white, fontSize: size * 0.42, fontWeight: .w600, height: 1.0),
    ),
  );
}
