/// The long-press menu of the iPhone library look (Michel, 30 October 2026,
/// reference 8c2d7495): the rows `media_context_menu.dart` built, in the order of
/// the reference and on the floating sheet of the filter and sort menus.
///
/// **Presentation only.** What a row may offer stays with the menu; here it only
/// gets a place. Beheren and Meer manieren om te kijken are two rows that open
/// their own list, so a row the reference has no place for stays one tap further,
/// and one this file has never heard of lands above Delen rather than nowhere.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../theme/mono_tokens.dart';
import '../media_menu_action.dart';
import '../overlay_sheet.dart';
import '../overlay_sheet_geometry.dart';
import 'library_phone_look.dart';
import 'library_phone_sheet.dart';

/// Top of the sheet down to Beheren.
const List<String> _aboveManage = [
  'play_item',
  'play',
  'watchlist_toggle',
  'add_to',
  'rate',
  'watch',
  'unwatch',
  'remove_from_continue_watching',
  'download',
  'download_collection',
  'download_playlist',
  'manage_sync',
  'remove_sync',
  'delete_download',
];

/// What Beheren holds: changes to the server's own data.
const List<String> _manage = ['edit_metadata', 'match', 'unmatch', 'remove_from_collection', 'delete_media', 'delete'];

/// Between Beheren and Meer manieren om te kijken.
const List<String> _aboveMoreWays = ['fileinfo', 'series', 'details', 'request'];

/// What Meer manieren om te kijken holds: every other way to start this title.
const List<String> _moreWays = [
  'play_from_beginning',
  'play_version',
  'play_external',
  'play_trailer',
  'shuffle_play',
  'shuffle',
];

const List<String> _bottom = ['share'];

/// The play triangle fills less of its box than the other icons do.
const Set<String> _largeIcons = {'play_item', 'play'};

/// The icons of the reference. Other rows keep the icon the menu gave them.
(IconData, bool)? _ownIcon(MediaMenuAction action) => switch (action.value) {
  'play_item' || 'play' => (Symbols.play_arrow_rounded, true),
  'watchlist_toggle' => (Symbols.bookmark_rounded, action.active),
  'add_to' => (Symbols.playlist_add_rounded, false),
  'rate' => (Symbols.star_rounded, false),
  'watch' => (Symbols.check_circle_rounded, false),
  'unwatch' => (Symbols.check_circle_rounded, true),
  'download' || 'download_collection' || 'download_playlist' => (Symbols.arrow_circle_down_rounded, false),
  'fileinfo' => (Symbols.info_rounded, false),
  _ => null,
};

/// A row of the sheet: an action of the menu, or a group that opens its own list.
class LibraryPhoneMenuRow {
  const LibraryPhoneMenuRow({
    required this.icon,
    required this.label,
    this.value,
    this.filledIcon = false,
    this.subtitle,
    this.destructive = false,
    this.iconScale = 1,
    this.children = const [],
  });

  LibraryPhoneMenuRow._fromAction(MediaMenuAction action)
    : icon = _ownIcon(action)?.$1 ?? action.icon,
      filledIcon = _ownIcon(action)?.$2 ?? false,
      label = action.label,
      value = action.value,
      subtitle = action.subtitle,
      destructive = action.destructive,
      iconScale = _largeIcons.contains(action.value) ? LibraryPhoneMetrics.sheetPlayIconScale : 1,
      children = const [];

  final IconData icon;
  final String label;

  /// What the menu dispatches on. Null on a group.
  final String? value;
  final bool filledIcon;
  final String? subtitle;
  final bool destructive;
  final double iconScale;
  final List<LibraryPhoneMenuRow> children;
}

/// [actions] in the order of the reference. Every action comes back exactly once.
List<LibraryPhoneMenuRow> libraryPhoneMenuRows(List<MediaMenuAction> actions) {
  List<LibraryPhoneMenuRow> pick(List<String> values) => [
    for (final value in values)
      for (final action in actions)
        if (action.value == value) LibraryPhoneMenuRow._fromAction(action),
  ];
  final known = {..._aboveManage, ..._manage, ..._aboveMoreWays, ..._moreWays, ..._bottom};
  final manage = pick(_manage);
  final moreWays = pick(_moreWays);
  return [
    ...pick(_aboveManage),
    if (manage.isNotEmpty) LibraryPhoneMenuRow(icon: Symbols.edit_rounded, label: t.mediaMenu.manage, children: manage),
    ...pick(_aboveMoreWays),
    if (moreWays.isNotEmpty)
      LibraryPhoneMenuRow(
        icon: Symbols.format_list_bulleted_rounded,
        label: t.mediaMenu.moreWaysToWatch,
        children: moreWays,
      ),
    for (final action in actions)
      if (!known.contains(action.value)) LibraryPhoneMenuRow._fromAction(action),
    ...pick(_bottom),
  ];
}

/// Opens the menu and answers with the chosen row's value.
Future<String?> showLibraryPhoneMenu(
  BuildContext context, {
  required String title,
  required List<LibraryPhoneMenuRow> rows,
  bool focusFirstRow = false,
}) => OverlaySheetController.showAdaptive<String>(
  context,
  showDragHandle: true,
  presentation: OverlaySheetPresentation.floating,
  backgroundColor: tokens(context).bg,
  builder: (_) => LibraryPhoneMenuSheet(title: title, rows: rows, focusFirstRow: focusFirstRow),
);

/// The sheet: one list at a time, with a group opening in its place.
class LibraryPhoneMenuSheet extends StatefulWidget {
  const LibraryPhoneMenuSheet({super.key, required this.title, required this.rows, this.focusFirstRow = false});

  final String title;
  final List<LibraryPhoneMenuRow> rows;
  final bool focusFirstRow;

  @override
  State<LibraryPhoneMenuSheet> createState() => _LibraryPhoneMenuSheetState();
}

class _LibraryPhoneMenuSheetState extends State<LibraryPhoneMenuSheet> {
  LibraryPhoneMenuRow? _openGroup;

  void _choose(LibraryPhoneMenuRow row) {
    if (row.children.isNotEmpty) {
      setState(() => _openGroup = row);
    } else {
      OverlaySheetController.closeAdaptive(context, row.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = _openGroup;
    final rows = group?.children ?? widget.rows;
    return AutomationNode(
      id: AutomationIds.sheetContextMenu,
      role: 'sheet',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LibraryPhoneSheetHeading(
            title: group?.label ?? widget.title,
            onBack: group == null ? null : () => setState(() => _openGroup = null),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: LibraryPhoneMetrics.sheetListPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, row) in rows.indexed)
                    AutomationNode(
                      key: ValueKey(row.value ?? row.label),
                      id: AutomationIds.sheetContextMenuItem,
                      instance: '$i',
                      role: 'list.item',
                      child: LibraryPhoneSheetActionRow(
                        icon: row.icon,
                        filledIcon: row.filledIcon,
                        iconScale: row.iconScale,
                        label: row.label,
                        subtitle: row.subtitle,
                        destructive: row.destructive,
                        autofocus: widget.focusFirstRow && i == 0,
                        onTap: () => _choose(row),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
