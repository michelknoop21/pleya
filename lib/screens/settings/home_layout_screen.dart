import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_hub.dart';
import '../../providers/discover_provider.dart';
import '../../providers/home_layout_provider.dart';
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

    return SettingsPage.slivers(
      title: Text(t.settings.homeLayout),
      slivers: [
        SliverReorderableList(
          itemCount: ids.length,
          onReorderItem: (oldIndex, newIndex) {
            final next = List.of(ids);
            next.insert(newIndex, next.removeAt(oldIndex));
            layout.setOrder(next);
          },
          itemBuilder: (context, index) {
            final id = ids[index];
            final hub = rows[id]!;
            final hidden = layout.isRowHidden(id);
            return Material(
              key: ValueKey(id),
              type: MaterialType.transparency,
              child: ListTile(
                leading: ReorderableDragStartListener(index: index, child: const Icon(Symbols.drag_handle_rounded)),
                title: Text(hub.title),
                subtitle: hub.serverName != null ? Text(hub.serverName!) : null,
                trailing: Switch(value: !hidden, onChanged: (visible) => layout.setRowHidden(id, !visible)),
              ),
            );
          },
        ),
      ],
    );
  }
}
