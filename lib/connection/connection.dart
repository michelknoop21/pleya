import '../media/media_backend.dart';
import '../models/plex/plex_home_user.dart';
import '../services/plex_auth_service.dart';

/// Identifier of a backend kind a [Connection] points at. Lighter-weight than
/// [MediaBackend] for places that only care about persistence/auth shape
/// (e.g. database column values).
enum ConnectionKind {
  plex,
  jellyfin,
  local,
  pleyaShare;

  String get id => switch (this) {
    ConnectionKind.plex => 'plex',
    ConnectionKind.jellyfin => 'jellyfin',
    ConnectionKind.local => 'local',
    ConnectionKind.pleyaShare => 'pleyaShare',
  };

  static ConnectionKind fromId(String id) => switch (id) {
    'plex' => ConnectionKind.plex,
    'jellyfin' => ConnectionKind.jellyfin,
    'local' => ConnectionKind.local,
    'pleyaShare' => ConnectionKind.pleyaShare,
    _ => throw ArgumentError('Unknown ConnectionKind id: $id'),
  };

  MediaBackend get backend => switch (this) {
    ConnectionKind.plex => MediaBackend.plex,
    ConnectionKind.jellyfin => MediaBackend.jellyfin,
    // Pleya Share items are proxied local files; they behave as local media
    // throughout the UI (no ratings/playlists/transcoding).
    ConnectionKind.local || ConnectionKind.pleyaShare => MediaBackend.local,
  };
}

/// Health snapshot for a connection. Updated by the orchestrator each time a
/// session is established or refreshed.
enum ConnectionStatus { unknown, online, offline, authError, disabled }

/// A media server connection — a unit of authentication the user added.
///
/// A `PlexAccountConnection` carries one Plex account + its discovered servers + an
/// optional active Home profile. A `JellyfinConnection` is a single server +
/// user. Most users only ever add one connection.
sealed class Connection {
  String get id;
  ConnectionKind get kind;
  String get displayName;
  ConnectionStatus get status;
  DateTime get createdAt;
  DateTime? get lastAuthenticatedAt;

  /// Backend kind as a [MediaBackend] — for UI that branches on backend
  /// (badges, etc.). Just a passthrough to [kind.backend].
  MediaBackend get backend => kind.backend;

  /// Primary label shown in connection-list UIs. Plex shows the active
  /// profile/account name; Jellyfin shows the server name.
  String get displayLabel;

  /// Secondary line shown beneath [displayLabel] in connection-list UIs.
  /// Plex: server count; Jellyfin: `userName · baseUrl`. May be null when
  /// no useful subtitle exists.
  String? get displaySubtitle;

  /// Backend-specific config payload, persisted as JSON. Each subclass
  /// defines the schema.
  Map<String, Object?> toConfigJson();
}

/// A Plex account connection.
///
/// Fields here mirror what [PlexAuthService] gathers during PIN OAuth: an
/// account token (long-lived), the per-device client identifier (so plex.tv
/// doesn't see a "new device" each launch), and the optional Home user the
/// user has switched into.
class PlexAccountConnection extends Connection {
  @override
  final String id;

  @override
  final ConnectionStatus status;

  @override
  final DateTime createdAt;

  @override
  final DateTime? lastAuthenticatedAt;

  /// plex.tv account access token.
  final String accountToken;

  /// Per-device client identifier. Stable across launches.
  final String clientIdentifier;

  /// Display name shown for this connection (typically the Plex account email
  /// or username, fallback "Plex").
  final String accountLabel;

  /// Active Home user, or `null` for the main account.
  final PlexHomeUser? activeProfile;

  /// Servers discovered for this account (cached). Populated by the auth
  /// flow and refreshed periodically.
  final List<PlexServer> servers;

  PlexAccountConnection({
    required this.id,
    required this.accountToken,
    required this.clientIdentifier,
    required this.accountLabel,
    this.activeProfile,
    this.servers = const [],
    this.status = ConnectionStatus.unknown,
    required this.createdAt,
    this.lastAuthenticatedAt,
  });

  @override
  ConnectionKind get kind => ConnectionKind.plex;

  /// The bare plex.tv account uuid, without the `plex.` prefix that [id]
  /// wears to keep the connection table's key namespace apart.
  ///
  /// Account-scoped state (the watchlist) keys on this. Carrying the prefixed
  /// row id into such a key would mix a storage detail into an identity that
  /// also has to line up with what plex.tv reports, and the two would drift the
  /// first time the row-id scheme changes. Falls back to [id] when the prefix
  /// is missing, which happens for the rare rows keyed by client identifier.
  String get accountUuid => id.startsWith('plex.') ? id.substring('plex.'.length) : id;

  @override
  String get displayName => activeProfile != null && activeProfile!.title.isNotEmpty
      ? '${activeProfile!.title} · $accountLabel'
      : accountLabel;

  @override
  String get displayLabel => displayName;

  @override
  String? get displaySubtitle => servers.length == 1 ? '1 Plex server' : '${servers.length} Plex servers';

  PlexAccountConnection copyWith({
    String? id,
    String? accountToken,
    String? clientIdentifier,
    String? accountLabel,
    PlexHomeUser? activeProfile,
    bool clearActiveProfile = false,
    List<PlexServer>? servers,
    ConnectionStatus? status,
    DateTime? createdAt,
    DateTime? lastAuthenticatedAt,
  }) {
    return PlexAccountConnection(
      id: id ?? this.id,
      accountToken: accountToken ?? this.accountToken,
      clientIdentifier: clientIdentifier ?? this.clientIdentifier,
      accountLabel: accountLabel ?? this.accountLabel,
      activeProfile: clearActiveProfile ? null : (activeProfile ?? this.activeProfile),
      servers: servers ?? this.servers,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      lastAuthenticatedAt: lastAuthenticatedAt ?? this.lastAuthenticatedAt,
    );
  }

  @override
  Map<String, Object?> toConfigJson() {
    return {
      'accountToken': accountToken,
      'clientIdentifier': clientIdentifier,
      'accountLabel': accountLabel,
      'activeProfile': activeProfile?.toJson(),
      'servers': servers.map((s) => s.toJson()).toList(),
    };
  }

  factory PlexAccountConnection.fromConfigJson({
    required String id,
    required Map<String, Object?> json,
    required ConnectionStatus status,
    required DateTime createdAt,
    DateTime? lastAuthenticatedAt,
  }) {
    final profileJson = json['activeProfile'];
    final activeProfile = profileJson is Map<String, dynamic> ? PlexHomeUser.fromJson(profileJson) : null;
    final serversJson = json['servers'];
    final servers = serversJson is List
        ? serversJson.whereType<Map<String, dynamic>>().map(PlexServer.fromJson).toList()
        : <PlexServer>[];
    return PlexAccountConnection(
      id: id,
      accountToken: json['accountToken'] as String? ?? '',
      clientIdentifier: json['clientIdentifier'] as String? ?? '',
      accountLabel: json['accountLabel'] as String? ?? 'Plex',
      activeProfile: activeProfile,
      servers: servers,
      status: status,
      createdAt: createdAt,
      lastAuthenticatedAt: lastAuthenticatedAt,
    );
  }
}

/// A single-server Jellyfin connection.
class JellyfinConnection extends Connection {
  @override
  final String id;

  @override
  final ConnectionStatus status;

  @override
  final DateTime createdAt;

  @override
  final DateTime? lastAuthenticatedAt;

  /// Active server base URL, no trailing slash. e.g. `https://jellyfin.home.lan`.
  final String baseUrl;

  /// Candidate server URLs for this Jellyfin server, with [baseUrl] first.
  /// Existing installs only have [baseUrl]; deserialization backfills this.
  final List<String> baseUrls;

  /// Server's reported name (System/Info).
  final String serverName;

  /// Server's machine identifier (System/Info `Id`).
  final String serverMachineId;

  /// Authenticated Jellyfin user id (UUID).
  final String userId;

  /// Authenticated user's display name.
  final String userName;

  /// Long-lived access token from `/Users/AuthenticateByName`.
  final String accessToken;

  /// Per-device client identifier (same value sent in the
  /// `Authorization: MediaBrowser DeviceId="..."` header).
  final String deviceId;

  /// Whether this user is a Jellyfin admin (`/Users/{id}.Policy.IsAdministrator`).
  /// Captured at auth time so the UI can gate admin-only entries (delete,
  /// match/unmatch, edit metadata) without an extra round-trip.
  final bool isAdministrator;

  JellyfinConnection({
    required this.id,
    required this.baseUrl,
    List<String>? baseUrls,
    required this.serverName,
    required this.serverMachineId,
    required this.userId,
    required this.userName,
    required this.accessToken,
    required this.deviceId,
    this.isAdministrator = false,
    this.status = ConnectionStatus.unknown,
    required this.createdAt,
    this.lastAuthenticatedAt,
  }) : baseUrls = _normalizeBaseUrls(baseUrl, baseUrls);

  @override
  ConnectionKind get kind => ConnectionKind.jellyfin;

  @override
  String get displayName => '$userName · $serverName';

  @override
  String get displayLabel => serverName;

  @override
  String? get displaySubtitle {
    final extraCount = baseUrls.length - 1;
    final suffix = extraCount > 0 ? ' +$extraCount' : '';
    return '$userName · ${_truncateUrl(baseUrl)}$suffix';
  }

  static String _truncateUrl(String url) {
    if (url.length <= 40) return url;
    return '${url.substring(0, 37)}…';
  }

  static List<String> _normalizeBaseUrls(String activeBaseUrl, List<String>? urls) {
    final result = <String>[];
    final seen = <String>{};

    void add(String url) {
      final trimmed = url.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) return;
      result.add(trimmed);
    }

    add(activeBaseUrl);
    for (final url in urls ?? const <String>[]) {
      add(url);
    }
    return List.unmodifiable(result);
  }

  JellyfinConnection copyWith({
    String? id,
    String? baseUrl,
    List<String>? baseUrls,
    String? serverName,
    String? serverMachineId,
    String? userId,
    String? userName,
    String? accessToken,
    String? deviceId,
    bool? isAdministrator,
    ConnectionStatus? status,
    DateTime? createdAt,
    DateTime? lastAuthenticatedAt,
  }) {
    final nextBaseUrl = baseUrl ?? this.baseUrl;
    return JellyfinConnection(
      id: id ?? this.id,
      baseUrl: nextBaseUrl,
      baseUrls: baseUrls ?? this.baseUrls,
      serverName: serverName ?? this.serverName,
      serverMachineId: serverMachineId ?? this.serverMachineId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      accessToken: accessToken ?? this.accessToken,
      deviceId: deviceId ?? this.deviceId,
      isAdministrator: isAdministrator ?? this.isAdministrator,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      lastAuthenticatedAt: lastAuthenticatedAt ?? this.lastAuthenticatedAt,
    );
  }

  @override
  Map<String, Object?> toConfigJson() {
    return {
      'baseUrl': baseUrl,
      'baseUrls': baseUrls,
      'serverName': serverName,
      'serverMachineId': serverMachineId,
      'userId': userId,
      'userName': userName,
      'accessToken': accessToken,
      'deviceId': deviceId,
      'isAdministrator': isAdministrator,
    };
  }

  factory JellyfinConnection.fromConfigJson({
    required String id,
    required Map<String, Object?> json,
    required ConnectionStatus status,
    required DateTime createdAt,
    DateTime? lastAuthenticatedAt,
  }) {
    final rawBaseUrls = json['baseUrls'];
    final baseUrls = rawBaseUrls is List ? rawBaseUrls.whereType<String>().toList(growable: false) : const <String>[];
    final rawBaseUrl = json['baseUrl'] as String?;
    final baseUrl = rawBaseUrl != null && rawBaseUrl.isNotEmpty
        ? rawBaseUrl
        : (baseUrls.isNotEmpty ? baseUrls.first : '');
    return JellyfinConnection(
      id: id,
      baseUrl: baseUrl,
      baseUrls: baseUrls,
      serverName: json['serverName'] as String? ?? 'Jellyfin',
      serverMachineId: json['serverMachineId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      userName: json['userName'] as String? ?? '',
      accessToken: json['accessToken'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      isAdministrator: json['isAdministrator'] as bool? ?? false,
      status: status,
      createdAt: createdAt,
      lastAuthenticatedAt: lastAuthenticatedAt,
    );
  }
}

/// A local folder connection — a directory on the device (Android SAF URI)
/// scanned as a media library. No auth tokens, no network. Always "online".
class LocalFolderConnection extends Connection {
  @override
  final String id;

  @override
  final ConnectionStatus status;

  @override
  final DateTime createdAt;

  @override
  final DateTime? lastAuthenticatedAt;

  /// Platform-specific directory URI. On Android this is a `content://` SAF URI
  /// with persistable permission. On iOS this is a file path (security-scoped
  /// bookmark data stored in [bookmarkData]).
  final String directoryUri;

  /// User-given display name for this folder source (e.g. "My Movies").
  @override
  final String displayName;

  /// Library type hint: "movies", "tvshows", or "mixed". Drives how the
  /// scanner interprets folder structure.
  final String libraryType;

  /// iOS-only: base64-encoded security-scoped bookmark for persistent access.
  /// Null on Android.
  final String? bookmarkData;

  LocalFolderConnection({
    required this.id,
    required this.directoryUri,
    required this.displayName,
    this.libraryType = 'mixed',
    this.bookmarkData,
    this.status = ConnectionStatus.online,
    required this.createdAt,
    this.lastAuthenticatedAt,
  });

  @override
  ConnectionKind get kind => ConnectionKind.local;

  @override
  String get displayLabel => displayName;

  @override
  String? get displaySubtitle => libraryType == 'movies'
      ? 'Local · Movies'
      : libraryType == 'tvshows'
      ? 'Local · TV Shows'
      : 'Local · Mixed';

  LocalFolderConnection copyWith({
    String? id,
    String? directoryUri,
    String? displayName,
    String? libraryType,
    String? bookmarkData,
    ConnectionStatus? status,
    DateTime? createdAt,
    DateTime? lastAuthenticatedAt,
  }) {
    return LocalFolderConnection(
      id: id ?? this.id,
      directoryUri: directoryUri ?? this.directoryUri,
      displayName: displayName ?? this.displayName,
      libraryType: libraryType ?? this.libraryType,
      bookmarkData: bookmarkData ?? this.bookmarkData,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      lastAuthenticatedAt: lastAuthenticatedAt ?? this.lastAuthenticatedAt,
    );
  }

  @override
  Map<String, Object?> toConfigJson() {
    return {
      'directoryUri': directoryUri,
      'displayName': displayName,
      'libraryType': libraryType,
      'bookmarkData': bookmarkData,
    };
  }

  factory LocalFolderConnection.fromConfigJson({
    required String id,
    required Map<String, Object?> json,
    required ConnectionStatus status,
    required DateTime createdAt,
    DateTime? lastAuthenticatedAt,
  }) {
    return LocalFolderConnection(
      id: id,
      directoryUri: json['directoryUri'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'Local Folder',
      libraryType: json['libraryType'] as String? ?? 'mixed',
      bookmarkData: json['bookmarkData'] as String?,
      status: status,
      createdAt: createdAt,
      lastAuthenticatedAt: lastAuthenticatedAt,
    );
  }
}

/// A paired Pleya Share host — another Pleya device (or the standalone
/// server) that streams its local folders to this device over the LAN.
class PleyaShareConnection extends Connection {
  @override
  final String id;

  @override
  final ConnectionStatus status;

  @override
  final DateTime createdAt;

  @override
  final DateTime? lastAuthenticatedAt;

  /// Host's advertised device name (e.g. "Michel's iPhone").
  final String hostName;

  /// Pairing identity issued by the host during code pairing.
  final String pairId;

  /// Long-lived reconnect secret (base64). Concealed via the credential
  /// vault when persisted.
  final String pairSecret;

  /// Last known LAN IPs of the host, most recent first. Discovery beacons
  /// refresh this at runtime.
  final List<String> lastKnownIps;

  /// Host HTTP port.
  final int port;

  /// Host's relay room identity for internet fallback (null for hosts that
  /// predate relay support).
  final String? relayHostId;

  PleyaShareConnection({
    required this.id,
    required this.hostName,
    required this.pairId,
    required this.pairSecret,
    required this.lastKnownIps,
    required this.port,
    this.relayHostId,
    this.status = ConnectionStatus.online,
    required this.createdAt,
    this.lastAuthenticatedAt,
  });

  @override
  ConnectionKind get kind => ConnectionKind.pleyaShare;

  @override
  String get displayName => hostName;

  @override
  String get displayLabel => hostName;

  @override
  String? get displaySubtitle => 'Pleya Share · ${lastKnownIps.isNotEmpty ? lastKnownIps.first : '?'}:$port';

  PleyaShareConnection copyWith({
    String? hostName,
    String? pairSecret,
    List<String>? lastKnownIps,
    int? port,
    String? relayHostId,
    ConnectionStatus? status,
    DateTime? lastAuthenticatedAt,
  }) {
    return PleyaShareConnection(
      id: id,
      hostName: hostName ?? this.hostName,
      pairId: pairId,
      pairSecret: pairSecret ?? this.pairSecret,
      lastKnownIps: lastKnownIps ?? this.lastKnownIps,
      port: port ?? this.port,
      relayHostId: relayHostId ?? this.relayHostId,
      status: status ?? this.status,
      createdAt: createdAt,
      lastAuthenticatedAt: lastAuthenticatedAt ?? this.lastAuthenticatedAt,
    );
  }

  @override
  Map<String, Object?> toConfigJson() {
    return {
      'hostName': hostName,
      'pairId': pairId,
      'pairSecret': pairSecret,
      'lastKnownIps': lastKnownIps,
      'port': port,
      if (relayHostId != null) 'relayHostId': relayHostId,
    };
  }

  factory PleyaShareConnection.fromConfigJson({
    required String id,
    required Map<String, Object?> json,
    required ConnectionStatus status,
    required DateTime createdAt,
    DateTime? lastAuthenticatedAt,
  }) {
    return PleyaShareConnection(
      id: id,
      hostName: json['hostName'] as String? ?? 'Pleya Share',
      pairId: json['pairId'] as String? ?? '',
      pairSecret: json['pairSecret'] as String? ?? '',
      lastKnownIps: (json['lastKnownIps'] as List?)?.cast<String>() ?? const [],
      port: (json['port'] as num?)?.toInt() ?? 48634,
      relayHostId: json['relayHostId'] as String?,
      status: status,
      createdAt: createdAt,
      lastAuthenticatedAt: lastAuthenticatedAt,
    );
  }
}
