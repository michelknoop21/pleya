import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../i18n/strings.g.dart';
import '../media/ids.dart';
import '../profiles/active_profile_provider.dart';
import '../providers/multi_server_provider.dart';
import 'base_shared_preferences_service.dart';
import 'pleya_server_client.dart';

typedef PushChoices = ({bool movies, bool episodes});
typedef PushSource = ({String id, String name});

class PleyaPushNotifications extends ChangeNotifier with WidgetsBindingObserver {
  PleyaPushNotifications(this._profileId, this._profile, this._servers) {
    WidgetsBinding.instance.addObserver(this);
    _servers.addListener(_sync);
    _profile.addListener(_sync);
    _sync();
  }

  static const _channel = MethodChannel('com.pleya/push');
  static const off = (movies: false, episodes: false);

  final String _profileId;
  final ActiveProfileProvider _profile;
  final MultiServerProvider _servers;
  final _saved = <String, List<String>>{};
  final _synced = <String, PleyaServerClient>{};
  final _pending = <String>{};
  bool _disposed = false;
  bool _busy = false;
  bool _reconcileRequested = false;

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

  String get _prefix => 'pleya.push/${Uri.encodeComponent(_profileId)}/';
  String _key(String id) => '$_prefix${Uri.encodeComponent(id)}';

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
      if (enabling && existing != null && (existing.length == 2 || existing.contains('pending'))) {
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
      final removal = stored.take(2).toList();
      await prefs.setStringList(_key(connection), removal);
      _saved[connection] = removal;
      await client.removePushInstallation(stored.first);
      if (!_current) return;
      await prefs.remove(_key(connection));
      _saved.remove(connection);
    } else {
      final token = device['token'];
      final environment = device['environment'];
      if (token == null || environment == null) throw StateError('Missing push device identity');
      await client.registerPushInstallation(
        stored.first,
        token: token,
        environment: environment,
        locale: LocaleSettings.currentLocale.languageCode == 'nl' ? 'nl' : 'en',
        movies: selected.movies,
        episodes: selected.episodes,
      );
      if (!_current) return;
      if (stored.contains('pending')) {
        final confirmed = stored.where((value) => value != 'pending').toList();
        final prefs = await BaseSharedPreferencesService.sharedCache();
        if (!_current) return;
        await prefs.setStringList(_key(connection), confirmed);
        _saved[connection] = confirmed;
      }
    }
    _synced[connection] = client;
    _pending.remove(connection);
  }

  void retry() => _sync();

  void _sync() {
    if (!_current) return;
    final online = _online;
    _synced.removeWhere((id, client) => !identical(online[id], client));
    // Defer notifications until the profile and server bindings have settled.
    unawaited(Future<void>.microtask(_reconcile));
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
      for (final key in prefs.keys.where((key) => key.startsWith(_prefix))) {
        final stored = prefs.getStringList(key);
        if (stored == null || stored.length < 2) continue;
        final connection = Uri.decodeComponent(key.substring(_prefix.length));
        _saved[connection] = stored;
        final client = _online[connection];
        if (client == null) {
          if (stored.length == 2 || stored.contains('pending')) _pending.add(connection);
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
      _synced.clear();
      _sync();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _servers.removeListener(_sync);
    _profile.removeListener(_sync);
    super.dispose();
  }
}
