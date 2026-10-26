/// The pieces Mijn Pleya draws the same way on iPhone and Apple TV (A-24b,
/// Editorial): which kijklijst titles the page shows, what a poster opens, and
/// the face of the Big P card. Each platform wraps them in its own input
/// (a tap on iPhone, the remote's focus on TV).
library;

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../i18n/strings.g.dart';
import '../media/ids.dart';
import '../media/media_item.dart';
import '../media/watchlist_entry.dart';
import '../providers/watchlist_provider.dart';
import '../theme/mono_tokens.dart';
import '../utils/media_image_helper.dart';
import '../utils/provider_extensions.dart';
import '../widgets/big_p/big_p_rig.dart' show bigPAsset;
import '../widgets/optimized_media_image.dart';
import '../widgets/pleya_logo.dart';

/// How many kijklijst posters the page shows before "Bekijk alles" takes over.
const int kMyPleyaWatchlistMax = 12;

/// The kijklijst titles Mijn Pleya shows, newest first.
List<WatchlistEntry> myPleyaWatchlistEntries(WatchlistProvider provider) =>
    provider.entriesByRecentlyAdded.take(kMyPleyaWatchlistMax).toList();

/// The server item a poster opens, or null when the title has nothing to play
/// and the poster opens the full kijklijst instead. Availability is not
/// resolved here: that work belongs to the kijklijst itself.
MediaItem? myPleyaWatchlistTarget(WatchlistProvider provider, WatchlistEntry entry) =>
    provider.isPlayable(entry) ? entry.lastKnownMatch : null;

/// A kijklijst poster's picture: the server's poster when the title resolved
/// to something playable ([match]), otherwise the catalogue poster, and a
/// quiet fill when neither exists.
class MyPleyaWatchlistArtwork extends StatelessWidget {
  const MyPleyaWatchlistArtwork({
    super.key,
    required this.entry,
    required this.match,
    required this.width,
    required this.height,
  });

  final WatchlistEntry entry;
  final MediaItem? match;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final match = this.match;
    final placeholder = ColoredBox(color: tokens(context).surfaceElevated);
    if (match != null) {
      return OptimizedMediaImage.poster(
        client: context.tryGetMediaClientWithFallback(serverIdOrNull(match.serverId)),
        imagePath: match.posterThumb(),
        width: width,
        height: height,
        fallbackIcon: Symbols.movie_rounded,
        blurHash: match.posterBlurHash,
      );
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return switch (MediaImageHelper.catalogPosterUrl(
      entry.posterRef,
      width: (width * dpr).round(),
      height: (height * dpr).round(),
    )) {
      '' => placeholder,
      final url => CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, _) => placeholder,
        errorBuilder: (_, _, _) => placeholder,
      ),
    };
  }
}

/// The Big P card's face: brand red, the Pleya mark, title and subtitle, an
/// optional call to action, and Big P himself on the right
/// (`still-zwaaien.png`, byte-identical to the package's `bigp_still.png`).
/// Same in every theme: it is a brand surface, with white ink on red.
///
/// Measured in [unit]s: at 1 it is the iPhone card of northstar 00 (100 high);
/// the TV hub passes its own unit for the 480 x 165 card of northstar 01.
/// [minTextSize] keeps the small lines at or above the TV's legible minimum.
class BigPCardFace extends StatelessWidget {
  const BigPCardFace({
    super.key,
    required this.subtitle,
    this.action,
    this.unit = 1,
    this.minTextSize = 0,
    this.textRightReserve = 110,
  });

  final String subtitle;
  final String? action;
  final double unit;
  final double minTextSize;

  /// Room the text leaves for Big P on the right, in [unit]s.
  final double textRightReserve;

  @override
  Widget build(BuildContext context) {
    final accent = tokens(context).accent;
    final small = (12.5 * unit).clamp(minTextSize, double.infinity);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(accent, const Color(0xFF1A0B10), 0.45)!,
            Color.lerp(accent, const Color(0xFF1A0B10), 0.78)!,
          ],
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 100 * unit),
        child: Stack(
          children: [
            Positioned(
              right: 10 * unit,
              top: 4 * unit,
              bottom: 0,
              child: Image.asset(bigPAsset('still-zwaaien'), fit: BoxFit.contain),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16 * unit, 16 * unit, textRightReserve * unit, 16 * unit),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PleyaLogo(size: 38 * unit),
                  SizedBox(width: 12 * unit),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          t.assistant.tileTitle,
                          maxLines: 1,
                          style: TextStyle(color: Colors.white, fontSize: 21 * unit, fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: 4 * unit),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: small),
                        ),
                        if (action case final action?) ...[
                          SizedBox(height: 4 * unit),
                          Text(
                            action,
                            maxLines: 1,
                            style: TextStyle(color: Colors.white, fontSize: small, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
