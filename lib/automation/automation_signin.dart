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

/// Polls for [rootNavigatorKey]'s context becoming available — the same
/// "polled, never a sleep" style [handleAutomationOpen] already uses for
/// screen readiness. `/v1/signin`/`/v1/connections/seed` run as the very
/// next setup step after `launch`, and `/v1/health` only proves the
/// automation HTTP server itself is bound, not that the widget tree has
/// painted its first frame — on iOS-sim that gap was wide enough for a
/// single unretried check to fail every run.
/// Loopback-only guard for every `base_url` this control plane accepts —
/// shared by [handleAutomationSignIn] and [handleAutomationConnectionsSeed]
/// so the two endpoints can never drift into two subtly different SSRF
/// boundaries. Pleya Verify's automation sign-in exists to reach the local
/// fixture server: `{{fixture}}` always resolves to a literal
/// `http://127.0.0.1:<port>` (see `resolvePlaceholders` in
/// `pleya_verify/runner/lib/src/engine/run_scenario.dart`), never a real
/// server anywhere else. Accepting an arbitrary caller-supplied origin here
/// would turn a loopback-only automation endpoint into an open proxy that
/// probes, logs into, and persists credentials against whatever URL it is
/// handed — including a LAN host, a cloud metadata service, or anything
/// else reachable from wherever the app happens to be running.
///
/// Checked before any network call or persistence happens, and deliberately
/// conservative: `http` only (never `https`, which nothing on this path
/// needs), and a literal loopback address, never a hostname — resolving
/// `localhost` still means trusting whatever `/etc/hosts` or the resolver
/// says, and a literal check has no such dependency. Returns an error
/// message when [rawUrl] is not an accepted loopback origin, `null` when it
/// is.
String? rejectNonLoopbackBaseUrl(String rawUrl) {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null) return '"$rawUrl" is not a valid URL';
  if (uri.scheme != 'http') {
    return 'base_url must be a plain http:// loopback address — got scheme "${uri.scheme}" ($rawUrl)';
  }
  if (uri.host != '127.0.0.1' && uri.host != '::1') {
    return 'base_url must point at a literal loopback address (127.0.0.1 or ::1) — got host "${uri.host}" ($rawUrl)';
  }
  if (!uri.hasPort || uri.port <= 0 || uri.port > 65535) {
    return 'base_url must include a valid port ($rawUrl)';
  }
  return null;
}

Future<BuildContext?> _waitForRootContext({Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) return context;
    if (DateTime.now().isAfter(deadline)) return null;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

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

  final String baseUrl;
  try {
    baseUrl = PleyaServerAuthService.normaliseBaseUrl(baseUrlInput);
  } on MediaServerException catch (e) {
    return {'ok': false, 'error': e.toString()};
  }
  final rejectedBaseUrl = rejectNonLoopbackBaseUrl(baseUrl);
  if (rejectedBaseUrl != null) return {'ok': false, 'error': rejectedBaseUrl};

  final context = await _waitForRootContext();
  if (context == null) {
    return {'ok': false, 'error': 'no root context available yet — the app has not finished booting'};
  }

  final auth = PleyaServerAuthService();
  try {
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
  final rejectedBaseUrl = rejectNonLoopbackBaseUrl(baseUrl);
  if (rejectedBaseUrl != null) return {'ok': false, 'error': rejectedBaseUrl};

  final context = await _waitForRootContext();
  if (context == null) {
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

  if (!context.mounted) return {'ok': false, 'error': 'context unmounted mid-signin'};
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
  final createdFirstProfile = boundProfile == null;
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

  // A real user reaches this exact state by tapping through AddPleyaServerScreen/
  // AddJellyfinScreen, which pop back into AuthScreen, and AuthScreen's own
  // handler pushes ProfileSessionScreen once the first profile is bound
  // (lib/screens/auth_screen.dart:182-184). This endpoint never goes through
  // that screen, so nothing else ever fires that transition — without this,
  // the app is left showing AuthScreen forever with a fully bound profile
  // underneath it. Routed through AutomationNavigationHooks rather than a
  // hardcoded `Navigator.pushReplacement(..., ProfileSessionScreen())` here:
  // that widget's full provider tree only exists in the real app, and a
  // no-op when nothing registered the hook (e.g. a narrower widget test)
  // beats a crash on an unmountable widget.
  if (createdFirstProfile) {
    AutomationNavigationHooks.instance.handoffToFirstProfile();
  }

  return {'ok': true, 'profileId': bindProfile.id, 'connectionId': connection.id};
}

/// The screens `/v1/open` reaches by selecting a nav tab.
///
/// `screen.main` is not in here because it needs no tab switch — it is the
/// always-mounted container. `screen.media_detail` is not in here either: it
/// needs an item id `/v1/open` does not accept yet, so it is rejected by name
/// rather than attempted. Screens that are pushed routes are in
/// [_routeScreens] and register an opener with
/// [AutomationNavigationHooks.registerRouteOpener] instead.
const Map<String, NavigationTabId> _screenToTab = {
  AutomationIds.screenDiscover: NavigationTabId.discover,
  // Series and Films are their own nav tabs and, since they got ids of their
  // own, their own openable screens. Without these two the shell would declare
  // three landings and let a scenario reach one.
  AutomationIds.screenSeries: NavigationTabId.series,
  AutomationIds.screenMovies: NavigationTabId.movies,
  AutomationIds.screenLibraries: NavigationTabId.libraries,
  // Boeken is reachable the same way, and has to be: the mobile bar is driven
  // by pointer taps, and `tap` only takes coordinates. Without this a scenario
  // could assert that the Boeken slot exists but never open what is behind it.
  AutomationIds.screenBooks: NavigationTabId.books,
};

/// The screens `/v1/open` reaches by asking the screen that owns the route to
/// push it, rather than by selecting a nav tab.
///
/// A closed list, and that is the whole point. `isRoute` used to be "anything
/// that is not a nav tab and not `screen.main`", so a misspelled or not-yet-
/// mapped id was silently treated as a route: `/v1/open` waited the full
/// `timeoutMs` for a screen nothing could ever push and answered
/// `timeout waiting for "X" to become ready`. That is the failure mode the
/// docstring above promises this endpoint does not have — `screen.media_detail`
/// is named there as the example of failing clearly rather than guessing, and
/// it was the first id to fall through the gap.
const Set<String> _routeScreens = {
  AutomationIds.screenAllBooks,
  AutomationIds.screenBooksFilters,
  AutomationIds.screenBooksSearch,
  AutomationIds.screenBookDetail,
  AutomationIds.screenBooksToc,
  AutomationIds.screenBookReader,
  AutomationIds.screenBookTextSearch,
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

  NavigationTabId? tab;
  // A screen is a nav tab, a route pushed by the screen that owns it, or
  // nothing this endpoint can reach. Alle boeken is the second kind: it hangs
  // off Boeken-home, so no tab selection reaches it.
  //
  // The third case is checked rather than assumed. Treating every unknown id
  // as a route meant a typo, or a screen with no opener like
  // `screen.media_detail`, waited out `timeoutMs` and came back with a
  // readiness timeout — a report that says the app was slow when the truth is
  // that nothing was ever going to push that screen.
  final isRoute = _routeScreens.contains(screen);
  if (screen != AutomationIds.screenMain && !isRoute && !_screenToTab.containsKey(screen)) {
    return {
      'ok': false,
      'error':
          'unsupported screen "$screen" — no nav-tab mapping and no route opener registered for it. '
          'Openable: ${[AutomationIds.screenMain, ..._screenToTab.keys, ..._routeScreens]..sort()}',
    };
  }
  if (screen != AutomationIds.screenMain && !isRoute) {
    tab = _screenToTab[screen];
    if (!AutomationNavigationHooks.instance.selectTab(tab!)) {
      return {'ok': false, 'error': 'MainScreen is not mounted to open a tab on'};
    }
  }
  var routeOpened = false;

  final timeoutMs = (body['timeoutMs'] as num?)?.toInt() ?? 5000;
  final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
  while (true) {
    final entry = AutomationScreenRegistry.instance.snapshot().firstWhereOrNull((s) => s['id'] == screen);
    if (entry != null && entry['ready'] == true) return {'ok': true, 'screen': screen};
    if (DateTime.now().isAfter(deadline))
      return {'ok': false, 'error': 'timeout waiting for "$screen" to become ready'};
    await Future<void>.delayed(const Duration(milliseconds: 100));
    // Ask again on every turn: a capability-gated destination (Boeken, Live
    // TV, Kijklijst) only becomes visible once its source has answered, which
    // can be after this call started.
    if (tab != null) AutomationNavigationHooks.instance.selectTab(tab);
    // A route is pushed exactly once, and the opener is what says whether that
    // happened. Retrying while it keeps answering `false` covers the owning
    // screen still mounting and the shelf not having answered yet; it cannot
    // stack duplicates, because `false` means nothing was pushed.
    //
    // Awaited, and that is the fix. The opener is a `Future<bool> Function()`
    // now: as a `VoidCallback` an async opener returned at its first `await`,
    // this flag went `true` before the lookup and before the push, and a bail
    // on `book == null` burned the only attempt while the loop sat out its
    // whole timeout.
    if (isRoute && !routeOpened) routeOpened = await AutomationNavigationHooks.instance.openRoute(screen);
  }
}
