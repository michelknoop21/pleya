import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_hub.dart';
import '../../providers/discover_provider.dart';
import '../../providers/home_layout_provider.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/settings_page.dart';

/// Lets the user reorder and hide the home screen rows. The hero and Continue
/// Watching rows are fixed and deliberately absent here.
class HomeLayoutScreen extends StatelessWidget {
  const HomeLayoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<HomeLayoutProvider>();
    // One entry per row identity — duplicate identities (several "Because you
    // watched" rows) move and hide as one block.
    final rows = <String, MediaHub>{};
    for (final hub in layout.apply(context.watch<DiscoverProvider>().hubs, homeRowId, dropHidden: false)) {
      rows.putIfAbsent(homeRowId(hub), () => hub);
    }
    final ids = rows.keys.toList();

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

    // A remote has no drag gesture, so the drag handle is unreachable on TV and
    // only the visibility switch can be focused. Swap it for D-pad-operable
    // move buttons there; pointer platforms keep the drag-to-reorder list.
    final isTv = PlatformDetector.isTV();

    Widget buildTile(int index) {
      final id = ids[index];
      final hub = rows[id]!;
      final hidden = layout.isRowHidden(id);
      return Material(
        key: ValueKey(id),
        type: MaterialType.transparency,
        child: ListTile(
          leading: isTv
              ? null
              : ReorderableDragStartListener(index: index, child: const Icon(Symbols.drag_handle_rounded)),
          title: Text(hub.title),
          subtitle: hub.serverName != null ? Text(hub.serverName!) : null,
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

    return SettingsPage.slivers(
      title: Text(t.settings.homeLayout),
      slivers: [
        if (isTv)
          SliverList.builder(itemCount: ids.length, itemBuilder: (context, index) => buildTile(index))
        else
          SliverReorderableList(
            itemCount: ids.length,
            onReorderItem: (oldIndex, newIndex) => move(oldIndex, newIndex),
            itemBuilder: (context, index) => buildTile(index),
          ),
      ],
    );
  }
}
