import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_hub.dart';
import '../../media/unified/unified_media_hub.dart';
import '../../providers/continue_watching_hidden_provider.dart';
import '../../providers/discover_provider.dart';
import '../../providers/home_custom_rows_provider.dart';
import '../../providers/home_extra_rows_provider.dart';
import '../../providers/home_layout_provider.dart';
import '../../providers/tv_home_projection_provider.dart';
import '../../services/unified_catalog/home_row_layout.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/home_custom_row_labels.dart';
import '../../utils/layout_constants.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/continue_watching_hidden_items.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/tv/tv_home_row_assembly.dart';
import '../../widgets/tv/tv_page_surface.dart';
import '../../widgets/tv/tv_unified_layout.dart';

/// One line of the list: a row and every id it answers to in the layout.
class _LayoutRow {
  const _LayoutRow({required this.ids, required this.title, this.type, this.serverName});

  final List<String> ids;
  final String title;
  final String? type;
  final String? serverName;
}

/// Lets the user reorder and hide the home screen rows. The hero and Continue
/// Watching rows are fixed and deliberately absent here.
class HomeLayoutScreen extends StatelessWidget {
  const HomeLayoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<HomeLayoutProvider>();
    final customRowsProvider = context.watch<HomeCustomRowsProvider?>();
    final extraRows = context.watch<HomeExtraRowsProvider?>();
    final hiddenItems = context.watch<ContinueWatchingHiddenProvider?>();

    // The list is the one the Home in front of the viewer draws (DEC-145). The
    // iPhone and the TV draw unified rows, where one row can answer to several
    // layout ids; desktop and iPad still draw one row per backend hub and have
    // no Recent uitgebracht or Nu op tv row to offer.
    final projection = context.watch<TvHomeProjectionProvider?>();
    final List<_LayoutRow> rows;
    if (projection != null && (PlatformDetector.isTV() || PlatformDetector.isPhone(context))) {
      rows = [
        for (final row in tvHomeOrderableRows(
          projection: projection,
          layout: layout,
          customRows: customRowsProvider,
          extraRows: extraRows,
          includeHidden: true,
          includeEmpty: true,
        ))
          _LayoutRow(
            ids: homeLayoutIdsOf(row),
            title: row.title,
            type: switch (row.kind) {
              UnifiedHubKind.movie => 'movie',
              UnifiedHubKind.show || UnifiedHubKind.episode => 'show',
              _ => null,
            },
            serverName: row.isServerSpecific ? row.serverName : null,
          ),
      ];
    } else {
      // ROW1b: rows the viewer defined themselves take part in the same list,
      // in front like DiscoverScreen. `allRows`, not `visibleRows`: a row that
      // has gone empty is still something the viewer must be able to find here
      // and turn back on.
      final own = [
        ...?customRowsProvider?.allRows(titleFor: homeCustomRowLabel),
        for (final row in extraRows?.allRows() ?? const <UnifiedMediaHub>[])
          if (!row.contributingRowIds.contains(homeLiveTvRowId)) row,
      ].map(mediaHubFromCustomRow);
      // One entry per row identity: duplicate identities (several "Because you
      // watched" rows) move and hide as one block.
      final byId = <String, MediaHub>{};
      for (final hub in layout.apply(
        [...own, ...context.watch<DiscoverProvider>().hubs],
        homeRowId,
        dropHidden: false,
      )) {
        byId.putIfAbsent(homeRowId(hub), () => hub);
      }
      rows = [
        for (final entry in byId.entries)
          _LayoutRow(
            ids: [entry.key],
            title: entry.value.title,
            type: entry.value.type,
            serverName: entry.value.serverName,
          ),
      ];
    }
    final ids = [for (final row in rows) row.ids.first];

    // The way back for a title hidden from Verder kijken when the row itself is
    // gone, which is exactly when every title in it has been hidden.
    final hiddenCount = hiddenItems?.count ?? 0;
    // The same surface as a row tile, so on TV it is a tile like the others
    // and takes the focus ring the page already draws.
    Widget? hiddenItemsTile(BuildContext context) {
      if (hiddenCount == 0) return null;
      final isTv = PlatformDetector.isTV();
      return Material(
        type: isTv ? MaterialType.canvas : MaterialType.transparency,
        color: isTv ? tokens(context).text.withValues(alpha: TvMyPleyaLayout.tileFillAlpha) : null,
        borderRadius: isTv
            ? BorderRadius.circular(TvMyPleyaLayout.tileRadius * TvLayoutConstants.scaleOf(context))
            : null,
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: isTv ? null : const Icon(Symbols.visibility_off_rounded),
          title: Text(continueWatchingHiddenLabel(hiddenCount)),
          subtitle: Text(t.discover.hiddenItemsHint),
          onTap: () => showContinueWatchingHiddenItems(context),
        ),
      );
    }

    final isTv = PlatformDetector.isTV();

    if (ids.isEmpty && isTv) {
      return TvPageSurface(
        title: t.settings.homeLayout,
        children: [Text(t.settings.homeLayoutEmpty), ?hiddenItemsTile(context)],
      );
    }
    if (ids.isEmpty) {
      return SettingsPage(
        title: Text(t.settings.homeLayout),
        children: [
          Padding(padding: const EdgeInsets.all(24), child: Text(t.settings.homeLayoutEmpty)),
          ?hiddenItemsTile(context),
        ],
      );
    }

    void move(int from, int to) {
      if (to < 0 || to >= ids.length) return;
      final next = List.of(rows);
      next.insert(to, next.removeAt(from));
      // Every id a row answers to, or a merged row's rank stops matching where
      // the viewer put it.
      layout.setOrder([for (final row in next) ...row.ids]);
    }

    // A remote has no drag gesture, so TV gets focusable move buttons beside
    // the visibility switch. Pointer platforms keep drag-to-reorder.
    Widget buildTile(int index) {
      final id = ids[index];
      final hub = rows[index];
      final hidden = hub.ids.every(layout.isRowHidden);
      final mediaLabel = switch (hub.type) {
        'movie' => t.search.filters.movies,
        'show' || 'season' || 'episode' => t.search.filters.shows,
        _ => null,
      };
      final needsTypeContext =
          hub.serverName != null || rows.any((other) => !identical(other, hub) && other.title == hub.title);
      final contextParts = [
        if (needsTypeContext && mediaLabel != null) mediaLabel,
        if (hub.serverName != null) hub.serverName!,
      ];
      return Material(
        key: ValueKey(id),
        type: isTv ? MaterialType.canvas : MaterialType.transparency,
        color: isTv ? tokens(context).text.withValues(alpha: TvMyPleyaLayout.tileFillAlpha) : null,
        borderRadius: isTv
            ? BorderRadius.circular(TvMyPleyaLayout.tileRadius * TvLayoutConstants.scaleOf(context))
            : null,
        child: ListTile(
          leading: isTv
              ? null
              : ReorderableDragStartListener(index: index, child: const Icon(Symbols.drag_handle_rounded)),
          title: Text(hub.title),
          subtitle: contextParts.isNotEmpty ? Text(contextParts.join(' · ')) : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isTv) ...[
                IconButton(
                  icon: const Icon(Symbols.arrow_upward_rounded),
                  tooltip: t.settings.homeLayoutMoveUp,
                  onPressed: index == 0 ? null : () => move(index, index - 1),
                ),
                IconButton(
                  icon: const Icon(Symbols.arrow_downward_rounded),
                  tooltip: t.settings.homeLayoutMoveDown,
                  onPressed: index == ids.length - 1 ? null : () => move(index, index + 1),
                ),
              ],
              Switch(
                value: !hidden,
                onChanged: (visible) async {
                  for (final rowId in hub.ids) {
                    await layout.setRowHidden(rowId, !visible);
                  }
                },
              ),
            ],
          ),
        ),
      );
    }

    if (isTv) {
      final scale = TvLayoutConstants.scaleOf(context);
      return TvPageSurface(
        title: t.settings.homeLayout,
        automationInstance: 'home_layout',
        children: const [],
        expanded: ListView.builder(
          itemCount: ids.length + (hiddenCount == 0 ? 0 : 1),
          itemBuilder: (context, index) => Padding(
            padding: EdgeInsets.only(bottom: TvMyPleyaLayout.tileGap * scale),
            child: index < ids.length ? buildTile(index) : hiddenItemsTile(context),
          ),
        ),
      );
    }

    return SettingsPage.slivers(
      title: Text(t.settings.homeLayout),
      slivers: [
        SliverReorderableList(
          itemCount: ids.length,
          onReorderItem: (oldIndex, newIndex) => move(oldIndex, newIndex),
          itemBuilder: (context, index) => buildTile(index),
        ),
        SliverToBoxAdapter(child: hiddenItemsTile(context)),
      ],
    );
  }
}
