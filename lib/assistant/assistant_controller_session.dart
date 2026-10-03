import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../profiles/active_profile_provider.dart';
import '../profiles/profile_connection_registry.dart';
import '../providers/download_provider.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/home_layout_provider.dart';
import '../providers/libraries_provider.dart';
import '../providers/multi_server_provider.dart';
import '../providers/playback_state_provider.dart';
import '../providers/seerr_provider.dart';
import '../providers/tautulli_provider.dart';
import '../services/download_manager_service.dart';
import '../services/unified_catalog/home_custom_row_loader.dart';
import 'assistant_controller.dart';
import 'assistant_tool_context.dart';
import 'assistant_playback.dart';
import 'assistant_provider.dart';
import 'assistant_tools.dart';
import 'assistant_web_lookup.dart';

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
AssistantController assistantControllerForSession(BuildContext context) => AssistantController(
  buildContext: (screen) => _sessionToolContext(context, screen),
  webFor: assistantWebServicesFor,
);

/// Web search for find_title, from the provider settings. Wikipedia needs
/// no key; the one web search per question uses the Ollama key (the Cloud
/// key, or the optional ollama.com key next to an Ollama server) or the
/// OpenRouter key. Whether web search is on at all is decided by the caller.
AssistantWebServices? assistantWebServicesFor(AssistantProviderConfig config) => AssistantWebServices.forKeys(
  ollamaWebKey: switch (config.kind) {
    AssistantProviderKind.ollamaCloud => config.apiKey,
    AssistantProviderKind.ollamaServer => config.ollamaWebKey,
    AssistantProviderKind.openRouter => '',
  },
  openRouterKey: config.kind == AssistantProviderKind.openRouter ? config.apiKey : '',
);

AssistantToolContext _sessionToolContext(BuildContext context, AssistantScreenContext? screen) {
  final manager = context.read<MultiServerProvider>().serverManager;
  final activeProfile = context.read<ActiveProfileProvider>();
  final layout = context.read<HomeLayoutProvider?>();
  final libraries = context.read<LibrariesProvider?>();
  final hidden = context.read<HiddenLibrariesProvider?>();
  final seerr = context.read<SeerrProvider?>();
  final tautulli = context.read<TautulliProvider?>();
  final downloads = context.read<DownloadProvider?>();
  final profileConnections = context.read<ProfileConnectionRegistry?>();
  final profileId = layout?.profileId ?? activeProfile.activeId;
  return AssistantToolContext(
    servers: manager,
    screen: screen,
    playback:
        context.read<PlaybackStateProvider?>()?.assistantPlayback ?? const AssistantPlaybackServices.unavailable(),
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
            participantProfiles: profileConnections == null
                ? null
                : (id) => profileConnections.listJellyfinProfileIdentities(id.value),
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
