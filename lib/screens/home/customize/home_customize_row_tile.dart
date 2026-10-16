/// One line of "Home aanpassen" (mockup 44 C, D, K): a drag handle, three small
/// posters, title with its origin, and an eye or a menu on the right.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:material_symbols_icons/symbols.dart';

import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/media_item.dart';
import '../../../media/media_server_client.dart';
import '../../../providers/home_custom_rows_provider.dart';
import '../../../services/unified_catalog/home_custom_row.dart';
import '../../../services/unified_catalog/home_layout_entries.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/home_custom_row_labels.dart';
import '../../../widgets/optimized_media_image.dart';
import '../../../widgets/tv/tv_expandable_media_tile.dart' show discoveryPosterPath;

/// The second line of a row: where it comes from and what it holds. [note] is
/// the part that is drawn in amber ("leeg").
({String text, String? note}) homeEntrySubtitle(
  HomeLayoutEntry entry, {
  required bool hidden,
  required bool needsTypeContext,
  HomeCustomRow? custom,
  HomeCustomRowsProvider? customRows,
}) {
  final parts = <String>[];
  String? note;
  switch (entry.kind) {
    case HomeLayoutEntryKind.ownRow:
      parts.add(t.unifiedCatalog.homeRows.ownRow);
      if (custom != null) {
        parts.add(entry.mediaType == 'movie' ? t.unifiedCatalog.moviesTitle : t.unifiedCatalog.seriesTitle);
        parts.addAll(homeCustomRowFilterParts(custom));
        final content = customRows?.contentFor(custom.id);
        if (content != null && content.isEmpty) {
          note = t.unifiedCatalog.homeRows.emptyNote;
        } else if (content != null) {
          final count = content.loadedCount;
          parts.add(t.unifiedCatalog.homeRows.titlesCount(count: count));
        }
      }
    case HomeLayoutEntryKind.pleyaRow:
      parts.add(t.unifiedCatalog.homeRows.pleyaRow);
      if (entry.optIn) {
        parts.add(t.unifiedCatalog.homeRows.optInNote);
        parts.add(t.unifiedCatalog.homeRows.onlyPlex);
      }
    case HomeLayoutEntryKind.mergedRow:
      parts.add(t.unifiedCatalog.homeRows.sourcesCount(count: entry.sourceNames.length));
      parts.addAll(entry.sourceNames);
    case HomeLayoutEntryKind.serverRow:
      final media = switch (entry.mediaType) {
        'movie' => t.search.filters.movies,
        'show' || 'season' || 'episode' => t.search.filters.shows,
        _ => null,
      };
      if (needsTypeContext && media != null) parts.add(media);
      if (entry.serverName != null) parts.add(entry.serverName!);
  }
  if (hidden) parts.add(t.unifiedCatalog.homeRows.hiddenNote);
  return (text: parts.join(' · '), note: note);
}

class HomeRowThumbs extends StatelessWidget {
  const HomeRowThumbs({super.key, required this.items, this.clientFor, this.height = 46});

  final List<MediaItem> items;
  final MediaServerClient? Function(String? serverId)? clientFor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final width = height * 2 / 3;
    final overlap = width * 0.45;
    final count = items.isEmpty ? 3 : items.length;
    return SizedBox(
      width: width + overlap * (count - 1),
      height: height,
      child: Stack(
        children: [
          for (var i = 0; i < count; i++)
            Positioned(
              left: overlap * i,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: mono.surfaceElevated,
                    border: Border.all(color: mono.bg, width: 1.5),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: i < items.length
                        ? OptimizedMediaImage.poster(
                            client: clientFor?.call(items[i].serverId),
                            imagePath: discoveryPosterPath(items[i]),
                            width: width,
                            height: height,
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// What the trailing control of a row does.
enum HomeRowMenuAction { edit, toggleHidden, viewAll, remove }

class HomeCustomizeRowTile extends StatelessWidget {
  const HomeCustomizeRowTile({
    super.key,
    required this.entry,
    required this.index,
    required this.total,
    required this.hidden,
    required this.subtitle,
    required this.onToggleHidden,
    required this.onOpenMenu,
    required this.onMoveUp,
    required this.onMoveDown,
    this.selected = false,
    this.showEditButton = false,
    this.onEdit,
    this.dragHandle,
    this.clientFor,
  });

  final HomeLayoutEntry entry;
  final int index;
  final int total;
  final bool hidden;
  final ({String text, String? note}) subtitle;
  final VoidCallback onToggleHidden;
  final VoidCallback onOpenMenu;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final bool selected;
  final bool showEditButton;
  final VoidCallback? onEdit;
  final Widget? dragHandle;
  final MediaServerClient? Function(String? serverId)? clientFor;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final textColor = hidden ? mono.textMuted : mono.text;
    final home = t.unifiedCatalog.homeRows;
    return AutomationNode(
      id: AutomationIds.homeCustomizeRow,
      instance: '$index',
      role: 'list.item',
      state: () => {'title': entry.title, 'hidden': hidden, 'own': entry.isOwn, 'ids': entry.ids},
      child: Semantics(
        container: true,
        label:
            '${entry.title}. ${home.rowPosition(position: index + 1, total: total)}'
            '${hidden ? '. ${home.hiddenNote}' : ''}',
        customSemanticsActions: {
          if (onMoveUp != null) CustomSemanticsAction(label: home.moveUp): onMoveUp!,
          if (onMoveDown != null) CustomSemanticsAction(label: home.moveDown): onMoveDown!,
        },
        child: Material(
          color: selected ? mono.text.withValues(alpha: 0.06) : Colors.transparent,
          child: InkWell(
            onTap: entry.isOwn ? onEdit : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  if (dragHandle != null) dragHandle!,
                  const SizedBox(width: 10),
                  Opacity(
                    opacity: hidden ? 0.5 : 1,
                    child: HomeRowThumbs(items: entry.posters, clientFor: clientFor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(color: textColor, fontWeight: FontWeight.w600),
                        ),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: subtitle.text),
                              if (subtitle.note != null) ...[
                                if (subtitle.text.isNotEmpty) const TextSpan(text: ' · '),
                                TextSpan(
                                  text: subtitle.note,
                                  style: TextStyle(color: mono.accentAlt, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: mono.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (showEditButton && entry.isOwn && onEdit != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: FilledButton.tonalIcon(
                        onPressed: onEdit,
                        icon: const Icon(Symbols.edit_rounded, size: 16),
                        label: Text(home.edit),
                      ),
                    ),
                  if (entry.isOwn)
                    IconButton(
                      tooltip: home.moreActions,
                      icon: const Icon(Symbols.more_horiz_rounded),
                      onPressed: onOpenMenu,
                    )
                  else
                    IconButton(
                      tooltip: hidden ? home.showOnHome : home.hideOnHome,
                      icon: Icon(hidden ? Symbols.visibility_off_rounded : Symbols.visibility_rounded),
                      onPressed: onToggleHidden,
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
