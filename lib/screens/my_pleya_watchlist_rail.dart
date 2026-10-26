part of 'my_pleya_screen.dart';

/// The kijklijst as bare posters: four fill the phone's width, more scroll
/// sideways (northstar 00 has no captions under them).
///
/// A playable title opens its detail page, the same route its card takes
/// anywhere else; a title with nothing to play opens the full kijklijst.
/// Availability is not resolved here: that work belongs to the full screen.
/// An empty list keeps its heading and "Bekijk alles" and says so in one line.
class _WatchlistRail extends StatelessWidget {
  const _WatchlistRail({required this.provider, required this.onOpenAll});

  final WatchlistProvider provider;
  final VoidCallback onOpenAll;

  static const double _gap = 8;
  static const double _maxPosterWidth = 120;

  @override
  Widget build(BuildContext context) {
    final entries = myPleyaWatchlistEntries(provider);
    final tk = tokens(context);
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(_kMyPleyaInset, 4, _kMyPleyaInset, 4),
        child: Text(t.watchlist.empty, style: TextStyle(color: tk.textMuted, fontSize: 13)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxWidth - 2 * _kMyPleyaInset - 3 * _gap;
        final width = (room / 4).clamp(56.0, _maxPosterWidth);
        final height = width * 1.5;
        return SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: _kMyPleyaInset),
            itemCount: entries.length,
            separatorBuilder: (context, _) => const SizedBox(width: _gap),
            itemBuilder: (context, index) => _WatchlistPoster(
              entry: entries[index],
              match: myPleyaWatchlistTarget(provider, entries[index]),
              width: width,
              height: height,
              onOpenAll: onOpenAll,
            ),
          ),
        );
      },
    );
  }
}

class _WatchlistPoster extends StatelessWidget {
  const _WatchlistPoster({
    required this.entry,
    required this.match,
    required this.width,
    required this.height,
    required this.onOpenAll,
  });

  final WatchlistEntry entry;

  /// What the poster opens; null opens the full kijklijst.
  final MediaItem? match;
  final double width;
  final double height;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    final match = this.match;
    final tk = tokens(context);
    final image = MyPleyaWatchlistArtwork(entry: entry, match: match, width: width, height: height);

    final radius = BorderRadius.circular(8);
    final VoidCallback open = match == null ? onOpenAll : () => unawaited(navigateToMediaItem(context, match));
    return Semantics(
      button: true,
      label: entry.item.title,
      onTap: open,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: open,
        child: Container(
          width: width,
          height: height,
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: tk.outline),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                image,
                if (match != null) WatchedIndicator(item: match),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
