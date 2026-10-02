import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../profiles/active_profile_provider.dart';
import '../providers/download_provider.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/home_layout_provider.dart';
import '../providers/libraries_provider.dart';
import '../providers/multi_server_provider.dart';
import '../providers/seerr_provider.dart';
import '../providers/tautulli_provider.dart';
import '../services/download_manager_service.dart';
import '../services/unified_catalog/home_custom_row_loader.dart';
import 'assistant_controller.dart';
import 'assistant_tool_context.dart';
import 'assistant_tools.dart';

/// The controller for one profile session. Register it lazily inside the
/// profile-scoped providers (`ProfileSessionScreen`), so a profile switch
/// drops the conversation and any waiting card:
///
/// ```dart
/// ChangeNotifierProvider(create: assistantControllerForSession, lazy: true),
/// ```
///
/// [context] is the provider's own element; the session providers are read
/// on each ask, never at creation, so a lazy provider such as
/// [HomeLayoutProvider] is only built once Big P is asked something. A
/// provider that is not in scope leaves its service null, which keeps those
/// tools out of the run.
AssistantController assistantControllerForSession(BuildContext context) =>
    AssistantController(buildContext: (screen) => _sessionToolContext(context, screen));

AssistantToolContext _sessionToolContext(BuildContext context, AssistantScreenContext? screen) {
  final manager = context.read<MultiServerProvider>().serverManager;
  final activeProfile = context.read<ActiveProfileProvider>();
  final layout = context.read<HomeLayoutProvider?>();
  final libraries = context.read<LibrariesProvider?>();
  final hidden = context.read<HiddenLibrariesProvider?>();
  final seerr = context.read<SeerrProvider?>();
  final tautulli = context.read<TautulliProvider?>();
  final downloads = context.read<DownloadProvider?>();
  final profileId = layout?.profileId ?? activeProfile.activeId;
  return AssistantToolContext(
    servers: manager,
    screen: screen,
    catalog: libraries == null || hidden == null || profileId == null
        ? null
        : AssistantCatalogServices(
            // Built as Home's own rows build it (TvHomeCustomizeController).
            rowLoader: CatalogHomeCustomRowLoader(
              libraries: () => libraries.libraries,
              isServerVisible: manager.isServerVisible,
              hiddenLibraryKeys: () => hidden.hiddenLibraryKeys,
              clientFor: manager.getClient,
            ),
            saveRow: layout?.saveCustomRow,
            profileId: profileId,
            activeProfileId: () => activeProfile.activeId ?? '',
          ),
    insights: tautulli == null ? null : AssistantInsightServices(tautulliFor: tautulli.clientForServer),
    requests: seerr == null ? null : AssistantRequestServices(client: () => seerr.client),
    media: downloads == null
        ? null
        : AssistantMediaServices(
            downloadsSupported: DownloadManagerService.platformDownloadsSupported,
            downloadStatus: (key) => downloads.getProgress(key)?.status,
            queueEpisode: (episode, client) async => await downloads.queueDownload(episode, client) > 0,
            blockedOnCellular: DownloadManagerService.shouldBlockDownloadOnCellular,
          ),
  );
}
