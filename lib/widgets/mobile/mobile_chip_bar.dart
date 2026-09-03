/// The Series/Films chip row under the mobile Home header, switching
/// `MobileHomeScreen` between Home, `seriesRails` and `movieRails`. iOS
/// Unified 2026 fase 1, `docs/ios-unified-2026-fase1-plan.md` stap 5.
///
/// Only Series and Films render in fase 1 (H5): Nieuw and Genres have no
/// product contract yet and are not decorative filler.
library;

import 'package:flutter/material.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../utils/haptics.dart';
import '../focusable_filter_chip.dart';

enum MobileHomeChip { home, series, movies }

class MobileChipBar extends StatelessWidget {
  final MobileHomeChip selected;
  final ValueChanged<MobileHomeChip> onSelected;

  const MobileChipBar({super.key, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    void select(MobileHomeChip chip) {
      if (chip == selected) return;
      Haptics.light();
      onSelected(chip);
    }

    return AutomationNode(
      id: AutomationIds.homeChips,
      role: 'filter',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            FocusableFilterChip(
              label: t.unifiedCatalog.seriesTitle,
              selected: selected == MobileHomeChip.series,
              onPressed: () => select(MobileHomeChip.series),
            ),
            const SizedBox(width: 8),
            FocusableFilterChip(
              label: t.unifiedCatalog.moviesTitle,
              selected: selected == MobileHomeChip.movies,
              onPressed: () => select(MobileHomeChip.movies),
            ),
          ],
        ),
      ),
    );
  }
}
