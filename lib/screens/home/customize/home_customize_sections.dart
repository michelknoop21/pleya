/// The parts of "Home aanpassen" around the list of rows (mockup 44 C, K):
/// section labels, the locked rows, the "Nieuwe rij" tile and Verborgen items.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/media_item.dart';
import '../../../media/media_server_client.dart';
import '../../../theme/mono_tokens.dart';
import '../../../widgets/continue_watching_hidden_items.dart';
import 'home_customize_row_tile.dart';

class HomeCustomizeSectionLabel extends StatelessWidget {
  const HomeCustomizeSectionLabel(this.label, {super.key, this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: tokens(context).textMuted,
      letterSpacing: 1.1,
      fontWeight: FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(
        children: [
          Expanded(child: Text(label.toUpperCase(), style: style)),
          if (trailing != null) Text(trailing!, style: style?.copyWith(letterSpacing: 0, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// Uitgelicht and Verder kijken: shown so "why can I not move the top of my
/// Home" answers itself, and locked (DEC-100 (4)).
class HomeCustomizeFixedRow {
  const HomeCustomizeFixedRow({required this.title, required this.subtitle, required this.posters});

  final String title;
  final String subtitle;
  final List<MediaItem> posters;
}

class HomeCustomizeFixedRows extends StatelessWidget {
  const HomeCustomizeFixedRows({super.key, required this.rows, this.clientFor});

  final List<HomeCustomizeFixedRow> rows;
  final MediaServerClient? Function(String? serverId)? clientFor;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: mono.surface, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: mono.outline),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Symbols.lock_rounded, size: 18, color: mono.textMuted),
                  const SizedBox(width: 10),
                  Opacity(
                    opacity: 0.8,
                    child: HomeRowThumbs(items: rows[i].posters, clientFor: clientFor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rows[i].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(color: mono.textMuted, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          rows[i].subtitle,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: mono.textMuted),
                        ),
                      ],
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: mono.outline),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(
                        t.unifiedCatalog.homeRows.fixed,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: mono.textMuted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class HomeCustomizeNewRowTile extends StatelessWidget {
  const HomeCustomizeNewRowTile({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    return AutomationNode(
      id: AutomationIds.homeCustomizeNew,
      role: 'button',
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onPressed,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: mono.outline),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Symbols.add_rounded),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.unifiedCatalog.homeRows.newRow,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          t.unifiedCatalog.homeRows.newRowSubtitle,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: mono.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The way back for a title hidden from Verder kijken when the row itself is
/// gone, which is exactly when every title in it has been hidden.
class HomeCustomizeHiddenItemsTile extends StatelessWidget {
  const HomeCustomizeHiddenItemsTile({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tokens(context).surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Symbols.visibility_off_rounded),
        title: Text(continueWatchingHiddenLabel(count)),
        subtitle: Text(t.discover.hiddenItemsHint),
        onTap: () => showContinueWatchingHiddenItems(context),
      ),
    );
  }
}
