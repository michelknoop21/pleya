import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../providers/continue_watching_hidden_provider.dart';
import '../../providers/discover_provider.dart';
import '../../providers/home_custom_rows_provider.dart';
import '../../providers/home_extra_rows_provider.dart';
import '../../providers/home_layout_provider.dart';
import '../../providers/tv_home_projection_provider.dart';
import '../../services/unified_catalog/home_layout_entries.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/continue_watching_hidden_items.dart';
import '../../widgets/tv/tv_page_surface.dart';
import '../../widgets/tv/tv_unified_layout.dart';
import '../home/customize/home_customize_screen.dart';

/// Instellingen > Indeling van Home.
///
/// On iPhone, iPad and Mac this is the same screen as "Home aanpassen" on Home
/// (`HomeCustomizeScreen`, HOME-R1), so there is one place to arrange the rows
/// and one implementation of it. tvOS keeps its own list below, with focusable
/// move buttons beside the visibility switch, and the tvOS panel on Home itself.
class HomeLayoutScreen extends StatelessWidget {
  const HomeLayoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!PlatformDetector.isTV()) return const HomeCustomizeScreen();
    return const _TvHomeLayoutList();
  }
}

class _TvHomeLayoutList extends StatelessWidget {
  const _TvHomeLayoutList();

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<HomeLayoutProvider>();
    final hiddenItems = context.watch<ContinueWatchingHiddenProvider?>();

    // The list is the one the Home in front of the viewer draws (DEC-145): unified
    // rows, where one row can answer to several layout ids.
    final projection = context.watch<TvHomeProjectionProvider?>();
    final rows = homeLayoutEntries(
      layout: layout,
      customRows: context.watch<HomeCustomRowsProvider?>(),
      extraRows: context.watch<HomeExtraRowsProvider?>(),
      projection: projection,
      backendHubs: projection == null ? context.watch<DiscoverProvider>().hubs : const [],
    );

    // The way back for a title hidden from Verder kijken when the row itself is
    // gone, which is exactly when every title in it has been hidden.
    final hiddenCount = hiddenItems?.count ?? 0;
    // The same surface as a row tile, so on TV it is a tile like the others
    // and takes the focus ring the page already draws.
    Widget? hiddenItemsTile(BuildContext context) {
      if (hiddenCount == 0) return null;
      return Material(
        type: MaterialType.canvas,
        color: tokens(context).text.withValues(alpha: TvMyPleyaLayout.tileFillAlpha),
        borderRadius: BorderRadius.circular(TvMyPleyaLayout.tileRadius * TvLayoutConstants.scaleOf(context)),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          title: Text(continueWatchingHiddenLabel(hiddenCount)),
          subtitle: Text(t.discover.hiddenItemsHint),
          onTap: () => showContinueWatchingHiddenItems(context),
        ),
      );
    }

    if (rows.isEmpty) {
      return TvPageSurface(
        title: t.settings.homeLayout,
        children: [Text(t.settings.homeLayoutEmpty), ?hiddenItemsTile(context)],
      );
    }

    // `homeLayoutEntriesAfterMove` and not "every row's ids in the new order":
    // twin hubs that share an id move as one block, and the ids of a row that is
    // not in the list (a server that is offline) keep their place (HOME-R1).
    void move(int from, int to) {
      final next = homeLayoutEntriesAfterMove(rows, from, to - from, previous: layout.order);
      if (next != null) layout.setOrder(next);
    }

    Widget buildTile(int index) {
      final hub = rows[index];
      final hidden = hub.ids.every(layout.isRowHidden);
      final mediaLabel = switch (hub.mediaType) {
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
        type: MaterialType.canvas,
        color: tokens(context).text.withValues(alpha: TvMyPleyaLayout.tileFillAlpha),
        borderRadius: BorderRadius.circular(TvMyPleyaLayout.tileRadius * TvLayoutConstants.scaleOf(context)),
        child: ListTile(
          title: Text(hub.title),
          subtitle: contextParts.isNotEmpty ? Text(contextParts.join(' · ')) : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Symbols.arrow_upward_rounded),
                tooltip: t.settings.homeLayoutMoveUp,
                onPressed: index == 0 ? null : () => move(index, index - 1),
              ),
              IconButton(
                icon: const Icon(Symbols.arrow_downward_rounded),
                tooltip: t.settings.homeLayoutMoveDown,
                onPressed: index == rows.length - 1 ? null : () => move(index, index + 1),
              ),
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

    final scale = TvLayoutConstants.scaleOf(context);
    return TvPageSurface(
      title: t.settings.homeLayout,
      automationInstance: 'home_layout',
      children: const [],
      expanded: ListView.builder(
        itemCount: rows.length + (hiddenCount == 0 ? 0 : 1),
        itemBuilder: (context, index) => Padding(
          padding: EdgeInsets.only(bottom: TvMyPleyaLayout.tileGap * scale),
          child: index < rows.length ? buildTile(index) : hiddenItemsTile(context),
        ),
      ),
    );
  }
}
