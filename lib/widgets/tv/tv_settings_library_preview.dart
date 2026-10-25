/// The preview beside the library category of the TV settings page (A-24):
/// three posters from the library and the look they are shown in.
///
/// It asks for nothing. The posters are items Home has already loaded into
/// [DiscoverProvider]; before that, or without a provider at all, the card
/// shows the theme and density line on its own.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../providers/discover_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/tv_hig.dart';
import '../optimized_media_image.dart';
import 'tv_expandable_media_tile.dart' show discoveryPosterPath;
import 'tv_settings_categories.dart' show TvStudioEyebrow;
import 'tv_settings_studio_style.dart';
import 'tv_unified_layout.dart';

/// Up to [count] items with a poster, first seen first, one per poster.
List<MediaItem> pickSettingsPreviewPosters(Iterable<MediaItem> candidates, {int count = 3}) {
  final seen = <String>{};
  final picked = <MediaItem>[];
  for (final item in candidates) {
    final path = discoveryPosterPath(item);
    if (path == null || path.isEmpty || !seen.add(path)) continue;
    picked.add(item);
    if (picked.length == count) break;
  }
  return picked;
}

/// Reads what Home already holds and hands it to [TvSettingsPreviewCard].
class TvSettingsLibraryPreview extends StatelessWidget {
  const TvSettingsLibraryPreview({super.key, required this.title, required this.summary});

  final String title;

  /// The current theme and density, as the appearance row states them.
  final String summary;

  static Iterable<MediaItem> _candidates(DiscoverProvider discover) sync* {
    yield* discover.onDeck;
    for (final hub in discover.hubs) {
      yield* hub.items;
    }
    yield* discover.latestMovies;
  }

  @override
  Widget build(BuildContext context) {
    // Nullable on purpose: a page mounted without Home (a test, a profile
    // that never opened it) simply has no posters to show.
    final discover = context.watch<DiscoverProvider?>();
    final items = discover == null ? const <MediaItem>[] : pickSettingsPreviewPosters(_candidates(discover));
    return TvSettingsPreviewCard(
      title: title,
      summary: summary,
      items: items,
      clientFor: (serverId) => context.read<MultiServerProvider?>()?.serverManager.getClient(ServerId(serverId)),
    );
  }
}

class TvSettingsPreviewCard extends StatelessWidget {
  const TvSettingsPreviewCard({
    super.key,
    required this.title,
    required this.summary,
    required this.items,
    this.clientFor,
  });

  final String title;
  final String summary;
  final List<MediaItem> items;
  final MediaServerClient? Function(String serverId)? clientFor;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final pt = TvHig.of(context);
    final radius = tk.radiusMd;

    return Container(
      padding: EdgeInsets.all(32 * pt),
      decoration: BoxDecoration(
        color: tvStudioPreviewFill(tk),
        borderRadius: BorderRadius.circular(radius * 1.5),
        border: Border.all(color: tvStudioSeparator(tk)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TvStudioEyebrow(title),
          if (items.isNotEmpty) ...[
            SizedBox(height: 12 * pt),
            Row(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) SizedBox(width: 14 * pt),
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(radius),
                        child: ColoredBox(
                          color: tk.text.withValues(alpha: 0.06),
                          child: OptimizedMediaImage.poster(
                            client: items[i].serverId == null ? null : clientFor?.call(items[i].serverId!),
                            imagePath: discoveryPosterPath(items[i]),
                            fit: BoxFit.cover,
                            fadeInDuration: Duration.zero,
                            fallbackIcon: items[i].kind == MediaKind.show
                                ? Symbols.live_tv_rounded
                                : Symbols.movie_rounded,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                // Fewer than three keeps the poster size of three.
                for (var i = items.length; i < 3; i++) ...[SizedBox(width: 14 * pt), const Spacer()],
              ],
            ),
          ],
          SizedBox(height: 24 * pt),
          Text(
            summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
              fontSize: TvHig.caption1 * pt,
              height: TvHig.caption1Leading / TvHig.caption1,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
