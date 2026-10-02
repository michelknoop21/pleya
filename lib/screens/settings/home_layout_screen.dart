import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_hub.dart';
import '../../providers/discover_provider.dart';
import '../../providers/home_custom_rows_provider.dart';
import '../../providers/home_layout_provider.dart';
import '../../services/unified_catalog/home_row_layout.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/home_custom_row_labels.dart';
import '../../utils/layout_constants.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/tv/tv_page_surface.dart';
import '../../widgets/tv/tv_unified_layout.dart';

/// Lets the user reorder and hide the home screen rows. The hero and Continue
/// Watching rows are fixed and deliberately absent here.
class HomeLayoutScreen extends StatelessWidget {
  const HomeLayoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<HomeLayoutProvider>();
    // ROW1b: rows the viewer defined themselves take part in the same list,
    // in front like DiscoverScreen and the TV panel. `allRows`, not
    // `visibleRows` — a row that has gone empty is still something the viewer
    // must be able to find here and turn back on.
    final customRows =
        context.watch<HomeCustomRowsProvider?>()?.allRows(titleFor: homeCustomRowLabel).map(mediaHubFromCustomRow) ??
        const <MediaHub>[];
    // One entry per row identity — duplicate identities (several "Because you
    // watched" rows) move and hide as one block.
    final rows = <String, MediaHub>{};
    for (final hub in layout.apply(
      [...customRows, ...context.watch<DiscoverProvider>().hubs],
      homeRowId,
      dropHidden: false,
    )) {
      rows.putIfAbsent(homeRowId(hub), () => hub);
    }
    final ids = rows.keys.toList();

    final isTv = PlatformDetector.isTV();

    if (ids.isEmpty && isTv) {
      return TvPageSurface(title: t.settings.homeLayout, children: [Text(t.settings.homeLayoutEmpty)]);
    }
    if (ids.isEmpty) {
      return SettingsPage(
        title: Text(t.settings.homeLayout),
        children: [Padding(padding: const EdgeInsets.all(24), child: Text(t.settings.homeLayoutEmpty))],
      );
    }

    void move(int from, int to) {
      if (to < 0 || to >= ids.length) return;
      final next = List.of(ids);
      next.insert(to, next.removeAt(from));
      layout.setOrder(next);
    }

    // A remote has no drag gesture, so TV gets focusable move buttons beside
    // the visibility switch. Pointer platforms keep drag-to-reorder.
    Widget buildTile(int index) {
      final id = ids[index];
      final hub = rows[id]!;
      final hidden = layout.isRowHidden(id);
      final mediaLabel = switch (hub.type) {
        'movie' => t.search.filters.movies,
        'show' || 'season' || 'episode' => t.search.filters.shows,
        _ => null,
      };
      final needsTypeContext =
          hub.serverName != null || rows.values.any((other) => !identical(other, hub) && other.title == hub.title);
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
              Switch(value: !hidden, onChanged: (visible) => layout.setRowHidden(id, !visible)),
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
          itemCount: ids.length,
          itemBuilder: (context, index) => Padding(
            padding: EdgeInsets.only(bottom: TvMyPleyaLayout.tileGap * scale),
            child: buildTile(index),
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
      ],
    );
  }
}
