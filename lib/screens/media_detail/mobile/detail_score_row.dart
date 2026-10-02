import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../i18n/strings.g.dart';
import '../../../media/external_rating.dart';
import 'light_ink_plate.dart';

/// The outside scores under the hero (D-01): icon plus value per source,
/// centred, on its own plate in the light theme. Not tappable (DEC-140).
class DetailScoreRow extends StatelessWidget {
  const DetailScoreRow({super.key, required this.ratings});

  final List<ExternalRating> ratings;

  @override
  Widget build(BuildContext context) {
    if (ratings.isEmpty) return const SizedBox.shrink();
    return LightInkPlate(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 14,
        runSpacing: 8,
        children: [
          for (final r in ratings)
            Semantics(
              label: '${_sourceName(r.source)} ${r.label}',
              excludeSemantics: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(r.assetPath, height: 18),
                  const SizedBox(width: 6),
                  Text(r.label, style: const TextStyle(fontSize: 14.5)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _sourceName(ExternalRatingSource source) => switch (source) {
    ExternalRatingSource.imdb => 'IMDb',
    ExternalRatingSource.tmdb => 'TMDB',
    ExternalRatingSource.rottenTomatoesCritic => t.discover.scoreRtCritics,
    ExternalRatingSource.rottenTomatoesAudience => t.discover.scoreRtAudience,
    ExternalRatingSource.community => t.discover.scoreCommunity,
  };
}
