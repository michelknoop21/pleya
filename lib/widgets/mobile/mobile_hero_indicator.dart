/// The mobile hero carousel's position indicator. iOS Unified 2026 fase 1,
/// `docs/ios-unified-2026-fase1-plan.md` stap 6.
///
/// Which style ships is one of DEC-090 §10's two open Home details (B):
/// permanent dots, matching the comp, versus a transient segment indicator
/// that only shows during an advance, per hoofdstuk 9.6 of the tvOS
/// northstar report. [mobileHeroIndicatorStyleDefault] is a placeholder so
/// the seam exists in code, not a decision — see that constant's own doc.
library;

import 'package:flutter/material.dart';

import '../../theme/mono_tokens.dart';

enum HeroIndicatorStyle {
  /// A fixed row of dots, one per slide, the selected one wider — the
  /// Home-comp's own treatment.
  persistentDots,

  /// Dots that only draw while an advance is in flight, then fade out —
  /// hoofdstuk 9.6 of the tvOS northstar report.
  transientSegment,
}

/// Placeholder default for [HeroIndicatorStyle], **not a design decision**.
/// DEC-090 §10 (B) leaves the choice between [HeroIndicatorStyle.persistentDots]
/// and [HeroIndicatorStyle.transientSegment] open pending Michel's review;
/// this constant only keeps `MobileHeroCard` compiling and visually
/// reviewable in the meantime.
const HeroIndicatorStyle mobileHeroIndicatorStyleDefault = HeroIndicatorStyle.persistentDots;

class MobileHeroIndicator extends StatelessWidget {
  final int count;
  final int selectedIndex;
  final HeroIndicatorStyle style;

  /// Only meaningful for [HeroIndicatorStyle.transientSegment]: true while an
  /// advance is animating, so the dots can stay hidden the rest of the time.
  final bool isAdvancing;

  const MobileHeroIndicator({
    super.key,
    required this.count,
    required this.selectedIndex,
    this.style = mobileHeroIndicatorStyleDefault,
    this.isAdvancing = false,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox.shrink();
    final visible = style == HeroIndicatorStyle.persistentDots || isAdvancing;

    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: reduceMotion(context, tokens(context).fast),
      child: Row(
        mainAxisSize: .min,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            AnimatedContainer(
              duration: reduceMotion(context, tokens(context).fast),
              width: i == selectedIndex ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: i == selectedIndex ? 0.95 : 0.5),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
