import 'package:flutter/material.dart';

import '../automation/automation_ids.dart';
import '../exceptions/media_server_exceptions.dart';
import '../i18n/strings.g.dart';
import '../media/media_backend.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';
import '../utils/app_logger.dart';
import '../utils/deletion_notifier.dart';
import '../utils/dialogs.dart';
import '../utils/snackbar_helper.dart';
import 'media_deletion_failure_message.dart';

/// Asks, then permanently removes [item] and its files from its server, and
/// tells the viewer how it went. True only when the server removed it.
///
/// One path for every menu that offers the delete. [sourceName] goes into the
/// dialog title, so the confirmation names the copy that is about to go, and
/// the message starts with the title itself. [client] is read after the
/// confirmation. A client for any other server than [item]'s is refused
/// before anything is sent: a lookup with a fallback can hand back the first
/// online server when the item's own is gone, and a delete must never land
/// there. The client's own owner guard refuses one that lost its rights.
Future<bool> confirmAndDeleteMediaItem(
  BuildContext context, {
  required MediaItem item,
  required MediaServerClient Function() client,
  String? sourceName,
}) async {
  final isMultipleMediaItems = item.kind == MediaKind.show || item.kind == MediaKind.season;
  final confirmed = await showDeleteConfirmation(
    context,
    title: sourceName == null ? t.mediaMenu.deleteFromServer : '${t.mediaMenu.deleteFromServer} · $sourceName',
    message: [
      item.displayTitle,
      t.mediaMenu.confirmDelete,
      if (isMultipleMediaItems) t.mediaMenu.deleteMultipleWarning,
      if (item.backend == MediaBackend.pleyaServer) t.mediaMenu.pleyaServerDeletesFiles,
    ].join('\n\n'),
    confirmText: t.mediaMenu.deleteFromServer,
    confirmAutomationId: '${AutomationIds.dialogDeleteMedia}[confirm]',
    cancelAutomationId: '${AutomationIds.dialogDeleteMedia}[cancel]',
  );
  if (!confirmed || !context.mounted) return false;

  MediaServerClient? resolved;
  try {
    resolved = client();
    if (resolved.serverId.value != item.serverId) {
      appLogger.w('Delete refused: client for ${resolved.serverId} is not the server of ${item.globalKey}');
      if (context.mounted) showErrorSnackBar(context, t.mediaMenu.deleteServerGone);
      return false;
    }
    final success = await resolved.deleteMediaItem(item);
    if (success) {
      // Broadcast deletion event for cross-screen propagation
      DeletionNotifier().notifyDeletedItem(item: item);
    }
    if (context.mounted) {
      if (success) {
        showSuccessSnackBar(context, t.mediaMenu.mediaDeletedSuccessfully);
      } else {
        showErrorSnackBar(context, t.mediaMenu.mediaFailedToDelete);
      }
    }
    return success;
  } on MediaDeletionIncompleteException catch (e) {
    // Part of it is gone: say what stayed. The title only leaves the UI when the
    // server says it left the catalogue too; a title with a file left is still
    // on the server. The caller refreshes its list either way.
    appLogger.w(t.mediaMenu.mediaFailedToDelete, error: e);
    if (context.mounted) showErrorSnackBar(context, mediaDeletionFailureMessage(e, item.backend));
    final removed = incompleteDeletionRemovedTitle(e, item.kind);
    if (removed) DeletionNotifier().notifyDeletedItem(item: item);
    return removed;
  } catch (e) {
    appLogger.e(t.mediaMenu.mediaFailedToDelete, error: e);
    final message = await resolveMediaDeletionFailureMessage(e, item.backend, resolved);
    if (context.mounted) showErrorSnackBar(context, message);
    return false;
  }
}
