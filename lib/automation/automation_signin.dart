import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../connection/connection.dart';
import '../exceptions/media_server_exceptions.dart';
import '../main.dart' show rootNavigatorKey;
import '../navigation/navigation_tabs.dart';
import '../navigation/profile_navigation_scope.dart';
import '../profiles/active_profile_binder.dart';
import '../profiles/active_profile_provider.dart';
import '../profiles/profile.dart';
import '../profiles/profile_connection.dart';
import '../profiles/profile_registry.dart';
import '../screens/settings/connection_persistence.dart';
import '../services/pleya_server_auth_service.dart';
import 'automation_ids.dart';
import 'automation_navigation_hooks.dart';
import 'automation_screen.dart';

/// `POST /v1/signin` body: `{"base_url", "username", "password",
/// "setup_code"?}`. Drives the exact chain
/// `lib/screens/settings/add_pleya_server_screen.dart`'s `_submit()`/
/// `_persist()` use — probe -> login/setup (the server's own
/// `auth.setup_required` decides which) -> persist -> bind, creating the
/// first local profile when none is active yet. No second connection
/// architecture: same [PleyaServerAuthService], same
/// [persistAndBindConnection].
///
/// Uses [rootNavigatorKey]'s context, not `profileNavigationRegistry`'s:
/// this can run *before* any profile session exists (it may create the very
/// first one), and `profileNavigationRegistry` only attaches once a profile
/// session is mounted. Same seam `main.dart`'s `_rootPinPrompt` already uses
/// for exactly that reason.
Future<Map<String, Object?>> handleAutomationSignIn(Map<String, Object?> body) async {
  final baseUrlInput = body['base_url'] as String?;
  final username = body['username'] as String?;
  final password = body['password'] as String?;
  if (baseUrlInput == null || username == null || password == null) {
    return {'ok': false, 'error': 'base_url, username and password are required'};
  }

  final context = rootNavigatorKey.currentContext;
  if (context == null || !context.mounted) {
    return {'ok': false, 'error': 'no root context available yet — the app has not finished booting'};
  }

  final auth = PleyaServerAuthService();
  try {
    final baseUrl = PleyaServerAuthService.normaliseBaseUrl(baseUrlInput);
    final info = await auth.probe(baseUrl);
    final authResult = info.auth.setupRequired
        ? await auth.completeSetup(
            baseUrl: baseUrl,
            setupCode: body['setup_code'] as String? ?? '',
            username: username,
            password: password,
          )
        : await auth.login(baseUrl: baseUrl, username: username, password: password);

    final detail = await auth.fetchServerDetail(baseUrl: baseUrl, accessToken: authResult.tokens.accessToken);
    if (!context.mounted) return {'ok': false, 'error': 'context unmounted mid-signin'};

    final connection = PleyaServerConnection(
      id: 'pleyaServer.${authResult.info.serverId}',
      baseUrl: baseUrl,
      serverId: authResult.info.serverId,
      serverName: detail?.name.isNotEmpty == true ? detail!.name : 'Pleya Server',
      userName: authResult.userName,
      refreshToken: authResult.tokens.refreshToken,
      status: ConnectionStatus.online,
      createdAt: DateTime.now(),
      lastAuthenticatedAt: DateTime.now(),
    );

    return await _persistConnectionAndBindProfile(context, connection);
  } on MediaServerException catch (e) {
    return {'ok': false, 'error': e.toString()};
  }
}

/// `POST /v1/connections/seed` body: `{"base_url", "server_id",
/// "server_name", "user_name", "refresh_token"}`. The fast path for a
/// scenario that only needs *a* connection to exist and doesn't care to
/// re-prove the sign-in UI on every run: skips the probe/login HTTP round
/// trip and persists a [PleyaServerConnection] built straight from the
/// caller's own knowledge of the fixture it already seeded. Shares
/// [_persistConnectionAndBindProfile] with `/v1/signin` — the two endpoints
/// differ only in how the connection gets built, not in what happens to it
/// afterward.
Future<Map<String, Object?>> handleAutomationConnectionsSeed(Map<String, Object?> body) async {
  final baseUrl = body['base_url'] as String?;
  final serverId = body['server_id'] as String?;
  final serverName = body['server_name'] as String?;
  final userName = body['user_name'] as String?;
  final refreshToken = body['refresh_token'] as String?;
  if (baseUrl == null || serverId == null || serverName == null || userName == null || refreshToken == null) {
    return {'ok': false, 'error': 'base_url, server_id, server_name, user_name and refresh_token are required'};
  }

  final context = rootNavigatorKey.currentContext;
  if (context == null || !context.mounted) {
    return {'ok': false, 'error': 'no root context available yet — the app has not finished booting'};
  }

  final connection = PleyaServerConnection(
    id: 'pleyaServer.$serverId',
    baseUrl: baseUrl,
    serverId: serverId,
    serverName: serverName,
    userName: userName,
    refreshToken: refreshToken,
    status: ConnectionStatus.online,
    createdAt: DateTime.now(),
    lastAuthenticatedAt: DateTime.now(),
  );

  return _persistConnectionAndBindProfile(context, connection);
}

/// Shared tail of `/v1/signin` and `/v1/connections/seed`: persist
/// [connection], creating the first local profile if none is active yet
/// (mirrors `add_pleya_server_screen.dart`'s `_persist()`), then
/// `rebindIfActive` when the newly bound profile is the active one.
Future<Map<String, Object?>> _persistConnectionAndBindProfile(
  BuildContext context,
  PleyaServerConnection connection,
) async {
  final activeProvider = context.read<ActiveProfileProvider>();
  await activeProvider.initialize();
  if (!context.mounted) return {'ok': false, 'error': 'context unmounted mid-signin'};

  var boundProfile = activeProvider.active;
  if (boundProfile == null) {
    final now = DateTime.now();
    final profile = Profile.local(
      id: 'local-${const Uuid().v4()}',
      displayName: connection.userName.isNotEmpty ? connection.userName : connection.serverName,
      sortOrder: now.millisecondsSinceEpoch,
      createdAt: now,
    );
    await context.read<ProfileRegistry>().upsert(profile);
    await activeProvider.activate(profile);
    if (!context.mounted) return {'ok': false, 'error': 'context unmounted mid-signin'};
    boundProfile = activeProvider.active ?? profile;
  }

  final bindProfile = boundProfile;
  final boundToActive = bindProfile.id == activeProvider.activeId;

  await persistAndBindConnection(
    context: context,
    connection: connection,
    bindToProfile: ProfileConnection(
      profileId: bindProfile.id,
      connectionId: connection.id,
      // The refresh token is the only credential there is; the access token
      // is minted per session and would be stale before the next launch.
      userToken: connection.refreshToken,
      userIdentifier: connection.serverId,
      tokenAcquiredAt: DateTime.now(),
    ),
    addToManager: null,
  );

  if (!context.mounted) return {'ok': false, 'error': 'context unmounted mid-signin'};
  if (boundToActive) {
    await context.read<ActiveProfileBinder>().rebindIfActive(bindProfile.id);
  }

  return {'ok': true, 'profileId': bindProfile.id, 'connectionId': connection.id};
}

/// The only screens `/v1/open` currently knows how to reach a
/// [NavigationTabId] for — `screen.main` needs no tab switch (it's the
/// always-mounted container), and `screen.media_detail` needs an item id
/// `/v1/open` doesn't accept yet, so it fails clearly rather than guessing.
const Map<String, NavigationTabId> _screenToTab = {
  AutomationIds.screenDiscover: NavigationTabId.discover,
  AutomationIds.screenLibraries: NavigationTabId.libraries,
};

/// `POST /v1/open` body: `{"screen": "screen.discover", "timeoutMs"?}`.
/// Drives [AutomationNavigationHooks] — the exact `_selectTab` the sidebar's
/// own tab bar calls, not a second navigation path — then waits for that
/// screen's `AutomationScreen` to report ready via
/// [AutomationScreenRegistry] (polled, matching `AutomationWait`'s style —
/// never a sleep).
///
/// Uses `profileNavigationRegistry`'s context, not [rootNavigatorKey]'s: that
/// registry only attaches once a profile session is mounted
/// (`profile_session_screen.dart`), which is exactly the precondition for
/// "open a screen inside the app" to mean anything — before that, this fails
/// with a clear error instead of pushing on a null/wrong navigator.
Future<Map<String, Object?>> handleAutomationOpen(Map<String, Object?> body) async {
  final screen = body['screen'] as String?;
  if (screen == null) return {'ok': false, 'error': 'screen is required'};

  final context = profileNavigationRegistry.navigator?.context;
  if (context == null || !context.mounted) {
    return {'ok': false, 'error': 'no profile session is mounted yet — sign in first'};
  }

  if (screen != AutomationIds.screenMain) {
    final tab = _screenToTab[screen];
    if (tab == null) {
      return {'ok': false, 'error': 'unsupported screen "$screen" — no nav-tab mapping registered for it yet'};
    }
    if (!AutomationNavigationHooks.instance.selectTab(tab)) {
      return {'ok': false, 'error': 'MainScreen is not mounted to open a tab on'};
    }
  }

  final timeoutMs = (body['timeoutMs'] as num?)?.toInt() ?? 5000;
  final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
  while (true) {
    final entry = AutomationScreenRegistry.instance.snapshot().firstWhereOrNull((s) => s['id'] == screen);
    if (entry != null && entry['ready'] == true) return {'ok': true, 'screen': screen};
    if (DateTime.now().isAfter(deadline))
      return {'ok': false, 'error': 'timeout waiting for "$screen" to become ready'};
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
