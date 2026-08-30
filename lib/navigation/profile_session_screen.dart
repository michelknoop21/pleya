import '../providers/download_provider.dart';
import '../services/watchlist/watchlist_snapshot_store.dart';
import '../services/api_cache.dart';
import '../providers/watchlist_store.dart';
import '../providers/watchlist_provider.dart';
import '../media/media_backend.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../focus/key_event_utils.dart';
import '../media/ids.dart';
import '../media/media_server_client.dart';
import '../profiles/active_profile_provider.dart';
import '../providers/companion_remote_provider.dart';
import '../providers/discover_provider.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/home_layout_provider.dart';
import '../providers/libraries_provider.dart';
import '../providers/multi_server_provider.dart';
import '../providers/playback_state_provider.dart';
import '../providers/seerr_provider.dart';
import '../providers/tautulli_provider.dart';
import '../profiles/plex_home_service.dart';
import '../profiles/plex_self_account.dart';
import '../providers/now_watching_provider.dart';
import '../providers/trakt_account_provider.dart';
import '../providers/trackers_provider.dart';
import '../providers/unified_catalogs.dart';
import '../providers/user_profile_provider.dart';
import '../providers/watch_state_store.dart';
import '../database/app_database.dart';
import '../i18n/strings.g.dart';
import '../screens/main_screen.dart';
import '../services/livetv/plex_favorite_channels_service.dart';
import '../services/recommendations/interaction_recorder.dart';
import '../services/recommendations/personalized_rows_builder.dart';
import '../services/recommendations/recommendation_service.dart';
import '../services/recommendations/tautulli_history_importer.dart';
import '../services/recommendations/tautulli_import_binding.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import '../services/tautulli/tautulli_server_binding.dart';
import '../utils/app_logger.dart';
import '../watch_together/providers/watch_together_provider.dart';
import 'profile_navigation_scope.dart';

/// Root route for an active profile session.
///
/// The root app navigator owns setup/auth/profile-picking. This route owns the
/// profile-scoped provider tree and a nested navigator for all content routes.
/// Changing the active profile changes the keyed boundary below, disposing the
/// old nested navigator, MainScreen, tab state, and profile-scoped providers.
///
/// Keep profile-owned routes, dialogs, sheets, and virtual keyboards on the
/// nearest navigator from this subtree. Keep setup/auth/PIN/profile-picker flows
/// on the root navigator so they survive this subtree being replaced.
class ProfileSessionScreen extends StatefulWidget {
  const ProfileSessionScreen({super.key, this.isOfflineMode = false, this.initialPromptHandled = false})
    : profileShellBuilder = null;

  @visibleForTesting
  const ProfileSessionScreen.forTesting({
    super.key,
    this.isOfflineMode = false,
    this.initialPromptHandled = false,
    required this.profileShellBuilder,
  });

  final bool isOfflineMode;
  final bool initialPromptHandled;
  final WidgetBuilder? profileShellBuilder;

  @override
  State<ProfileSessionScreen> createState() => _ProfileSessionScreenState();
}

class _ProfileSessionScreenState extends State<ProfileSessionScreen> {
  // Profile changes remount the inner session, but the root route survives.
  // Treat the initial launch/profile prompt as handled after the first session
  // frame so switching profiles from the root picker does not immediately open
  // another required-selection picker underneath it. Flipped via a post-frame
  // callback rather than during build to avoid mutating state mid-build.
  bool _hasBuiltSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _hasBuiltSession = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ActiveProfileProvider>(
      builder: (context, activeProfile, _) {
        final activeId = activeProfile.activeId;
        final initialPromptHandled = widget.initialPromptHandled || _hasBuiltSession;
        return KeyedSubtree(
          key: ValueKey<String?>('profile-session:$activeId'),
          child: MultiProvider(
            providers: [
              ChangeNotifierProxyProvider<MultiServerProvider, WatchStateStore>(
                create: (_) => WatchStateStore(),
                update: (_, multiServer, previous) {
                  final provider = previous ?? WatchStateStore();
                  provider.setActiveProfileId(activeId);
                  provider.setActiveClientScopesByServer({
                    for (final serverId in multiServer.serverManager.serverIds)
                      serverId: multiServer.serverManager.getClient(ServerId(serverId))?.cacheServerId,
                  });
                  return provider;
                },
              ),
              ChangeNotifierProvider(
                create: (context) {
                  final provider = TraktAccountProvider();
                  unawaited(
                    provider.onActiveProfileChanged(activeId).catchError((Object e, StackTrace s) {
                      appLogger.w('Trakt profile hydrate failed', error: e, stackTrace: s);
                    }),
                  );
                  return provider;
                },
              ),
              ChangeNotifierProvider(
                create: (context) {
                  final provider = TrackersProvider();
                  unawaited(
                    provider.onActiveProfileChanged(activeId).catchError((Object e, StackTrace s) {
                      appLogger.w('Trackers profile hydrate failed', error: e, stackTrace: s);
                    }),
                  );
                  return provider;
                },
              ),
              ChangeNotifierProvider(
                create: (context) {
                  final provider = SeerrProvider();
                  provider.attachPlexTokenResolver(() => context.read<UserProfileProvider>().currentPlexUserToken());
                  unawaited(
                    provider.onActiveProfileChanged(activeId).catchError((Object e, StackTrace s) {
                      appLogger.w('Seerr profile hydrate failed', error: e, stackTrace: s);
                    }),
                  );
                  return provider;
                },
              ),
              ChangeNotifierProvider(
                create: (context) {
                  final provider = TautulliProvider();
                  // A Tautulli record belongs to a server, so the provider has
                  // to be able to ask which servers exist and which of them this
                  // profile administers. Closures, because a server can still
                  // register after the profile has bound, and the listener so a
                  // late registration re-resolves instead of going unnoticed.
                  final multiServer = context.read<MultiServerProvider>();
                  final plexHome = context.read<PlexHomeService?>();
                  provider.attachServerResolvers(
                    serverIds: () => multiServer.serverManager.serverIds,
                    isOwnerOrAdmin: multiServer.serverManager.isOwnerOrAdmin,
                    // The credential is the admin's, so the provider resolves
                    // whose history it fetches instead of being told. Nullable
                    // read: without a Home service nothing resolves and the
                    // import refuses, which is the right answer either way.
                    selfAccountId: (profileId) => plexSelfAccountIdIn(profileId, plexHome?.current ?? const {}),
                    registryChanges: multiServer,
                  );
                  unawaited(
                    provider.onActiveProfileChanged(activeId).catchError((Object e, StackTrace s) {
                      appLogger.w('Tautulli profile hydrate failed', error: e, stackTrace: s);
                    }),
                  );
                  return provider;
                },
              ),
              // Everything Tautulli reports is admin data, so this poller is
              // wired to say no by default: without an owned Plex server and a
              // paired instance it never starts a timer, never sends a request
              // and never holds state. The dependencies are read once and kept,
              // because the closures outlive any single build.
              ChangeNotifierProvider(
                create: (context) {
                  final tautulli = context.read<TautulliProvider>();
                  final multiServer = context.read<MultiServerProvider>();
                  final activeProfile = context.read<ActiveProfileProvider>();
                  final plexHome = context.read<PlexHomeService>();

                  // Two different questions. Whether this profile may see any of
                  // it is about ownership anywhere; which client can resolve a
                  // reported rating key is about the one server Tautulli
                  // watches, and only the second one may guess.
                  bool ownsAServer() {
                    final manager = multiServer.serverManager;
                    return manager.serverIds.any((id) => manager.isOwnerOrAdmin(ServerId(id)));
                  }

                  ServerId? monitoredServerId() {
                    final manager = multiServer.serverManager;
                    return tautulliMonitoredServer(
                      machineIdentifier: tautulli.machineIdentifier,
                      serverIds: manager.serverIds,
                      isOwnerOrAdmin: manager.isOwnerOrAdmin,
                    );
                  }

                  return NowWatchingProvider(
                    client: () => tautulli.client,
                    enabled: ownsAServer,
                    selfUserId: () => plexSelfAccountId(activeProfile.activeId, plexHome),
                    // Tautulli hands out Plex library paths for artwork, which
                    // only a Plex client can turn into a loadable URL.
                    artworkClient: () {
                      final serverId = monitoredServerId();
                      return serverId == null ? null : multiServer.getPlexClientForServer(serverId);
                    },
                  );
                },
              ),
              ChangeNotifierProvider(
                create: (context) =>
                    HiddenLibrariesProvider(storageService: context.read<StorageService>(), profileId: activeId),
                lazy: true,
              ),
              ChangeNotifierProvider(
                create: (context) =>
                    HomeLayoutProvider(storageService: context.read<StorageService>(), profileId: activeId),
                lazy: true,
              ),
              ChangeNotifierProvider(
                create: (context) => LibrariesProvider(
                  storageService: context.read<StorageService>(),
                  multiServer: context.read<MultiServerProvider>(),
                ),
              ),
              // Fase 3's lifecycle owner for the unified catalogs, holding the
              // two hoofdstuk 10.1 defines: Films and Series. Profile-scoped
              // like LibrariesProvider/HiddenLibrariesProvider above —
              // hoofdstuk 22 requires unified providers to be disposed on
              // profile switch, which this KeyedSubtree does for free once
              // `dispose:` fans out to the catalogs that were built.
              //
              // Lazy twice over: this object is not created until something
              // reads it, and neither catalog is created until something asks
              // for it by name, so a Films-only session never builds a Series
              // merge. Neither one opens a connection before a screen calls
              // `ensureStarted()`. A plain Provider rather than a
              // ChangeNotifierProvider because the notifiers are the two
              // catalogs inside, which screens listen to individually.
              Provider<UnifiedCatalogs>(
                create: (context) => UnifiedCatalogs(
                  multiServer: context.read<MultiServerProvider>(),
                  libraries: context.read<LibrariesProvider>(),
                  hiddenLibraries: context.read<HiddenLibrariesProvider>(),
                ),
                dispose: (_, catalogs) => catalogs.dispose(),
                lazy: true,
              ),
              // On-device recommendation learning + serving, scoped to this
              // profile (torn down with the KeyedSubtree on profile switch).
              Provider<RecommendationService>(
                create: (context) {
                  final database = context.read<AppDatabase>();
                  final tautulli = context.read<TautulliProvider>();
                  final multiServer = context.read<MultiServerProvider>();
                  final activeProfile = context.read<ActiveProfileProvider>();
                  // Nullable read: without a Home service there is no way to
                  // resolve which Plex account this profile is, and the binding
                  // then refuses with `ambiguousUser` instead of guessing.
                  final plexHome = context.read<PlexHomeService?>();
                  final profileId = activeId ?? '';

                  return RecommendationService(
                    profileId: profileId,
                    database: database,
                    titles: PersonalizedRowTitles(
                      topPicks: t.discover.topPicksForYou,
                      becauseYouLike: (genre) => t.discover.becauseYouLike(genre: genre),
                      hiddenGems: t.discover.hiddenGems,
                    ),
                    enabledImportServerIds: tautulli.enabledImportServerIds,
                    // The store load is asynchronous and Discover routinely
                    // wins the race, so the sync waits for the answer instead
                    // of reading an empty map and concluding nothing is paired.
                    importSourcesReady: () => Future.wait([
                      tautulli.whenHydrated(),
                      // The same race, one provider over: without the Home
                      // users the binding cannot tell which Plex account this
                      // profile is and refuses with `ambiguousUser`. Waiting on
                      // `start` alone is not enough — it returns once the
                      // *cache* has been read, which on a first run is empty.
                      plexHome?.whenHomeUsersKnown() ?? Future<void>.value(),
                    ]),
                    importerFactory: (importProfileId, serverId) {
                      // The binding is re-resolved per sync rather than captured,
                      // so a policy change, a disconnect or a server that only
                      // just registered is picked up on the next attempt.
                      final binding = resolveTautulliImportBinding(
                        personalizedRecommendationsEnabled:
                            SettingsService.instanceOrNull?.read(SettingsService.personalizedRecommendations) ?? true,
                        status: tautulli.importStatusFor(serverId),
                        activeProfileId: importProfileId,
                        homeUsers: plexHome?.current ?? const {},
                        registeredServerIds: multiServer.serverManager.serverIds,
                        hasCatalogueClient: (id) => multiServer.serverManager.getClient(id) != null,
                      );
                      if (binding is TautulliImportRefusal) {
                        appLogger.d('RecommendationService: import refused (${binding.reason.name})');
                        return null;
                      }
                      final target = binding as TautulliImportTarget;
                      final client = multiServer.serverManager.getClient(target.serverId);
                      if (client == null) return null;
                      return TautulliHistoryImporter(
                        database: database,
                        access: tautulli,
                        target: target,
                        client: client,
                        // Re-checked before every write, not just at the start:
                        // the sync outlives a profile switch otherwise.
                        isCurrentProfile: () => activeProfile.activeId == importProfileId,
                      );
                    },
                  );
                },
              ),
              Provider<InteractionRecorder>(
                lazy: false,
                create: (context) => InteractionRecorder(
                  database: context.read<AppDatabase>(),
                  profileId: activeId ?? '',
                  clientResolver: context.read<MultiServerProvider>().getClientForServer,
                )..start(),
                dispose: (_, recorder) => recorder.dispose(),
              ),
              ChangeNotifierProvider(
                create: (context) {
                  final activeProfile = context.read<ActiveProfileProvider>();
                  return DiscoverProvider(
                    context.read<MultiServerProvider>(),
                    context.read<HiddenLibrariesProvider>(),
                    context.read<LibrariesProvider>(),
                    isProfileBinding: () => activeProfile.isBinding,
                    recommendations: activeId == null ? null : context.read<RecommendationService>(),
                  );
                },
              ),
              ChangeNotifierProvider(create: (_) => WatchlistStore()..bindProfile(activeId)),
              // The kijklijst is rebuilt per profile: its sources, its cache
              // keys and its snapshot are all scoped to the acting user, and a
              // provider carried across a switch would serve the previous
              // user's list.
              ChangeNotifierProxyProvider3<MultiServerProvider, DownloadProvider, SeerrProvider, WatchlistProvider>(
                create: (context) =>
                    WatchlistProvider(snapshots: WatchlistSnapshotStore(cache: ApiCache.forBackend(MediaBackend.plex))),
                update: (context, multiServer, downloads, seerr, previous) {
                  final provider =
                      previous ??
                      WatchlistProvider(
                        snapshots: WatchlistSnapshotStore(cache: ApiCache.forBackend(MediaBackend.plex)),
                      );
                  provider.isServerOnline = multiServer.isServerOnline;
                  provider.hasDownload = downloads.isDownloaded;
                  provider.seerrConfigured = seerr.isConfigured;
                  provider.attach(
                    profileId: activeId,
                    resolvePlexAuth: () => context.read<UserProfileProvider>().currentPlexAccountAuth(),
                    clientIdentifier: () => context.read<StorageService>().getOrCreateClientIdentifier(),
                    clientsById: () => multiServer.serverManager.onlineClients,
                    serversFor: () => [
                      for (final serverId in multiServer.serverManager.serverIds)
                        (
                          serverId: ServerId(serverId),
                          backend:
                              multiServer.serverManager.getClient(ServerId(serverId))?.backend ?? MediaBackend.plex,
                          client: multiServer.serverManager.getClient(ServerId(serverId)),
                          online: multiServer.isServerOnline(ServerId(serverId)),
                        ),
                    ],
                    cache: ApiCache.forBackend(MediaBackend.plex),
                  );
                  return provider;
                },
              ),
              // The Plex Live TV favorites live in the cloud, on an account
              // plus a Home user, so they hang off the profile session and not
              // off a server client. Lazy on purpose: a Jellyfin-only setup
              // must never open a socket to plex.tv.
              Provider<PlexFavoriteChannelsService>(
                lazy: true,
                create: (context) => PlexFavoriteChannelsService(
                  profileId: activeId ?? '',
                  resolveAuth: () => context.read<UserProfileProvider>().currentPlexAccountAuth(),
                  clientIdentifier: () => context.read<StorageService>().getOrCreateClientIdentifier(),
                ),
                dispose: (_, service) => service.dispose(),
              ),
              ChangeNotifierProvider(create: (context) => PlaybackStateProvider()),
              ChangeNotifierProvider(create: (context) => WatchTogetherProvider()),
              ChangeNotifierProvider(create: (context) => CompanionRemoteProvider()),
            ],
            child: _ProfileSessionNavigator(
              isOfflineMode: widget.isOfflineMode,
              initialPromptHandled: initialPromptHandled,
              profileShellBuilder: widget.profileShellBuilder,
            ),
          ),
        );
      },
    );
  }
}

class _ProfileSessionNavigator extends StatefulWidget {
  const _ProfileSessionNavigator({
    required this.isOfflineMode,
    required this.initialPromptHandled,
    required this.profileShellBuilder,
  });

  final bool isOfflineMode;
  final bool initialPromptHandled;
  final WidgetBuilder? profileShellBuilder;

  @override
  State<_ProfileSessionNavigator> createState() => _ProfileSessionNavigatorState();
}

class _ProfileSessionNavigatorState extends State<_ProfileSessionNavigator> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _mainScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final _routeObserver = RouteObserver<PageRoute<dynamic>>();

  @override
  void initState() {
    super.initState();
    profileNavigationRegistry.attachNavigator(_navigatorKey);
    profileNavigationRegistry.attachMainScaffoldMessenger(_mainScaffoldMessengerKey);
  }

  @override
  void dispose() {
    profileNavigationRegistry.detachNavigator(_navigatorKey);
    profileNavigationRegistry.detachMainScaffoldMessenger(_mainScaffoldMessengerKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProfileNavigationScope(
      navigatorKey: _navigatorKey,
      routeObserver: _routeObserver,
      mainScaffoldMessengerKey: _mainScaffoldMessengerKey,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          unawaited(_navigatorKey.currentState?.maybePop());
        },
        child: Navigator(
          key: _navigatorKey,
          observers: [_routeObserver, BackKeySuppressorObserver()],
          onGenerateRoute: _onGenerateRoute,
        ),
      ),
    );
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    // This navigator's initial route is the profile shell. Content routes are
    // pushed imperatively from inside the shell, so named routes belong to the
    // root navigator unless this method is expanded intentionally.
    final routeName = settings.name;
    if (routeName != null && routeName != Navigator.defaultRouteName) {
      throw FlutterError('ProfileSessionNavigator does not handle named route "$routeName".');
    }

    return MaterialPageRoute<void>(
      settings: settings,
      builder: (context) =>
          widget.profileShellBuilder?.call(context) ??
          MainScreen(isOfflineMode: widget.isOfflineMode, initialPromptHandled: widget.initialPromptHandled),
    );
  }
}
