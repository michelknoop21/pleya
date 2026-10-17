import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../database/app_database.dart';
import '../media/ids.dart';
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
import '../screens/video_player_screen.dart' show VideoPlayerScreenState;
import '../services/download_manager_service.dart';
import '../services/memory/memory_service.dart';
import '../services/recommendations/recommendation_service.dart';
import '../services/trakt/trakt_sync_service.dart';
import '../services/unified_catalog/home_custom_row_loader.dart';
import '../models/plex/plex_home_user.dart' show PlexHomeUser;
import '../providers/trakt_account_provider.dart';
import '../profiles/household_kids_store.dart';
import '../profiles/plex_home_service.dart';
import 'current_user_binding.dart';
import 'assistant_spoiler_context.dart';
import 'assistant_spoiler_progress.dart';
import 'assistant_controller.dart';
import 'assistant_kids_ages_store.dart';
import 'assistant_kids_profile_store.dart';
import 'assistant_memory.dart';
import 'assistant_memory_host.dart';
import 'assistant_memory_overview.dart';
import 'assistant_tool_context.dart';
import 'assistant_playback.dart';
import 'assistant_provider.dart';
import 'assistant_title_facts.dart';
import 'assistant_title_facts_cache.dart';
import 'assistant_trakt_services.dart';
import 'assistant_tools.dart';
import 'assistant_web_lookup.dart';
import 'big_p_voice.dart';

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
AssistantController assistantControllerForSession(BuildContext context) {
  final factsCache = TitleFactsCache(db: context.read<AppDatabase?>());
  final controller = AssistantController(
    buildContext: (screen) => _sessionToolContext(context, screen, factsCache),
    webFor: assistantWebServicesFor,
    serverChanges: context.read<MultiServerProvider>(),
  );
  BigPVoice(controller, playbackActive: () => VideoPlayerScreenState.activeId != null);
  // The children's switch flipped while a memory card waits: the card goes.
  void kidsChanged() {
    unawaited(controller.recheckMemoryCards());
    unawaited(controller.refreshIdleProfile());
  }

  KidsProfileStore.changes.addListener(kidsChanged);
  controller.onDispose(() => KidsProfileStore.changes.removeListener(kidsChanged));
  return controller;
}

/// The "Vraag of werk bij" field of the memory screen, for one profile
/// session: its own run with the memory tools only, apart from the
/// conversation. Register it lazily next to the controller.
AssistantMemoryHost assistantMemoryHostForSession(BuildContext context) {
  final factsCache = TitleFactsCache(db: context.read<AppDatabase?>());
  final host = AssistantMemoryHost(
    buildContext: () => _sessionToolContext(context, null, factsCache),
    languageName: assistantLanguageName,
  );
  KidsProfileStore.changes.addListener(host.recheckCards);
  host.onDispose(() => KidsProfileStore.changes.removeListener(host.recheckCards));
  return host;
}

/// The writer of the memory overview for one profile session; it calls the
/// model only while the memory screen asks it to.
AssistantMemoryOverviewWriter assistantMemoryOverviewWriterForSession(BuildContext context) {
  final activeProfile = context.read<ActiveProfileProvider>();
  return AssistantMemoryOverviewWriter(
    memory: AssistantMemoryServices(
      service: context.read<MemoryService>(),
      activeProfileId: () => activeProfile.activeId,
      kidsProfile: () => assistantIsKidsProfile(activeProfile.active),
    ),
    languageName: assistantLanguageName,
  );
}

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

AssistantToolContext _sessionToolContext(BuildContext context, AssistantScreenContext? screen, TitleFactsCache cache) {
  final manager = context.read<MultiServerProvider>().serverManager;
  final activeProfile = context.read<ActiveProfileProvider>();
  final layout = context.read<HomeLayoutProvider?>();
  final libraries = context.read<LibrariesProvider?>();
  final hidden = context.read<HiddenLibrariesProvider?>();
  final seerr = context.read<SeerrProvider?>();
  final tautulli = context.read<TautulliProvider?>();
  final downloads = context.read<DownloadProvider?>();
  final profileConnections = context.read<ProfileConnectionRegistry?>();
  final recommendations = context.read<RecommendationService?>();
  final profileId = layout?.profileId ?? activeProfile.activeId;
  final plexHome = context.read<PlexHomeService?>();
  final trakt = context.read<TraktAccountProvider?>();
  final playback = context.read<PlaybackStateProvider?>()?.assistantPlayback;
  final memory = context.read<MemoryService?>();
  // The asker's own Trakt account, for the profile this context was built
  // for: a turn that outlives a profile switch reads nothing of the next one.
  // Evaluated live, and only with personalization on and off children's profiles.
  final traktUser = trakt?.activeUserUuid;
  String? traktBlock() => trakt == null || traktUser == null
      ? 'trakt_not_connected'
      : assistantTraktBlock(
          connected: trakt.isConnected,
          kidsProfile: trakt.isKidsProfile,
          sameProfile: trakt.activeUserUuid == traktUser,
          personalization: recommendations?.isPersonalizationEnabled ?? false,
        );
  bool traktAvailable() => traktBlock() == null;
  final traktSeen = trakt == null || traktUser == null
      ? null
      : AssistantTraktSeen(
          available: traktAvailable,
          read: () => TraktSyncService.instance.library.seen(expectUser: traktUser),
        );
  return AssistantToolContext(
    servers: manager,
    screen: screen,
    currentUser: currentUserContextFor(
      manager,
      profileId: activeProfile.activeId,
      plexHome: plexHome?.current ?? const <String, List<PlexHomeUser>>{},
      traktAccountId: trakt?.username,
    ),
    playback: playback ?? const AssistantPlaybackServices.unavailable(),
    spoilers: profileId == null || hidden == null
        ? null
        : AssistantSpoilerServices(
            profileId: profileId,
            profileCurrent: () =>
                activeProfile.activeId == profileId &&
                !activeProfile.isBinding &&
                activeProfile.lastBindingSucceeded &&
                hidden.isInitialized,
            boundary: () => playback?.watchBoundary?.call(),
            boundaryCurrent: (boundary) => playback?.boundaryCurrent?.call(boundary) ?? false,
            resume: (cancelled) {
              // A live player with unsupported/unknown position must not be
              // replaced by potentially later persisted progress.
              if (playback?.available() ?? false) return Future.value(null);
              return discoverAssistantSpoilerProgress(
                profileId: profileId,
                profileCurrent: () =>
                    activeProfile.activeId == profileId &&
                    !activeProfile.isBinding &&
                    activeProfile.lastBindingSucceeded &&
                    hidden.isInitialized &&
                    !(context.read<PlaybackStateProvider?>()?.assistantPlayback?.available() ?? false),
                visibleServers: () => [
                  for (final id in manager.serverIds)
                    if (manager.isServerVisible(ServerId(id))) ServerId(id),
                ],
                clientFor: (id) => manager.isServerOnline(id) ? manager.getClient(id) : null,
                libraryVisible: (server, library) =>
                    hidden.isInitialized && !hidden.isLibraryHidden('$server:$library'),
                cancelled: cancelled,
              );
            },
            libraryVisible: (server, library) =>
                hidden.isInitialized &&
                !hidden.isLibraryHidden('$server:$library') &&
                manager.isServerVisible(ServerId(server)),
          ),
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
    // One per ask, so the lookup budget starts fresh. The TMDB key and the
    // online switch are read per lookup, so a change in the settings counts
    // from the next question.
    titleFacts: TitleFactsService(
      cache: cache,
      clientFor: manager.getClient,
      seerr: () => seerr?.client,
      tmdbKey: () => AssistantProviderStore.current?.tmdbKey,
      tmdbBase: () => AssistantProviderStore.current?.baseUrl,
      online: () => AssistantProviderStore.current?.onlineFacts ?? true,
    ),
    kidsAges: KidsAgesStore().read,
    householdKids: HouseholdKidsStore().read,
    // Read per ask, so a switch flipped in Instellingen counts from the next
    // question.
    kidsProfile: () => assistantIsKidsProfile(activeProfile.active),
    // The service of this profile session; the tools and a card check per
    // call that its profile is still the active one.
    memory: memory == null
        ? null
        : AssistantMemoryServices(
            service: memory,
            activeProfileId: () => activeProfile.activeId,
            kidsProfile: () => assistantIsKidsProfile(activeProfile.active),
          ),
    personal: recommendations == null
        ? null
        : AssistantPersonalServices(
            userName: activeProfile.active?.displayName ?? '',
            recent: () => recommendations.recentSeeds(limit: 12),
            everSeen: recommendations.everSeenKeys,
            everSeenIdentities: () async => [
              ...await recommendations.everSeenIdentities(),
              ...?await traktSeen?.identities(),
            ],
            // A completed view weighs 1.0; a stopped one only 0.4.
            everCompleted: () => recommendations.everSeenKeys(minWeight: 1.0),
            everCompletedIdentities: () async => [
              ...await recommendations.everSeenIdentities(minWeight: 1.0),
              ...?await traktSeen?.identities(completedOnly: true),
            ],
            seenIncludesTrakt: () => traktSeen?.included ?? false,
            seenTraktUnavailable: () => traktSeen?.unavailable ?? false,
            taste: recommendations.taste,
            picks: recommendations.buildRows,
          ),
    trakt: trakt == null || traktUser == null
        ? null
        : AssistantTraktServices(
            blocked: traktBlock,
            watchlist: () => TraktSyncService.instance.library.watchlist(expectUser: traktUser),
          ),
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
