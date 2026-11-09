import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../connection/connection.dart';
import '../i18n/strings.g.dart';
import '../media/ids.dart';
import '../profiles/active_profile_provider.dart';
import '../providers/multi_server_provider.dart';
import 'base_shared_preferences_service.dart';
import 'multi_server_manager.dart';
import 'pleya_server_client.dart';

typedef PushChoices = ({bool movies, bool episodes});
typedef PushSource = ({String id, String name});

/// Reaches a Pleya session for a withdrawal: its bound client when there is
/// one, otherwise a short-lived client for that connection.
typedef PushReach =
    Future<void> Function(PleyaServerConnection connection, Future<void> Function(PleyaServerClient client) action);

/// Opt-in push per profile and Pleya Server account, kept convergent.
///
/// The only stored state is each profile's choice per connection plus the
/// installation id its PUT uses. From that and the active profile follows,
/// for every Pleya session the device knows (every Pleya connection in the
/// registry, across profiles), what the server should hold:
///
/// - the session belongs to the active profile and that profile opted in
///   there: one registration with its categories;
/// - anything else: nothing, which the session-wide DELETE achieves.
///
/// Reconciling writes that state, one run per session at a time; a request
/// during a run starts one more run after it. It runs at the start, on
/// resume, when a server comes online, on a profile switch, after a change
/// of choices, and on a growing pause while an attempt fails. A session whose
/// last confirmed state still matches is skipped between those moments, but
/// not at the start or on resume.
class PleyaPushNotifications extends ChangeNotifier with WidgetsBindingObserver {
  /// [sessions] lists every Pleya connection the device knows; [profileSessions]
  /// the ones bound to a profile. [retryBackoff] is the first pause before a
  /// failed attempt runs again; it doubles up to ten minutes.
  PleyaPushNotifications(
    this._profileId,
    this._profile,
    this._servers, {
    required this.sessions,
    required this.profileSessions,
    required this.reach,
    this.retryBackoff = const Duration(seconds: 30),
  }) {
    WidgetsBinding.instance.addObserver(this);
    _servers.addListener(_onChange);
    _profile.addListener(_onChange);
    _confirmed.clear();
    _failed.clear();
    _onChange();
  }

  @visibleForTesting
  static void resetForTesting() {
    _active = null;
    _running.clear();
    _again.clear();
    _confirmed.clear();
    _failed.clear();
  }

  static const _channel = MethodChannel('com.pleya/push');
  static const off = (movies: false, episodes: false);

  final String _profileId;
  final ActiveProfileProvider _profile;
  final MultiServerProvider _servers;
  final Future<List<PleyaServerConnection>> Function() sessions;
  final Future<Set<String>> Function(String profileId) profileSessions;
  final PushReach reach;
  final Duration retryBackoff;
  final _saved = <String, List<String>>{};
  bool _disposed = false;
  bool _busy = false;
  Duration? _nextBackoff;
  Timer? _retryTimer;
  Set<String> _onlineSeen = const {};
  ({String? active, bool binding})? _profileSeen;

  // Device-wide: one push state per session, whatever instance asks.
  static PleyaPushNotifications? _active;
  static final _running = <String, Future<void>>{};
  static final _again = <String>{};
  static final _confirmed = <String, String>{};
  static final _failed = <String>{};

  bool get busy => _busy;

  bool get _owns => !_disposed && _profile.activeId == _profileId;

  bool get _current => _owns && !_profile.isBinding;

  Map<String, PleyaServerClient> get _online => {
    if (_current)
      for (final id in _servers.onlineServerIds)
        if (_servers.getClientForServer(ServerId(id)) case final PleyaServerClient client)
          if (client.connection.accountUserId != null) client.connection.id: client,
  };

  List<PushSource> get sources => [
    if (_current)
      for (final entry in _saved.entries) (id: entry.key, name: entry.value[1]),
    for (final entry in _online.entries)
      if (entry.value.supportsSecurePush && !_saved.containsKey(entry.key))
        (id: entry.key, name: entry.value.connection.displayName),
  ];

  PushChoices choices(PushSource source) {
    final stored = _saved[source.id]?.skip(2);
    return stored == null ? off : (movies: stored.contains('movies'), episodes: stored.contains('episodes'));
  }

  bool available(PushSource source) => _online[source.id]?.supportsSecurePush == true;

  /// The server does not hold what this choice asks for yet.
  bool pending(PushSource source) => _failed.contains(source.id);

  bool canRetry(PushSource source) => _online.containsKey(source.id) && pending(source);

  /// The server registers one installation per device token, so on one server
  /// only one account of this profile can get push. Returns the name of the
  /// other account that gets it now, which turning [source] on switches off.
  String? sharedWith(PushSource source) {
    if (choices(source) != off) return null;
    final server = _serverOf(source.id);
    for (final other in sources) {
      if (other.id != source.id && _serverOf(other.id) == server && choices(other) != off) return other.name;
    }
    return null;
  }

  /// Connection ids are `pleyaServer.<serverId>.<account>`; push only runs on
  /// connections with an account part, so dropping that part names the server.
  static String _serverOf(String connectionId) =>
      connectionId.substring(0, connectionId.lastIndexOf('.').clamp(0, connectionId.length));

  static const _root = 'pleya.push/';
  static String _prefixFor(String profileId) => '$_root${Uri.encodeComponent(profileId)}/';
  static String _keyFor(String profileId, String connectionId) =>
      '${_prefixFor(profileId)}${Uri.encodeComponent(connectionId)}';
  String _key(String connectionId) => _keyFor(_profileId, connectionId);

  /// Every installation id any profile stored for [connectionId]: the fallback
  /// for a server without the session-wide DELETE.
  static Future<List<String>> knownIdsFor(String connectionId) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final suffix = '/${Uri.encodeComponent(connectionId)}';
    return [
      for (final key in prefs.keys)
        if (key.startsWith(_root) && key.endsWith(suffix)) ?prefs.getStringList(key)?.firstOrNull,
    ];
  }

  /// A connection leaves [profileId]: its choice goes. A session another
  /// profile still uses stays known, and the next reconcile empties it unless
  /// the active profile opted in there. The last reference is withdrawn and
  /// logged out by the caller before the connection row goes.
  static Future<void> forgetConnection(String profileId, String connectionId) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.remove(_keyFor(profileId, connectionId));
    _confirmed.remove(connectionId);
    _active?._reconcileAll();
  }

  /// App-wide sign-out: every Pleya session withdraws its push and ends,
  /// each capped like any other withdrawal, and every stored choice goes.
  static Future<void> signOut(List<PleyaServerConnection> connections, MultiServerManager servers) async {
    await Future.wait([
      for (final connection in connections)
        () async {
          try {
            final ids = await knownIdsFor(connection.id);
            await servers
                .withPleyaServerClient(connection, persist: false, (client) async {
                  await client.withdrawPush(knownIds: ids);
                  await client.logout();
                })
                .timeout(const Duration(seconds: 5));
          } catch (_) {
            // Offline: the session lapses with the server's session sweep.
          }
        }(),
    ]);
    final prefs = await BaseSharedPreferencesService.sharedCache();
    for (final key in prefs.keys.where((key) => key.startsWith(_root)).toList()) {
      await prefs.remove(key);
    }
    _confirmed.clear();
    _failed.clear();
  }

  Future<Map<String, String>?> _token({required bool prompt}) =>
      _channel.invokeMapMethod<String, String>('deviceToken', prompt);

  Future<void> setChoices(PushSource source, PushChoices next) async {
    if (_busy || !_current || !sources.contains(source)) return;
    final old = choices(source);
    final enabling = (next.movies && !old.movies) || (next.episodes && !old.episodes);
    if (enabling && !available(source)) return;
    _busy = true;
    notifyListeners();
    final connection = source.id;
    try {
      if (enabling && await _token(prompt: true) == null) return;
      if (!_current) return;
      final prefs = await BaseSharedPreferencesService.sharedCache();
      if (next == off) {
        await prefs.remove(_key(connection));
        _saved.remove(connection);
      } else {
        final id = _saved[connection]?.firstOrNull ?? const Uuid().v4();
        final stored = [id, source.name, if (next.movies) 'movies', if (next.episodes) 'episodes'];
        await prefs.setStringList(_key(connection), stored);
        _saved[connection] = stored;
      }
      _confirmed.remove(connection);
      final touched = {connection};
      if (enabling) {
        // The server keeps one installation per token: the other account of
        // this profile on the same server loses push, so its choice goes too.
        for (final other in _saved.keys.toList()) {
          if (other == connection || _serverOf(other) != _serverOf(connection)) continue;
          _saved.remove(other);
          await prefs.remove(_key(other));
          _confirmed.remove(other);
          touched.add(other);
        }
      }
      // Only the sessions this change touches: a slow unrelated server does
      // not hold the switches.
      await _reconcileAll(only: touched);
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  void retry() => unawaited(_reconcileAll());

  void _onChange() {
    if (_disposed) return;
    if (_owns) {
      _active = this;
    } else if (identical(_active, this)) {
      _active = null;
    }
    // Only a new reason reconciles: a server coming online, a profile switch
    // or a bind ending. Other notifications would retry a failure every time.
    final online = _servers.onlineServerIds.toSet();
    final profile = (active: _profile.activeId, binding: _profile.isBinding);
    final cause = !_onlineSeen.containsAll(online) || profile != _profileSeen;
    _onlineSeen = online;
    _profileSeen = profile;
    if (cause && _owns) unawaited(Future<void>.microtask(_reconcileAll));
  }

  Future<void> _reconcileAll({Set<String>? only}) async {
    if (!_owns) return;
    try {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      if (!_owns) return;
      _saved
        ..clear()
        ..addAll({
          for (final key in prefs.keys.where((key) => key.startsWith(_prefixFor(_profileId))))
            if (prefs.getStringList(key) case final stored? when stored.length > 2)
              Uri.decodeComponent(key.substring(_prefixFor(_profileId).length)): stored,
        });
      final known = await sessions();
      await Future.wait([
        for (final connection in known)
          if (only == null || only.contains(connection.id)) _schedule(connection),
      ]);
    } catch (_) {
      _retryLater();
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  /// One run per session at a time; a request during a run starts one more.
  static Future<void> _schedule(PleyaServerConnection connection) {
    final id = connection.id;
    final running = _running[id];
    if (running != null) {
      _again.add(id);
      return running;
    }
    late final Future<void> run;
    run = () async {
      try {
        do {
          _again.remove(id);
          await _converge(connection);
        } while (_again.contains(id));
      } finally {
        if (identical(_running[id], run)) _running.remove(id);
      }
    }();
    _running[id] = run;
    return run;
  }

  static Future<void> _converge(PleyaServerConnection connection) async {
    final owner = _active;
    if (owner == null) return;
    final id = connection.id;
    try {
      final mine = (await owner.profileSessions(owner._profileId)).contains(id);
      // The binder holds this session's token right now: its bound client
      // comes, and the end of the bind reconciles again.
      if (mine && owner._profile.isBinding) return;
      final prefs = await BaseSharedPreferencesService.sharedCache();
      final stored = mine ? prefs.getStringList(owner._key(id)) : null;
      final wanted = stored != null && stored.length > 2 && owner._owns ? stored : null;
      final device = wanted == null ? null : await owner._token(prompt: false);
      final put = wanted != null && device != null;
      final state = put ? 'put:${wanted.join(',')}' : 'clear';
      if (_confirmed[id] == state) return;
      if (put) {
        final client = owner._online[id];
        if (client == null) {
          // Offline or not bound: a server coming online reconciles again.
          _failed.add(id);
          return;
        }
        final token = device['token'];
        final environment = device['environment'];
        if (token == null || environment == null) throw StateError('Missing push device identity');
        await client.registerPushInstallation(
          wanted.first,
          token: token,
          environment: environment,
          locale: LocaleSettings.currentLocale.languageCode == 'nl' ? 'nl' : 'en',
          movies: wanted.contains('movies'),
          episodes: wanted.contains('episodes'),
        );
      } else {
        final ids = await knownIdsFor(id);
        await owner.reach(connection, (client) => client.withdrawPush(knownIds: ids));
      }
      _confirmed[id] = state;
      _failed.remove(id);
      owner._nextBackoff = null;
    } catch (_) {
      _confirmed.remove(id);
      _failed.add(id);
      owner._retryLater();
    }
  }

  /// A failed attempt runs again after a growing pause, capped at ten minutes.
  void _retryLater() {
    if (_disposed || (_retryTimer?.isActive ?? false)) return;
    final wait = _nextBackoff ?? retryBackoff;
    final doubled = wait * 2;
    _nextBackoff = doubled > const Duration(minutes: 10) ? const Duration(minutes: 10) : doubled;
    _retryTimer = Timer(wait, _reconcileAll);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _owns) {
      _confirmed.clear();
      unawaited(_reconcileAll());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (identical(_active, this)) _active = null;
    _retryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _servers.removeListener(_onChange);
    _profile.removeListener(_onChange);
    super.dispose();
  }
}
