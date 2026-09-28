import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../i18n/strings.g.dart';
import '../../../media/media_review.dart';
import '../../../widgets/bottom_sheet_header.dart';
import '../../../widgets/overlay_sheet.dart';

/// The Plex critic reviews as a rail of cards (`.rev` in D-01/D-03, DEC-140).
/// A tap opens the full text in the page's [OverlaySheetHost]. iPhone only.
class DetailReviewsSection extends StatelessWidget {
  const DetailReviewsSection({super.key, required this.reviews});

  final List<MediaReview> reviews;

  static const _cardWidth = 300.0;
  static const _cardHeight = 150.0;

  @override
  Widget build(BuildContext context) {
    if (reviews.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: _cardHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: reviews.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) => _ReviewCard(
          key: ValueKey('review-card-$index'),
          review: reviews[index],
          onTap: () => _showReview(context, reviews[index]),
        ),
      ),
    );
  }

  static void _showReview(BuildContext context, MediaReview review) {
    OverlaySheetController.of(context).show<void>(showDragHandle: true, builder: (_) => _ReviewSheet(review: review));
  }
}

/// `rottentomatoes://image.review.fresh` or `.rotten` to the bundled icon;
/// null for anything else.
String? _rtIconAsset(String? imageUri) => switch (imageUri) {
  'rottentomatoes://image.review.fresh' => 'assets/rating_icons/rt_fresh.svg',
  'rottentomatoes://image.review.rotten' => 'assets/rating_icons/rt_rotten.svg',
  _ => null,
};

class _SourceLine extends StatelessWidget {
  const _SourceLine({required this.review});

  final MediaReview review;

  @override
  Widget build(BuildContext context) {
    final icon = _rtIconAsset(review.imageUri);
    final source = review.source;
    if (icon == null && (source == null || source.isEmpty)) return const SizedBox.shrink();
    return Row(
      children: [
        if (icon != null) ...[SvgPicture.asset(icon, height: 14), const SizedBox(width: 6)],
        if (source != null && source.isNotEmpty)
          Flexible(
            child: Text(
              source,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.70)),
            ),
          ),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({super.key, required this.review, required this.onTap});

  final MediaReview review;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    return SizedBox(
      width: DetailReviewsSection._cardWidth,
      height: DetailReviewsSection._cardHeight,
      child: Material(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  review.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                _SourceLine(review: review),
                const SizedBox(height: 8),
                // Line height 1.3 keeps four lines inside the 150 px card.
                Expanded(
                  child: Text(
                    review.text,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewSheet extends StatelessWidget {
  const _ReviewSheet({required this.review});

  final MediaReview review;

  @override
  Widget build(BuildContext context) {
    final link = review.link;
    final uri = link == null || link.isEmpty ? null : Uri.tryParse(link);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BottomSheetHeader(title: review.author, subtitle: review.source),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Text(review.text, style: const TextStyle(fontSize: 15, height: 1.45)),
            ),
          ),
          if (uri != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: OutlinedButton.icon(
                onPressed: () => launchUrl(uri, mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(t.discover.reviewOpenSource),
              ),
            ),
        ],
      ),
    );
  }
}
