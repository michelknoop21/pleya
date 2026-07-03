import 'package:flutter/material.dart';

import '../i18n/strings.g.dart';
import '../services/seerr/seerr_constants.dart';

/// Small pill showing a media's request/availability state on cards and
/// detail screens. Amber = pending, blue = processing, green = (partially)
/// available. Renders nothing for unknown status.
class SeerrStatusBadge extends StatelessWidget {
  final SeerrMediaStatus status;
  final bool compact;

  const SeerrStatusBadge({super.key, required this.status, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      SeerrMediaStatus.pending => (const Color(0xFFF59E0B), t.seerr.pending),
      SeerrMediaStatus.processing => (const Color(0xFF3B82F6), t.seerr.processing),
      SeerrMediaStatus.partiallyAvailable => (const Color(0xFF22C55E), t.seerr.partiallyAvailable),
      SeerrMediaStatus.available => (const Color(0xFF22C55E), t.seerr.available),
      SeerrMediaStatus.unknown => (Colors.transparent, ''),
    };
    if (label.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: compact ? 10 : 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
