/// Source-bound metadata tools shared by the mobile and TV catalogues.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_source.dart';
import '../../metadata_edit/metadata_edit_adapters.dart';
import '../../providers/multi_server_provider.dart';
import '../../providers/offline_mode_provider.dart';
import '../../screens/metadata_edit_screen.dart';
import '../../screens/plex_match_screen.dart';
import '../../services/plex_client.dart';
import '../../widgets/app_menu.dart';
import '../../widgets/media_item_deletion.dart';
import '../../widgets/overlay_sheet.dart';

enum UnifiedManagementAction { artwork, metadata, match, delete }

List<UnifiedManagementAction> unifiedManagementActions({
  required MediaServerClient? client,
  required MediaKind kind,
  required bool canManage,
  required bool isOffline,
}) {
  if (isOffline || !canManage || client == null) return const [];
  return [
    if (supportsMetadataEdit(client, kind)) ...[UnifiedManagementAction.artwork, UnifiedManagementAction.metadata],
    if (client is PlexClient && (kind == MediaKind.movie || kind == MediaKind.show)) UnifiedManagementAction.match,
    // The same kinds and the same owner rule as "Delete from server" in the
    // per-item menu. [canManage] is false on every backend without a delete.
    if (kind == MediaKind.movie || kind == MediaKind.show || kind == MediaKind.season || kind == MediaKind.episode)
      UnifiedManagementAction.delete,
  ];
}

class UnifiedManagementChoice {
  const UnifiedManagementChoice(this.source, this.action, this.client, {String? sourceName}) : _sourceName = sourceName;
  final UnifiedMediaSource source;
  final UnifiedManagementAction action;
  final MediaServerClient client;
  final String? _sourceName;

  /// Which copy this row is about: the server, and on a server that holds the
  /// title twice (a "Films" and a "4K Films" library) the library as well, so
  /// the row and the dialog never read the same for two different copies.
  String get sourceName => _sourceName ?? source.serverName;

  String get label => switch (action) {
    UnifiedManagementAction.artwork => t.metadataEdit.artwork,
    UnifiedManagementAction.metadata => t.metadataEdit.editMetadata,
    UnifiedManagementAction.match => t.matchScreen.fixMatch,
    UnifiedManagementAction.delete => t.mediaMenu.deleteFromServer,
  };
  bool get destructive => action == UnifiedManagementAction.delete;

  /// `<action>.<source key>`: one copy's row, stable whatever else the menu
  /// holds above it (`sheet.context_menu.item[delete.<server>:<item>]`).
  String get automationInstance => '${action.name}.${source.sourceKey}';
  IconData get icon => switch (action) {
    UnifiedManagementAction.artwork => Symbols.image_rounded,
    UnifiedManagementAction.metadata => Symbols.edit_rounded,
    UnifiedManagementAction.match => Symbols.search_rounded,
    UnifiedManagementAction.delete => Symbols.delete_forever_rounded,
  };
}

/// The row text: on a title with more than one source it names the server the
/// action works on, because each source is its own row.
String managementLabel(UnifiedMediaGroup group, UnifiedManagementChoice choice) =>
    group.hasMultipleSources ? '${choice.label} · ${choice.sourceName}' : choice.label;

/// [source]'s server, plus its library when [group] has another copy on that
/// same server.
String _sourceName(UnifiedMediaGroup group, UnifiedMediaSource source) {
  final sameServer = group.sources.where((s) => s.serverId == source.serverId).length;
  if (sameServer < 2) return source.serverName;
  return '${source.serverName} · ${source.libraryTitle ?? source.item.id}';
}

List<UnifiedManagementChoice> unifiedManagementChoices(
  BuildContext context,
  UnifiedMediaGroup group, {
  required bool isOffline,
}) {
  final manager = context.read<MultiServerProvider?>()?.serverManager;
  if (manager == null) return const [];
  return [
    for (final source in group.sources)
      if (manager.isServerOnline(source.serverId))
        if (manager.getClient(source.serverId) case final client?)
          for (final action in unifiedManagementActions(
            client: client,
            kind: source.item.kind,
            canManage: manager.canManageServerMetadata(source.serverId),
            isOffline: isOffline,
          ))
            UnifiedManagementChoice(source, action, client, sourceName: _sourceName(group, source)),
  ];
}

/// [onDeleted] hears which copy its server removed, so a wall can take that
/// one card off in place; without it a delete reports through [onChanged]
/// like an edit does.
Future<void> runUnifiedManagementChoice(
  BuildContext context,
  UnifiedManagementChoice choice, {
  VoidCallback? onChanged,
  ValueChanged<UnifiedMediaSource>? onDeleted,
}) async {
  final manager = context.read<MultiServerProvider?>()?.serverManager;
  if (manager == null) return;
  final source = choice.source;
  final client = manager.getClient(source.serverId);
  if (!identical(client, choice.client) || !manager.isServerOnline(source.serverId)) return;
  // Re-read rights and the exact source after the menu closes. Never fall
  // back to another online server for a canonical write.
  if (!unifiedManagementActions(
    client: client,
    kind: source.item.kind,
    canManage: manager.canManageServerMetadata(source.serverId),
    isOffline: context.read<OfflineModeProvider?>()?.isOffline ?? false,
  ).contains(choice.action))
    return;
  if (choice.action == UnifiedManagementAction.delete) {
    // One source, never the whole title: the dialog names the server, and the
    // other copies of a title on several servers stay where they are.
    final deleted = await confirmAndDeleteMediaItem(
      context,
      item: source.item,
      client: () => choice.client,
      sourceName: choice.sourceName,
    );
    if (!deleted || !context.mounted) return;
    if (onDeleted != null) {
      onDeleted(source);
    } else {
      onChanged?.call();
    }
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => switch (choice.action) {
        UnifiedManagementAction.artwork => MetadataEditScreen(
          metadata: source.item,
          artworkOnly: true,
          expectedClient: choice.client,
        ),
        UnifiedManagementAction.metadata => MetadataEditScreen(metadata: source.item, expectedClient: choice.client),
        UnifiedManagementAction.match => PlexMatchScreen(
          metadata: source.item,
          expectedClient: choice.client as PlexClient,
        ),
        UnifiedManagementAction.delete => throw StateError('handled above'),
      },
    ),
  );
  if (context.mounted) onChanged?.call();
}

Future<void> showUnifiedManagementMenu(
  BuildContext context,
  UnifiedMediaGroup group, {
  required bool isOffline,
  VoidCallback? onChanged,
  ValueChanged<UnifiedMediaSource>? onDeleted,
}) async {
  final choices = unifiedManagementChoices(context, group, isOffline: isOffline);
  if (choices.isEmpty) return;
  final choice = await OverlaySheetController.showAdaptive<UnifiedManagementChoice>(
    context,
    builder: (_) => AppMenuSheet<UnifiedManagementChoice>(
      title: group.representativeSource.item.displayTitle,
      entries: [
        for (final choice in choices)
          AppMenuItem(
            value: choice,
            icon: choice.icon,
            semanticLabel: managementLabel(group, choice),
            child: Builder(
              builder: (rowContext) => AutomationNode(
                id: AutomationIds.sheetContextMenuItem,
                instance: choice.automationInstance,
                role: 'list.item',
                state: () => {'label': managementLabel(group, choice), 'focused': automationRowHasFocus(rowContext)},
                child: Text(managementLabel(group, choice)),
              ),
            ),
            destructive: choice.destructive,
          ),
      ],
    ),
  );
  if (choice != null && context.mounted) {
    await runUnifiedManagementChoice(context, choice, onChanged: onChanged, onDeleted: onDeleted);
  }
}
