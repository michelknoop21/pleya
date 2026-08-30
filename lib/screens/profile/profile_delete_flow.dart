import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../connection/connection_registry.dart';
import '../../database/app_database.dart';
import '../../i18n/strings.g.dart';
import '../../profiles/active_profile_provider.dart';
import '../../profiles/profile.dart';
import '../../profiles/profile_connection_cleanup.dart';
import '../../profiles/profile_connection_registry.dart';
import '../../profiles/profile_registry.dart';
import '../../providers/download_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../services/storage_service.dart';
import '../../services/unified_catalog/preferred_server_store.dart';
import '../../services/unified_catalog/unified_catalog_query_store.dart';
import '../../services/unified_catalog/source_preference_store.dart';
import '../../utils/app_logger.dart';
import '../../utils/dialogs.dart';
import '../../utils/snackbar_helper.dart';

Future<bool> confirmAndDeleteProfile(
  BuildContext context, {
  required Profile profile,
  required String title,
  required String message,
  String? confirmText,
}) async {
  final confirmed = await showDeleteConfirmation(context, title: title, message: message, confirmText: confirmText);
  if (!confirmed || !context.mounted) return false;

  try {
    await deleteProfile(context, profile);
    return true;
  } catch (error, stackTrace) {
    appLogger.w('Failed to delete profile ${profile.id}', error: error, stackTrace: stackTrace);
    if (context.mounted) {
      showErrorSnackBar(context, t.errors.failedToDeleteProfile(displayName: profile.displayName));
    }
    return false;
  }
}

Future<void> deleteProfile(BuildContext context, Profile profile) async {
  final pcRegistry = context.read<ProfileConnectionRegistry>();
  final connRegistry = context.read<ConnectionRegistry>();
  final profileRegistry = context.read<ProfileRegistry>();
  final downloadProvider = context.read<DownloadProvider>();
  final database = context.read<AppDatabase>();
  final active = context.read<ActiveProfileProvider>();
  final storage = context.read<StorageService>();
  final serverManager = context.read<MultiServerProvider>().serverManager;
  final wasActive = active.activeId == profile.id;

  await downloadProvider.deleteDownloadsForProfile(profile.id);
  await database.deleteRecommendationDataForProfile(profile.id);
  // Hoofdstuk 14.8: deleting a profile wipes its remembered source choices.
  // Before the profile row goes, while its scope is still derivable.
  await SourcePreferenceStore.clearForProfileScope(storage.userScopeForProfileId(profile.id));
  // Same rule for the profile's default server: which machine someone watches
  // from goes with the profile, it does not linger for the next one.
  await PreferredServerStore.clearForProfileScope(storage.userScopeForProfileId(profile.id));
  // And how they had Films and Series set up (hoofdstuk 22): a genre or a
  // library selection describes what someone browses, so it leaves with them
  // rather than greeting the next profile on this device.
  await UnifiedCatalogQueryStore.clearForProfileScope(storage.userScopeForProfileId(profile.id));
  await removeAllProfileConnectionsAndCleanup(
    profileId: profile.id,
    profileConnections: pcRegistry,
    connections: connRegistry,
    storage: storage,
    serverManager: serverManager,
  );
  await profileRegistry.remove(profile.id);

  if (!wasActive) return;
  final remaining = active.profiles.where((p) => p.id != profile.id).toList();
  if (remaining.isNotEmpty) {
    await active.activate(remaining.first);
  } else {
    await active.clearActiveProfile();
  }
}
