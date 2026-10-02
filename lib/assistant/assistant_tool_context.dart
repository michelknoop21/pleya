import '../media/ids.dart';
import '../media/media_library.dart';
import '../media/media_server_client.dart';
import '../media/server_administration.dart';
import '../services/multi_server_manager.dart';

/// Where the user opened the Assistant from. Pleya data, never authority:
/// every id here is checked again like any id the model sends.
class AssistantScreenContext {
  const AssistantScreenContext({this.serverId, this.libraryId});
  final String? serverId;
  final String? libraryId;
}

/// A user Pleya showed the model, kept so a later action can name it on the
/// confirmation card and refuse ids the model never saw.
class AssistantKnownUser {
  const AssistantKnownUser({
    required this.name,
    this.isAdmin = false,
    this.plexHomeMember = false,
    this.plexManaged = false,
  });
  final String name;
  final bool isAdmin;
  final bool plexHomeMember;
  final bool plexManaged;
}

/// Per-run state between the tools and the server manager.
///
/// Holds the allow-list of ids: a job, user or item id is only accepted when
/// a tool result in this run showed it, so neither a fabricated id nor one
/// planted in metadata text reaches a server. Library ids are checked against
/// the server's own library list.
class AssistantToolContext {
  AssistantToolContext({required this.servers, this.screen});

  final MultiServerManager servers;
  final AssistantScreenContext? screen;

  final Map<String, Set<String>> _jobs = {};
  final Map<String, Set<String>> _items = {};
  final Map<String, Map<String, AssistantKnownUser>> _users = {};
  final Map<String, List<MediaLibrary>> _libraries = {};

  /// Visible servers the active profile may administer, online or not. This
  /// is what Big P's visibility rests on; [adminClient] adds "online now".
  List<ServerId> get administeredServers => [
    for (final id in servers.serverIds)
      if (servers.isServerVisible(ServerId(id)) && servers.canAdministerServer(ServerId(id))) ServerId(id),
  ];

  /// The client for [serverId] when it may be administered right now:
  /// visible, online, the profile holds the rights, and the server exposes
  /// administration. Evaluated live on every call.
  MediaServerClient? adminClient(ServerId serverId) {
    if (!servers.isServerVisible(serverId) || !servers.isServerOnline(serverId)) return null;
    if (!servers.canAdministerServer(serverId)) return null;
    final client = servers.getClient(serverId);
    if (client case final ServerAdministrationClient admin when !admin.supportsServerAdministration) return null;
    return client;
  }

  /// [adminClient] with capability [T], or null.
  T? admin<T extends ServerAdministrationClient>(ServerId serverId) => switch (adminClient(serverId)) {
    final T client => client,
    _ => null,
  };

  PlexSharingAdministration? plexSharing(ServerId serverId) =>
      adminClient(serverId) == null ? null : servers.plexSharingFor(serverId);

  String serverName(ServerId serverId) => servers.serverDisplayName(serverId);

  Future<List<MediaLibrary>> libraries(ServerId serverId) async {
    final cached = _libraries[serverId.value];
    if (cached != null) return cached;
    final client = adminClient(serverId);
    if (client == null) throw const AssistantToolError('server_not_available');
    final libraries = (await client.fetchLibraries()).where((l) => !l.hidden).toList();
    return _libraries[serverId.value] = libraries;
  }

  Future<MediaLibrary> library(ServerId serverId, String libraryId) async {
    final match = (await libraries(serverId)).where((l) => l.id == libraryId).firstOrNull;
    if (match == null) throw const AssistantToolError('unknown_library_id');
    return match;
  }

  void showJob(ServerId serverId, String id) => (_jobs[serverId.value] ??= {}).add(id);
  void showItem(ServerId serverId, String id) => (_items[serverId.value] ??= {}).add(id);
  void showUser(ServerId serverId, String id, AssistantKnownUser user) => (_users[serverId.value] ??= {})[id] = user;

  void requireShownJob(ServerId serverId, String id) {
    if (!(_jobs[serverId.value]?.contains(id) ?? false)) throw const AssistantToolError('unknown_job_id');
  }

  void requireShownItem(ServerId serverId, String id) {
    if (!(_items[serverId.value]?.contains(id) ?? false)) throw const AssistantToolError('unknown_item_id');
  }

  AssistantKnownUser requireShownUser(ServerId serverId, String id) =>
      _users[serverId.value]?[id] ?? (throw const AssistantToolError('unknown_user_id'));
}

/// A refusal the model gets back as `{"error": code}`. Codes, not prose:
/// nothing in them comes from a server.
class AssistantToolError implements Exception {
  const AssistantToolError(this.code);
  final String code;

  @override
  String toString() => 'AssistantToolError($code)';
}
