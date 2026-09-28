import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../media/external_rating.dart';

/// The outside scores under the hero (D-01): icon plus value per source,
/// centred. Not tappable (DEC-140).
class DetailScoreRow extends StatelessWidget {
  const DetailScoreRow({super.key, required this.ratings});

  final List<ExternalRating> ratings;

  @override
  Widget build(BuildContext context) {
    if (ratings.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 8,
      children: [
        for (final r in ratings)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(r.assetPath, height: 18),
              const SizedBox(width: 6),
              Text(r.label, style: const TextStyle(fontSize: 14.5)),
            ],
          ),
      ],
    );
  }
}
