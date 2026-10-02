import 'dart:async';

import 'package:flutter/foundation.dart';

import '../media/media_backend.dart';
import '../media/ids.dart';
import '../media/media_item.dart';
import '../media/media_library.dart';
import '../media/media_playlist.dart';
import '../media/media_server_client.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../utils/error_message_utils.dart';
import 'libraries_provider.dart';
import 'multi_server_provider.dart';

enum PersonalMediaLoadState { initial, loading, loaded, error }

class PersonalCollectionEntry {
  const PersonalCollectionEntry({required this.item, required this.library});

  final MediaItem item;
  final MediaLibrary library;

  String get serverId => library.serverId!;

  /// Jellyfin's BoxSets endpoint is server-wide even when given a library ID.
  /// Plex collections remain library-scoped.
  String get sourceLabel => library.backend == MediaBackend.jellyfin
      ? (library.serverName ?? serverId)
      : '${library.serverName ?? serverId} · ${library.title}';
}

class PersonalPlaylistEntry {
  const PersonalPlaylistEntry({required this.playlist, required this.serverId, required this.serverName});

  final MediaPlaylist playlist;
  final String serverId;
  final String serverName;
}

/// Profile-scoped source for the two personal-media overview routes.
///
/// Plex collections stay library-scoped because their backend request needs
/// that context. Jellyfin BoxSets and playlists are server-scoped and fetched
/// exactly once per server, even when it owns several libraries. Successful
/// scopes survive a neighbouring server failure, and
/// [retryFailed] touches only the scopes that failed.
class PersonalMediaProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  PersonalMediaProvider({required MultiServerProvider multiServer, required LibrariesProvider libraries})
    : _multiServer = multiServer,
      _libraries = libraries {
    _libraries.addListener(_onSourcesChanged);
    _multiServer.addOnlineServersListener(_onOnlineServersChanged);
  }

  final MultiServerProvider _multiServer;
  final LibrariesProvider _libraries;

  PersonalMediaLoadState _state = PersonalMediaLoadState.initial;
  PersonalMediaLoadState get state => _state;

  final Map<String, List<PersonalCollectionEntry>> _collectionsByLibrary = {};
  final Map<String, List<PersonalPlaylistEntry>> _playlistsByServer = {};
  final Map<String, String> _collectionFailures = {};
  final Map<String, String> _playlistFailures = {};

  Future<void>? _inFlight;
  String? _loadedScopeSignature;
  bool _reloadAfterFlight = false;

  void _onOnlineServersChanged(Set<String> _) => _onSourcesChanged();

  void _onSourcesChanged() {
    safeNotifyListeners();
    if (_state == PersonalMediaLoadState.initial || _scopeSignature() == _loadedScopeSignature) return;
    if (_inFlight != null) {
      _reloadAfterFlight = true;
    } else {
      unawaited(load());
    }
  }

  String _scopeSignature() {
    final libraries = _collectionScopes().map((library) => library.globalKey).toList()..sort();
    final servers = _playlistScopes().map((client) => client.serverId.value).toList()..sort();
    return '${libraries.join('|')}#${servers.join('|')}';
  }

  List<PersonalCollectionEntry> get collections =>
      List.unmodifiable([for (final library in _collectionScopes()) ...?_collectionsByLibrary[library.globalKey]]);

  List<PersonalPlaylistEntry> get playlists => List.unmodifiable([
    for (final serverId in _playlistScopes().map((client) => client.serverId.value)) ...?_playlistsByServer[serverId],
  ]);

  Set<String> get failedCollectionLibraryKeys => Set.unmodifiable(_collectionFailures.keys);
  Set<String> get failedPlaylistServerIds => Set.unmodifiable(_playlistFailures.keys);
  Map<String, String> get collectionErrors => Map.unmodifiable(_collectionFailures);
  Map<String, String> get playlistErrors => Map.unmodifiable(_playlistFailures);

  bool get isLoading => _state == PersonalMediaLoadState.loading;
  bool get supportsCollections => _collectionScopes().isNotEmpty;
  bool get supportsPlaylists => _playlistScopes().isNotEmpty;
  bool get hasPartialFailure =>
      (_collectionFailures.isNotEmpty || _playlistFailures.isNotEmpty) &&
      (_collectionsByLibrary.isNotEmpty || _playlistsByServer.isNotEmpty);

  MediaServerClient? clientForServer(String serverId) => _multiServer.getClientForServer(ServerId(serverId));

  void _onFlightComplete() {
    _inFlight = null;
    if (_reloadAfterFlight && !isDisposed) {
      _reloadAfterFlight = false;
      unawaited(load());
    }
  }

  Future<void> load() => _inFlight ??= _loadAll().whenComplete(_onFlightComplete);

  Future<void> _loadAll() async {
    _state = PersonalMediaLoadState.loading;
    _collectionsByLibrary.clear();
    _playlistsByServer.clear();
    _collectionFailures.clear();
    _playlistFailures.clear();
    safeNotifyListeners();

    final collectionScopes = _collectionScopes();
    final playlistScopes = _playlistScopes();
    _loadedScopeSignature = _scopeSignature();
    final results = await Future.wait<Object>([
      for (final library in collectionScopes) _loadCollectionScope(library),
      for (final client in playlistScopes) _loadPlaylistScope(client),
    ]);

    for (final result in results) {
      _apply(result);
    }
    _finish(scopeCount: collectionScopes.length + playlistScopes.length);
  }

  Future<void> retryFailed() async {
    if (_inFlight != null) return _inFlight;
    final failedLibraries = Set<String>.of(_collectionFailures.keys);
    final failedServers = Set<String>.of(_playlistFailures.keys);
    if (failedLibraries.isEmpty && failedServers.isEmpty) return;

    _inFlight = _retry(failedLibraries, failedServers).whenComplete(_onFlightComplete);
    return _inFlight;
  }

  Future<void> _retry(Set<String> failedLibraries, Set<String> failedServers) async {
    _state = PersonalMediaLoadState.loading;
    safeNotifyListeners();

    final libraries = _collectionScopes().where((library) => failedLibraries.contains(library.globalKey)).toList();
    final clients = _playlistScopes().where((client) => failedServers.contains(client.serverId.value)).toList();
    final results = await Future.wait<Object>([
      for (final library in libraries) _loadCollectionScope(library),
      for (final client in clients) _loadPlaylistScope(client),
    ]);

    for (final result in results) {
      _apply(result);
    }
    _finish(scopeCount: _collectionScopes().length + _playlistScopes().length);
  }

  List<MediaLibrary> _collectionScopes() {
    final seenJellyfinServers = <String>{};
    final scopes = <MediaLibrary>[];
    for (final library in _libraries.libraries) {
      final serverId = library.serverId;
      if (library.isShared || serverId == null) continue;
      if (library.backend != MediaBackend.plex && library.backend != MediaBackend.jellyfin) continue;
      if (_multiServer.getClientForServer(ServerId(serverId)) == null) continue;
      if (library.backend == MediaBackend.jellyfin && !seenJellyfinServers.add(serverId)) continue;
      scopes.add(library);
    }
    return scopes;
  }

  List<MediaServerClient> _playlistScopes() {
    final seen = <String>{};
    return [
      for (final serverId in _multiServer.onlineServerIds)
        if (seen.add(serverId))
          if (_multiServer.getClientForServer(ServerId(serverId)) case final client?)
            if (client.capabilities.serverSidePlaylists) client,
    ];
  }

  Future<_CollectionResult> _loadCollectionScope(MediaLibrary library) async {
    final client = _multiServer.getClientForServer(ServerId(library.serverId!));
    if (client == null) return _CollectionResult(library: library, error: 'Server unavailable');
    try {
      final items = await client.fetchCollections(library.id);
      return _CollectionResult(
        library: library,
        entries: [
          for (final item in items)
            PersonalCollectionEntry(
              item: item.copyWith(
                libraryId: library.backend == MediaBackend.plex ? (item.libraryId ?? library.id) : item.libraryId,
                libraryTitle: library.backend == MediaBackend.plex
                    ? (item.libraryTitle ?? library.title)
                    : item.libraryTitle,
                serverId: item.serverId ?? library.serverId,
                serverName: item.serverName ?? library.serverName,
              ),
              library: library,
            ),
        ],
      );
    } catch (error) {
      return _CollectionResult(
        library: library,
        error: friendlyError(error, context: library.title),
      );
    }
  }

  Future<_PlaylistResult> _loadPlaylistScope(MediaServerClient client) async {
    try {
      final items = await client.fetchPlaylists(playlistType: 'video');
      return _PlaylistResult(
        serverId: client.serverId.value,
        entries: [
          for (final playlist in items)
            PersonalPlaylistEntry(
              playlist: playlist,
              serverId: client.serverId.value,
              serverName: client.serverName ?? client.serverId.value,
            ),
        ],
      );
    } catch (error) {
      return _PlaylistResult(
        serverId: client.serverId.value,
        error: friendlyError(error, context: client.serverName ?? client.serverId.value),
      );
    }
  }

  void _apply(Object result) {
    switch (result) {
      case _CollectionResult():
        final key = result.library.globalKey;
        if (result.error case final error?) {
          _collectionFailures[key] = error;
        } else {
          _collectionFailures.remove(key);
          _collectionsByLibrary[key] = result.entries;
        }
      case _PlaylistResult():
        if (result.error case final error?) {
          _playlistFailures[result.serverId] = error;
        } else {
          _playlistFailures.remove(result.serverId);
          _playlistsByServer[result.serverId] = result.entries;
        }
    }
  }

  void _finish({required int scopeCount}) {
    final failureCount = _collectionFailures.length + _playlistFailures.length;
    _state = scopeCount > 0 && failureCount == scopeCount
        ? PersonalMediaLoadState.error
        : PersonalMediaLoadState.loaded;
    safeNotifyListeners();
  }

  @override
  void dispose() {
    _libraries.removeListener(_onSourcesChanged);
    _multiServer.removeOnlineServersListener(_onOnlineServersChanged);
    super.dispose();
  }
}

class _CollectionResult {
  const _CollectionResult({required this.library, this.entries = const [], this.error});

  final MediaLibrary library;
  final List<PersonalCollectionEntry> entries;
  final String? error;
}

class _PlaylistResult {
  const _PlaylistResult({required this.serverId, this.entries = const [], this.error});

  final String serverId;
  final List<PersonalPlaylistEntry> entries;
  final String? error;
}
