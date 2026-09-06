/// Platform-neutral marker widgets drawn on a [UnifiedMediaGroup] card:
/// the source-count capsule, the watched tick, the resume progress line, and
/// the new-episode dot. Shared by every mobile card in `lib/widgets/mobile/`
/// (iOS Unified 2026 fase 1, `docs/ios-unified-2026-fase1-plan.md` stap 4) —
/// the same markers the tvOS card family draws, ported to touch chrome.
///
/// [WatchedTick] and a new-content marker are drawn by construction as
/// mutually exclusive: a caller shows one or the other from
/// [UnifiedMediaGroup.watchState], never both, because [newBadgeLabel]
/// already returns null for anything with view progress.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../i18n/strings.g.dart';
import '../media/unified/unified_media_group.dart';
import '../theme/mono_theme.dart';

/// How far through this title the group is, as a fraction, or null when
/// there is nothing to draw.
///
/// Read off the *representative* source's item, which the watch-state
/// resolver already chose as the one whose progress speaks for the group —
/// so a film half watched on one server and untouched on another shows one
/// bar, not an average of two runtimes that are not comparable.
double? resumeFractionFor(UnifiedMediaGroup group) {
  if (!group.watchState.hasActiveProgress) return null;
  final item = group.sources
      .firstWhere(
        (s) => s.sourceKey == group.watchState.representativeSourceKey,
        orElse: () => group.representativeSource,
      )
      .item;
  final offset = item.viewOffsetMs;
  final duration = item.durationMs;
  if (offset == null || duration == null || duration <= 0) return null;
  return (offset / duration).clamp(0.0, 1.0);
}

const double _badgeFill = 0.72;
const double _badgeRadius = 6;

/// "N sources" capsule, drawn only when a card's caller checks
/// [UnifiedMediaGroup.hasMultipleSources].
class SourceCountCapsule extends StatelessWidget {
  final int count;

  const SourceCountCapsule({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: _badgeFill),
        borderRadius: BorderRadius.circular(_badgeRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text(
          t.unifiedCatalog.sources(count: count),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          // White rather than the theme ink: this capsule sits on artwork,
          // and the theme ink is near-black over a black capsule in light
          // mode.
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white, height: 1.1),
        ),
      ),
    );
  }
}

/// The watched marker: a dark capsule with a check glyph, legible over any
/// artwork rather than a bare glyph that disappears into a bright poster.
class WatchedTick extends StatelessWidget {
  const WatchedTick({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: _badgeFill),
        shape: BoxShape.circle,
      ),
      child: const Padding(
        padding: EdgeInsets.all(4),
        child: Icon(Symbols.check_rounded, size: 14, color: Colors.white),
      ),
    );
  }
}

/// The resume bar along the artwork's bottom edge: brand red on a dark
/// track, flush with the artwork's own clip.
class ResumeLine extends StatelessWidget {
  final double fraction;

  const ResumeLine({super.key, required this.fraction});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 3,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fraction.clamp(0.0, 1.0),
            child: const ColoredBox(color: kAccent),
          ),
        ],
      ),
    );
  }
}

/// The new-episode marker: a small solid [kAccentAlt] dot — the same amber
/// "new" mark the northstar's landing rows use, distinct from [WatchedTick]
/// rather than a second use of it. A card never shows both: one is only ever
/// drawn where the other is not, since [newBadgeLabel] already returns null
/// for anything with view progress.
class NewEpisodeDot extends StatelessWidget {
  const NewEpisodeDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: kAccentAlt),
    );
  }
}
