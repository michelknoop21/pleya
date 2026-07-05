import 'package:flutter/material.dart';

import '../i18n/strings.g.dart';
import '../services/seerr/seerr_constants.dart';
import '../theme/mono_theme.dart';
import '../theme/mono_tokens.dart';

/// Small pill showing a media's request/availability state on cards and
/// detail screens, tinted with the app's brand palette: amber = pending,
/// muted = processing, green = (partially) available. Renders nothing for
/// unknown status.
class SeerrStatusBadge extends StatelessWidget {
  final SeerrMediaStatus status;
  final bool compact;

  const SeerrStatusBadge({super.key, required this.status, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final (color, label) = switch (status) {
      SeerrMediaStatus.pending => (kAccentAlt, t.seerr.pending),
      SeerrMediaStatus.processing => (tk.textMuted, t.seerr.processing),
      SeerrMediaStatus.partiallyAvailable => (kSuccess, t.seerr.partiallyAvailable),
      SeerrMediaStatus.available => (kSuccess, t.seerr.available),
      SeerrMediaStatus.unknown => (Colors.transparent, ''),
    };
    if (label.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: const BorderRadius.all(Radius.circular(100)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: compact ? 10 : 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
