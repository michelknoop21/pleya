/// Source-bound metadata tools shared by the mobile and TV catalogues.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

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
import '../../widgets/overlay_sheet.dart';

enum UnifiedManagementAction { artwork, metadata, match }

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
  ];
}

class UnifiedManagementChoice {
  const UnifiedManagementChoice(this.source, this.action, this.client);
  final UnifiedMediaSource source;
  final UnifiedManagementAction action;
  final MediaServerClient client;

  String get label => switch (action) {
    UnifiedManagementAction.artwork => t.metadataEdit.artwork,
    UnifiedManagementAction.metadata => t.metadataEdit.editMetadata,
    UnifiedManagementAction.match => t.matchScreen.fixMatch,
  };
  IconData get icon => switch (action) {
    UnifiedManagementAction.artwork => Symbols.image_rounded,
    UnifiedManagementAction.metadata => Symbols.edit_rounded,
    UnifiedManagementAction.match => Symbols.search_rounded,
  };
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
            UnifiedManagementChoice(source, action, client),
  ];
}

Future<void> runUnifiedManagementChoice(
  BuildContext context,
  UnifiedManagementChoice choice, {
  VoidCallback? onChanged,
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
            label: group.hasMultipleSources ? '${choice.label} · ${choice.source.serverName}' : choice.label,
          ),
      ],
    ),
  );
  if (choice != null && context.mounted) await runUnifiedManagementChoice(context, choice, onChanged: onChanged);
}
