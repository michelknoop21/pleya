import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../i18n/strings.g.dart';
import '../services/seerr/seerr_constants.dart';
import '../theme/mono_theme.dart';
import '../theme/mono_tokens.dart';
import 'app_icon.dart';

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

    final icon = switch (status) {
      SeerrMediaStatus.pending => Symbols.schedule_rounded,
      SeerrMediaStatus.processing => Symbols.downloading_rounded,
      SeerrMediaStatus.partiallyAvailable => Symbols.hourglass_bottom_rounded,
      SeerrMediaStatus.available => Symbols.check_circle_rounded,
      SeerrMediaStatus.unknown => null,
    };

    // These badges sit on top of poster art, where a 16%-alpha tint disappeared
    // against bright artwork. Solid fill with dark text reads at a glance, and
    // the drop shadow keeps the edge visible on light posters.
    final onBadge = status == SeerrMediaStatus.processing ? tk.text : const Color(0xFF0E0E10);
    final fill = status == SeerrMediaStatus.processing ? tk.surfaceElevated : color;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 10, vertical: compact ? 3 : 5),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
        border: status == SeerrMediaStatus.processing
            ? Border.all(color: tk.outline)
            : Border.all(color: Colors.black.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(0, 1))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            AppIcon(icon, fill: 1, size: compact ? 12 : 14, color: onBadge),
            SizedBox(width: compact ? 4 : 5),
          ],
          // Flexible, not fixed: on a poster card the badge is given the card's
          // width to live in, and a long label ("Deels beschikbaar") has to
          // shorten itself rather than run under the clip at the poster edge.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: onBadge,
                fontSize: compact ? 10.5 : 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
