import 'package:xml/xml.dart';

import '../exceptions/media_server_exceptions.dart';
import '../media/server_administration.dart';
import '../utils/media_server_http_client.dart';

/// Plex Home membership and server shares for one owned server, on plex.tv.
///
/// plex.tv has no official API for this. The endpoints and payloads follow
/// python-plexapi (`plexapi/myplex.py`, master): `createHomeUser`,
/// `removeHomeUser`, `updateFriend`, `_getSectionIds` and
/// `MyPlexServerShare`. All of them are the v1 XML generation under
/// `https://plex.tv/api/`; the v2 `sharings` endpoint is not used.
///
/// Runs as the Home admin's plex.tv account token only. A `/switch` user
/// token belongs to a different identity (a Home member) and must never reach
/// this class: build it through `MultiServerManager.plexSharingFor`, which
/// reads `PlexAccountConnection.accountToken` and never a server access
/// token.
///
/// Fails closed: a non-2xx status, a body that is not the expected XML, a
/// missing attribute or an unknown library key throws. Nothing is guessed.
class PlexSharingService implements PlexSharingAdministration {
  PlexSharingService({
    required this._accountToken,
    required this._clientIdentifier,
    required this.machineIdentifier,
    required this._canAdminister,
    required this._http,
  });

  static const _base = 'https://plex.tv/api';

  final String _accountToken;
  final String _clientIdentifier;
  final bool Function() _canAdminister;
  final MediaServerHttpClient _http;

  /// The owned server's machine identifier (`PlexServer.clientIdentifier`).
  final String machineIdentifier;

  @override
  bool get supportsServerAdministration => true;

  Map<String, String> get _headers => {
    'Accept': 'application/xml',
    'X-Plex-Product': 'Pleya',
    'X-Plex-Client-Identifier': _clientIdentifier,
    'X-Plex-Token': _accountToken,
  };

  void _assertAuthority() {
    if (_canAdminister() != true) {
      throw const MediaServerAuthException('Only a server administrator can do this', statusCode: 403);
    }
  }

  @override
  Future<List<PlexShare>> listShares() async {
    _assertAuthority();
    final sections = await _sections();
    final shares = await _sharedServers();
    final home = await _homeUsers();
    final homeById = {for (final u in home) u.id: u};

    final result = <PlexShare>[];
    final sharedUserIds = <String>{};
    for (final s in shares) {
      sharedUserIds.add(s.userId);
      final homeUser = homeById[s.userId];
      result.add(
        PlexShare(
          userId: s.userId,
          name: homeUser?.title ?? s.name,
          homeMember: homeUser != null,
          managed: homeUser?.managed ?? false,
          allLibraries: s.allLibraries,
          libraryIds: s.allLibraries
              ? sections.keyById.values.toList()
              : [for (final id in s.sharedSectionIds) sections.keyFor(id)],
        ),
      );
    }
    for (final u in home) {
      if (u.admin || sharedUserIds.contains(u.id)) continue;
      result.add(
        PlexShare(
          userId: u.id,
          name: u.title,
          homeMember: true,
          managed: u.managed,
          allLibraries: false,
          shared: false,
        ),
      );
    }
    return result;
  }

  @override
  Future<String> createManagedHomeUser(String name) async {
    _assertAuthority();
    final title = name.trim();
    if (title.isEmpty) throw ArgumentError.value(name, 'name', 'must not be empty');
    final root = _rootOf(await _http.post('$_base/home/users', queryParameters: {'title': title}, headers: _headers));
    final id = root.getAttribute('id');
    if (id == null || int.tryParse(id) == null) throw _shape('created Home user has no id');
    return id;
  }

  @override
  Future<void> setShareLibraries(
    String userId, {
    required bool allLibraries,
    List<String> libraryIds = const [],
  }) async {
    _assertAuthority();
    final invitedId = _userIdAsInt(userId);
    final sections = await _sections();
    // Translate every key before any mutating call, so an unknown key stops
    // the whole change instead of half-applying it.
    final plexTvIds = allLibraries
        ? sections.keyById.keys.toList()
        : [for (final key in libraryIds) sections.idFor(key)];
    if (plexTvIds.isEmpty) {
      throw ArgumentError('A share needs at least one library; use removeShare to revoke access');
    }

    final existing = (await _sharedServers()).where((s) => s.userId == userId).firstOrNull;
    if (existing != null) {
      _ok(
        await _http.put(
          '$_base/servers/$machineIdentifier/shared_servers/${existing.id}',
          headers: _headers,
          body: {
            'server_id': machineIdentifier,
            'shared_server': {'library_section_ids': plexTvIds},
          },
        ),
      );
    } else {
      _ok(
        await _http.post(
          '$_base/servers/$machineIdentifier/shared_servers',
          headers: _headers,
          body: {
            'server_id': machineIdentifier,
            'shared_server': {'library_section_ids': plexTvIds, 'invited_id': invitedId},
            'sharing_settings': <String, String>{},
          },
        ),
      );
    }
  }

  @override
  Future<void> removeShare(String userId) async {
    _assertAuthority();
    _userIdAsInt(userId);
    final existing = (await _sharedServers()).where((s) => s.userId == userId).firstOrNull;
    if (existing == null) throw StateError('User $userId has no share on this server');
    _ok(await _http.delete('$_base/servers/$machineIdentifier/shared_servers/${existing.id}', headers: _headers));
  }

  @override
  Future<void> removeHomeUser(String userId) async {
    _assertAuthority();
    _userIdAsInt(userId);
    final user = (await _homeUsers()).where((u) => u.id == userId).firstOrNull;
    if (user == null) throw StateError('User $userId is not in this Plex Home');
    if (user.admin) throw StateError('The Home admin cannot be removed');
    _ok(await _http.delete('$_base/home/users/$userId', headers: _headers));
  }

  // --- reads -----------------------------------------------------------------

  /// `GET /api/servers/{machineId}`: `Server > Section(id, key)`, where `id`
  /// is plex.tv's section id and `key` the PMS section key (the app's
  /// `MediaLibrary.id`).
  Future<_SectionMap> _sections() async {
    final root = _rootOf(await _http.get('$_base/servers/$machineIdentifier', headers: _headers));
    final server = root.findElements('Server').firstOrNull;
    if (server == null) throw _shape('no Server element for $machineIdentifier');
    final keyById = <int, String>{};
    for (final section in server.findElements('Section')) {
      final id = int.tryParse(section.getAttribute('id') ?? '');
      final key = section.getAttribute('key');
      if (id == null || key == null || key.isEmpty) throw _shape('Section without id or key');
      keyById[id] = key;
    }
    return _SectionMap(keyById);
  }

  /// `GET /api/servers/{machineId}/shared_servers`.
  Future<List<_SharedServer>> _sharedServers() async {
    final root = _rootOf(await _http.get('$_base/servers/$machineIdentifier/shared_servers', headers: _headers));
    return [
      for (final e in root.findElements('SharedServer'))
        _SharedServer(
          id: _requireInt(e, 'id'),
          userId: _requireInt(e, 'userID'),
          name: _firstNonEmpty([e.getAttribute('username'), e.getAttribute('email')]) ?? '',
          allLibraries: e.getAttribute('allLibraries') == '1',
          sharedSectionIds: [
            for (final s in e.findElements('Section'))
              if (s.getAttribute('shared') == '1') int.parse(_requireInt(s, 'id')),
          ],
        ),
    ];
  }

  /// `GET /api/home/users`: the Home, admin included.
  Future<List<_HomeUser>> _homeUsers() async {
    final root = _rootOf(await _http.get('$_base/home/users', headers: _headers));
    return [
      for (final e in root.findElements('User'))
        _HomeUser(
          id: _requireInt(e, 'id'),
          title: _firstNonEmpty([e.getAttribute('title'), e.getAttribute('username')]) ?? '',
          admin: e.getAttribute('admin') == '1',
          // plex.tv calls managed users "restricted".
          managed: e.getAttribute('restricted') == '1',
        ),
    ];
  }

  // --- helpers ---------------------------------------------------------------

  void _ok(MediaServerResponse r) {
    throwIfHttpError(r);
    if (r.statusCode < 200 || r.statusCode >= 300) throw _shape('unexpected HTTP ${r.statusCode}', r);
  }

  XmlElement _rootOf(MediaServerResponse r) {
    _ok(r);
    final body = r.data;
    if (body is! String || body.trim().isEmpty) throw _shape('expected an XML body', r);
    try {
      return XmlDocument.parse(body).rootElement;
    } on XmlException catch (e) {
      throw _shape('unparsable XML: ${e.message}', r);
    }
  }

  String _requireInt(XmlElement e, String attribute) {
    final value = e.getAttribute(attribute);
    if (value == null || int.tryParse(value) == null) throw _shape('${e.name.local} without $attribute');
    return value;
  }

  int _userIdAsInt(String userId) {
    final id = int.tryParse(userId);
    if (id == null) throw ArgumentError.value(userId, 'userId', 'not a plex.tv user id');
    return id;
  }

  static String? _firstNonEmpty(List<String?> values) => values.where((v) => v != null && v.isNotEmpty).firstOrNull;

  static MediaServerHttpException _shape(String message, [MediaServerResponse? r]) => MediaServerHttpException(
    type: MediaServerHttpErrorType.unknown,
    statusCode: r?.statusCode,
    requestUri: r?.requestUri,
    message: 'plex.tv sharing: $message',
  );
}

class _SectionMap {
  _SectionMap(this.keyById) : _idByKey = {for (final e in keyById.entries) e.value: e.key};

  final Map<int, String> keyById;
  final Map<String, int> _idByKey;

  int idFor(String key) => _idByKey[key] ?? (throw ArgumentError.value(key, 'libraryId', 'unknown library'));

  String keyFor(int id) =>
      keyById[id] ??
      (throw MediaServerHttpException(
        type: MediaServerHttpErrorType.unknown,
        message: 'plex.tv sharing: shared section $id is not on this server',
      ));
}

class _SharedServer {
  const _SharedServer({
    required this.id,
    required this.userId,
    required this.name,
    required this.allLibraries,
    required this.sharedSectionIds,
  });

  final String id;
  final String userId;
  final String name;
  final bool allLibraries;
  final List<int> sharedSectionIds;
}

class _HomeUser {
  const _HomeUser({required this.id, required this.title, required this.admin, required this.managed});

  final String id;
  final String title;
  final bool admin;
  final bool managed;
}
