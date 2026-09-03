/// The mobile hero's CTA row: a white "Afspelen"/"Hervatten" pill plus a
/// secondary action. iOS Unified 2026 fase 1,
/// `docs/ios-unified-2026-fase1-plan.md` stap 6.
///
/// Which secondary action ships is DEC-090 §10's other open Home detail
/// (A): `+ Mijn lijst` (the Home comp) versus `Meer info` (the TV contract).
/// [mobileHeroSecondaryActionDefault] is a placeholder, not a decision — see
/// that constant's own doc.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../app_icon.dart';

enum HeroSecondaryAction { moreInfo, addToList }

/// Placeholder default for [HeroSecondaryAction], **not a design decision**.
/// DEC-090 §10 (A) leaves the choice open pending Michel's review; this
/// constant only keeps `MobileHeroCard` compiling and visually reviewable in
/// the meantime.
const HeroSecondaryAction mobileHeroSecondaryActionDefault = HeroSecondaryAction.moreInfo;

class MobileHeroActions extends StatelessWidget {
  final bool hasProgress;
  final int? minutesLeft;
  final HeroSecondaryAction secondary;
  final VoidCallback onPlay;
  final VoidCallback onSecondary;

  const MobileHeroActions({
    super.key,
    required this.hasProgress,
    this.minutesLeft,
    this.secondary = mobileHeroSecondaryActionDefault,
    required this.onPlay,
    required this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final primaryLabel = hasProgress && minutesLeft != null
        ? t.discover.minutesLeft(minutes: minutesLeft!)
        : t.common.play;
    final secondaryLabel = secondary == HeroSecondaryAction.addToList ? t.watchlist.add : t.common.details;
    final secondaryIcon = secondary == HeroSecondaryAction.addToList ? Symbols.add_rounded : Symbols.info_rounded;

    return Row(
      children: [
        AutomationNode(
          id: AutomationIds.discoverHeroPlay,
          role: 'button',
          child: FilledButton.icon(
            onPressed: onPlay,
            icon: const AppIcon(Symbols.play_arrow_rounded, fill: 1, size: 20),
            label: Text(primaryLabel),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: onSecondary,
          icon: AppIcon(secondaryIcon, size: 18, color: Colors.white),
          label: Text(secondaryLabel, style: const TextStyle(color: Colors.white)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white54)),
        ),
      ],
    );
  }
}
