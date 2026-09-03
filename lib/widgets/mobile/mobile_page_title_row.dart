/// The large page title on a mobile Series/Films landing, with the optional
/// entry to the complete catalog beside it. iOS Unified 2026 fase 2, mockups
/// `01-series-landing.png` and `02-films-landing.png`.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../theme/mono_tokens.dart';
import '../app_icon.dart';

class MobilePageTitleRow extends StatelessWidget {
  final String title;

  /// "Alle series" / "Alle films". Rendered only when [onViewAll] is set.
  final String viewAllLabel;

  /// Opens the complete catalog.
  ///
  /// Null in fase 2, and then the entry is not drawn at all rather than drawn
  /// dead: the catalog surface the northstar points at is fase 3's
  /// (`UnifiedCatalogProvider` has no UI yet), and a chevron that answers
  /// nothing is worse than one that is not there. Same shape as
  /// `MobileMediaRail.onViewAll`, which fase 1 left unset for the same reason.
  final VoidCallback? onViewAll;

  const MobilePageTitleRow({super.key, required this.title, required this.viewAllLabel, this.onViewAll});

  /// Matches the mockups' ratio against the 20pt rail headings, and lands on
  /// the platform's large-title size.
  static const double titleFontSize = 34;

  @override
  Widget build(BuildContext context) {
    final muted = tokens(context).textMuted;
    return AutomationNode(
      id: AutomationIds.landingTitle,
      role: 'region',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.w700),
              ),
            ),
            if (onViewAll != null)
              TextButton(
                onPressed: onViewAll,
                child: Row(
                  mainAxisSize: .min,
                  children: [
                    Text(
                      viewAllLabel,
                      style: TextStyle(color: muted, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 2),
                    AppIcon(Symbols.chevron_right_rounded, size: 18, color: muted),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
