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
import 'pleya_server_auth_service.dart';
import 'pleya_server_client.dart';

typedef PushChoices = ({bool movies, bool episodes});
typedef PushSource = ({String id, String name});

class PleyaPushNotifications extends ChangeNotifier with WidgetsBindingObserver {
  /// [releaseElsewhere] withdraws another profile's push through that
  /// profile's own connection; the device belongs to the active profile.
  /// [retryBackoff] is the first wait before a failed withdrawal is tried
  /// again without a resume or a server coming online; it doubles up to ten
  /// minutes.
  PleyaPushNotifications(
    this._profileId,
    this._profile,
    this._servers, {
    this.releaseElsewhere,
    this.retryBackoff = const Duration(seconds: 30),
  }) {
    WidgetsBinding.instance.addObserver(this);
    _servers.addListener(_sync);
    _profile.addListener(_sync);
    _withdrawn = _withdrawals.stream.listen(_afterWithdrawal);
    _sync();
  }

  static const _channel = MethodChannel('com.pleya/push');
  static const off = (movies: false, episodes: false);

  final String _profileId;
  final ActiveProfileProvider _profile;
  final MultiServerProvider _servers;
  final Future<void> Function(String connectionId, String installationId)? releaseElsewhere;
  final Duration retryBackoff;
  Duration? _nextBackoff;
  Timer? _retryTimer;
  late final StreamSubscription<String> _withdrawn;
  final _saved = <String, List<String>>{};
  final _synced = <String, PleyaServerClient>{};
  final _pending = <String>{};
  bool _disposed = false;
  bool _busy = false;
  bool _reconcileRequested = false;
  final _releasing = <String>{};
  // Withdrawals that failed are tried again when there is reason to expect
  // a different answer: at the start, on resume, or when a server comes
  // online. Not on every notification, which would rotate a short-lived
  // client's token each time.
  bool _withdrawalsDue = true;
  Set<String> _onlineSeen = const {};

  bool get busy => _busy;

  bool get _current => !_disposed && !_profile.isBinding && _profile.activeId == _profileId;

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

  bool pending(PushSource source) => _pending.contains(source.id);

  bool canRetry(PushSource source) => _online.containsKey(source.id) && _saved.containsKey(source.id);

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

  /// The [releaseElsewhere] the app uses: through the other profile's own
  /// stored connection, and not at all while the app knows it is offline,
  /// where a short-lived client only spends time before failing. A connection
  /// the active profile also uses only goes through its bound client, so no
  /// second client rotates the refresh token the binding holds.
  static Future<void> Function(String connectionId, String installationId) releaseThrough({
    required Future<Connection?> Function(String id) connection,
    required MultiServerManager servers,
    required bool Function() offline,
    required Future<bool> Function(String connectionId) sharedWithActive,
  }) => (connectionId, installation) async {
    if (offline()) throw StateError('Offline: withdrawal waits for the network');
    if (await connection(connectionId) case final PleyaServerConnection stored) {
      await servers.withPleyaServerClient(
        stored,
        (client) => client.withdrawPush(knownId: installation),
        boundOnly: await sharedWithActive(connectionId),
      );
    }
  };

  static String _prefixFor(String profileId) => 'pleya.push/${Uri.encodeComponent(profileId)}/';
  String get _prefix => _prefixFor(_profileId);
  String _key(String id) => '$_prefix${Uri.encodeComponent(id)}';

  /// Withdraws [profileId]'s push opt-in for a connection that is being
  /// removed. [withdraw] gets the stored installation id (null when there is
  /// none) as the fallback for an older server, and talks to the server; it is
  /// best effort and capped, so removing the connection never waits on the
  /// network for long. The opt-in goes either way.
  static Future<void> forgetConnection(
    String profileId,
    String connectionId,
    Future<void> Function(String? knownId) withdraw,
  ) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final key = '${_prefixFor(profileId)}${Uri.encodeComponent(connectionId)}';
    final stored = prefs.getStringList(key);
    try {
      final withdrawal = withdraw(stored?.first);
      _track(connectionId, withdrawal);
      await withdrawal.timeout(const Duration(seconds: 5));
    } on PleyaClientNotBoundException {
      // Only the bound client may withdraw here, and it is not there yet (just
      // after a cold start). Keep it as a pending opt-out so a later reconcile
      // withdraws it, instead of forgetting an installation the server keeps.
      if (stored != null) {
        await prefs.setStringList(key, _asOptOut(stored));
        return;
      }
    } catch (_) {
      // Offline or already closed: the local opt-in still goes.
    }
    await prefs.remove(key);
  }

  static const _released = 'released';

  /// No category left: what remains is a withdrawal still to make.
  static bool _isOptOut(List<String> stored) =>
      !stored.skip(2).contains('movies') && !stored.skip(2).contains('episodes');

  static List<String> _asOptOut(List<String> stored) => stored.take(2).toList();

  /// A withdrawal is session-wide: it also removes a registration that was
  /// made on the same connection while it was on its way (another profile on
  /// a shared connection, or this one coming back). Every finished withdrawal
  /// is announced per connection, and a live opt-in there registers again.
  static final _withdrawals = StreamController<String>.broadcast(sync: true);

  static void _track(String connection, Future<void> withdrawal) {
    withdrawal.then<void>((_) {}, onError: (Object _) {}).whenComplete(() => _withdrawals.add(connection)).ignore();
  }

  void _afterWithdrawal(String connection) {
    final stored = _saved[connection];
    if (!_current || stored == null || _isOptOut(stored) || !_synced.containsKey(connection)) return;
    _synced.remove(connection);
    _sync();
  }

  /// Pleya itself said the session is gone: a 401 or 403 with an `auth.*`
  /// code, or a revoked refresh chain. The server then has dropped the
  /// installation. A bare status from a proxy or captive portal proves nothing
  /// and is retried. (A server without push routes answers the DELETE with
  /// `library.not_found`; [PleyaServerClient.withdrawPush] treats that
  /// as done.)
  static bool _settled(Object error) =>
      error is PleyaRefreshChainRevokedException || error is PleyaAuthRejectedException;

  /// After a confirmed withdrawal: an opt-out is done and goes, an opt-in stays
  /// stored so it returns with its profile, but needs no further withdrawal.
  static Future<void> _markReleased(String key, String installation) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final stored = prefs.getStringList(key);
    if (stored == null || stored.first != installation || stored.contains(_released)) return;
    if (_isOptOut(stored)) return prefs.remove(key);
    await prefs.setStringList(key, [...stored, _released]);
  }

  static Future<void> _unmarkReleased(String key, String installation) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final stored = prefs.getStringList(key);
    if (stored == null || stored.first != installation || !stored.contains(_released)) return;
    await prefs.setStringList(key, stored.where((value) => value != _released).toList());
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
      final prefs = await BaseSharedPreferencesService.sharedCache();
      final existing = _saved[connection];
      final id = existing?.firstOrNull ?? const Uuid().v4();
      final token = enabling ? await _token(prompt: true) : null;
      if (!_current) return;
      if (enabling && token == null) throw StateError('Push permission denied');
      final client = _online[connection];
      if (enabling && existing != null && (_isOptOut(existing) || existing.contains('pending'))) {
        if (client == null) throw StateError('Pending opt-out requires connection');
        await _applyStored(client, existing, token: token);
        if (!_current || !identical(_online[connection], client)) return;
      }
      final stored = [id, source.name, if (next.movies) 'movies', if (next.episodes) 'episodes', 'pending'];
      await prefs.setStringList(_key(connection), stored);
      _saved[connection] = stored;
      _synced.remove(connection);
      _pending.add(connection);
      final connected = _online[connection];
      if (connected != null) await _applyStored(connected, stored, token: token);
      if (enabling && !_pending.contains(connection) && _current) {
        // The server already moved the token here; the other account's opt-in
        // on this server is gone, so the screen must not show it as on.
        for (final other in _saved.keys.toList()) {
          if (other == connection || _serverOf(other) != _serverOf(connection)) continue;
          _saved.remove(other);
          _pending.remove(other);
          await prefs.remove(_key(other));
        }
      }
    } catch (_) {
      _pending.add(connection);
    } finally {
      _finish();
    }
  }

  Future<void> _applyStored(PleyaServerClient client, List<String> stored, {Map<String, String>? token}) async {
    final connection = client.connection.id;
    final source = (id: connection, name: stored[1]);
    final selected = choices(source);
    final device = selected.movies || selected.episodes ? token ?? await _token(prompt: false) : null;
    if (!_current || !identical(_online[connection], client)) return;
    if (device == null) {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      if (!_current || !identical(_online[connection], client)) return;
      final removal = _asOptOut(stored);
      await prefs.setStringList(_key(connection), removal);
      _saved[connection] = removal;
      final withdrawal = client.withdrawPush(knownId: stored.first);
      _track(connection, withdrawal);
      await withdrawal;
      if (!_current) return;
      await prefs.remove(_key(connection));
      _saved.remove(connection);
    } else {
      final token = device['token'];
      final environment = device['environment'];
      if (token == null || environment == null) throw StateError('Missing push device identity');
      final installation = stored.first;
      await client.registerPushInstallation(
        installation,
        token: token,
        environment: environment,
        locale: LocaleSettings.currentLocale.languageCode == 'nl' ? 'nl' : 'en',
        movies: selected.movies,
        episodes: selected.episodes,
      );
      if (_profile.activeId != _profileId) {
        // The profile changed while this PUT was in flight: the device now
        // belongs to another profile, so withdraw it again right away.
        // Another profile's start may already have marked this key released,
        // from a DELETE that came before this registration. Only this DELETE
        // counts now; if it fails, the key stays open for the next attempt.
        final key = _key(connection);
        _track(
          connection,
          _unmarkReleased(
            key,
            installation,
          ).then((_) => client.withdrawPush(knownId: installation)).then((_) => _markReleased(key, installation)),
        );
        return;
      }
      if (!_current) return;
      // Read again: a withdrawal that finished before this PUT may have marked
      // the stored opt-in as released.
      final prefs = await BaseSharedPreferencesService.sharedCache();
      if (!_current) return;
      final latest = prefs.getStringList(_key(connection)) ?? stored;
      if (latest.first == installation && (latest.contains('pending') || latest.contains(_released))) {
        final confirmed = latest.where((value) => value != 'pending' && value != _released).toList();
        await prefs.setStringList(_key(connection), confirmed);
        _saved[connection] = confirmed;
      }
    }
    _synced[connection] = client;
    _pending.remove(connection);
  }

  void retry() => _sync();

  void _sync() {
    if (_profile.activeId != _profileId) return _release();
    if (!_current) return;
    final onlineNow = _servers.onlineServerIds.toSet();
    if (!_onlineSeen.containsAll(onlineNow)) _withdrawalsDue = true;
    _onlineSeen = onlineNow;
    final online = _online;
    _synced.removeWhere((id, client) => !identical(online[id], client));
    // Defer notifications until the profile and server bindings have settled.
    unawaited(Future<void>.microtask(_reconcile));
  }

  /// A shared device belongs to the active profile. Leaving it withdraws this
  /// profile's installations so another profile never gets its alerts; the
  /// stored choices stay and are registered again when this profile returns.
  void _release() {
    for (final MapEntry(key: connection, value: client) in _synced.entries) {
      final stored = _saved[connection];
      if (stored == null) continue;
      final key = _key(connection);
      _track(connection, client.withdrawPush(knownId: stored.first).then((_) => _markReleased(key, stored.first)));
    }
    _synced.clear();
  }

  Future<void> _reconcile() async {
    if (!_current) return;
    if (_busy) {
      _reconcileRequested = true;
      return;
    }
    _busy = true;
    try {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      if (!_current) return;
      // A removed connection takes its stored opt-in with it.
      _saved.removeWhere((connection, _) => !prefs.containsKey(_key(connection)));
      // Other profiles' installations on this device: covers a cold start here
      // after another profile was active and a release on switch that did not
      // reach the server. A passing failure stays unmarked and is retried on
      // the next reconcile (resume, a server coming online); success or a
      // settled answer marks it so the next start does not withdraw it again.
      // Only once the binder has settled on this profile: binding the active
      // servers comes first and never waits on this.
      final release = releaseElsewhere != null && _withdrawalsDue && _profile.settledProfileId == _profileId
          ? releaseElsewhere
          : null;
      if (release != null) _withdrawalsDue = false;
      // This profile's own pending opt-outs for a connection it can no longer
      // reach through a bound client (it was removed before the binding
      // came up) go the same way.
      for (final key in prefs.keys.where((key) => key.startsWith('pleya.push/'))) {
        final stored = prefs.getStringList(key);
        if (release == null || stored == null || stored.length < 2 || stored.contains(_released)) continue;
        final connection = Uri.decodeComponent(key.substring(key.lastIndexOf('/') + 1));
        if (key.startsWith(_prefix) && (!_isOptOut(stored) || _online.containsKey(connection))) continue;
        if (!_releasing.add(key)) continue;
        Future<void> attempt() async {
          try {
            await release(connection, stored.first);
          } catch (error) {
            if (!_settled(error)) return _retryLater();
          }
          _nextBackoff = null;
          await _markReleased(key, stored.first);
        }

        _track(connection, attempt().whenComplete(() => _releasing.remove(key)));
      }
      for (final key in prefs.keys.where((key) => key.startsWith(_prefix))) {
        final stored = prefs.getStringList(key);
        if (stored == null || stored.length < 2) continue;
        final connection = Uri.decodeComponent(key.substring(_prefix.length));
        _saved[connection] = stored;
        final client = _online[connection];
        if (client == null) {
          if (_isOptOut(stored) || stored.contains('pending')) _pending.add(connection);
          continue;
        }
        if (identical(_synced[connection], client)) continue;
        try {
          await _applyStored(client, stored);
        } catch (_) {
          _pending.add(connection);
        }
      }
    } catch (_) {
      // Preference storage can be unavailable during startup.
    } finally {
      _finish();
    }
  }

  /// A withdrawal that failed while the servers stayed online is not retried
  /// on every notification, but after a growing pause, capped at ten minutes.
  void _retryLater() {
    if (_disposed || (_retryTimer?.isActive ?? false)) return;
    final wait = _nextBackoff ?? retryBackoff;
    final doubled = wait * 2;
    _nextBackoff = doubled > const Duration(minutes: 10) ? const Duration(minutes: 10) : doubled;
    _retryTimer = Timer(wait, () {
      _withdrawalsDue = true;
      _sync();
    });
  }

  void _finish() {
    _busy = false;
    if (!_disposed) notifyListeners();
    if (_reconcileRequested) {
      _reconcileRequested = false;
      _sync();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _withdrawalsDue = true;
      _synced.clear();
      _sync();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _withdrawn.cancel().ignore();
    WidgetsBinding.instance.removeObserver(this);
    _servers.removeListener(_sync);
    _profile.removeListener(_sync);
    super.dispose();
  }
}
