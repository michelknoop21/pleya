import 'assistant_spoiler_context.dart';
import '../media/ids.dart';
import '../media/media_library.dart';
import '../media/media_server_client.dart';
import '../media/server_administration.dart';
import '../services/multi_server_manager.dart';
import '../utils/media_server_http_client.dart' show AbortController;
import 'assistant_age_gate.dart';
import 'assistant_title_facts.dart';
import 'assistant_tools.dart';
import 'assistant_web_lookup.dart';
import 'assistant_playback.dart';

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
    this.accessKnown = true,
  });
  final String name;
  final bool isAdmin;
  final bool plexHomeMember;
  final bool plexManaged;

  /// False when the server did not say which libraries this user sees; an
  /// access change is then refused rather than replacing the unknown.
  final bool accessKnown;
}

/// Per-run state between the tools and the server manager.
///
/// Holds the allow-list of ids: a job, user or item id is only accepted when
/// a tool result in this run showed it, so neither a fabricated id nor one
/// planted in metadata text reaches a server. Library ids are checked against
/// the server's own library list.
class AssistantToolContext {
  AssistantToolContext({
    required this.servers,
    this.screen,
    this.catalog,
    this.insights,
    this.requests,
    this.media,
    this.playback,
    this.spoilers,
    this.personal,
    this.web,
    this.titleFacts,
    this.kidsAges,
    this.region = assistantRegion,
    this.cancel,
    this.kidsFilter = true,
  });

  final MultiServerManager servers;
  final AssistantScreenContext? screen;

  /// The ask's cancel signal (`AssistantRun.cancel`): fires once the user
  /// left, so a long tool such as find_title aborts its calls at once.
  final AbortController? cancel;
  bool get cancelled => cancel?.isAborted ?? false;

  /// Diagnosis tasks never inherit the ordinary immediate administration path.
  bool libraryDoctorMode = false;
  final Set<String> libraryDoctorActions = {};
  void Function()? libraryDoctorCheck;
  String Function(String language)? libraryDoctorAnswer;
  String? get libraryDoctorError {
    try {
      libraryDoctorCheck?.call();
      return libraryDoctorMode && cancelled ? 'cancelled' : null;
    } on AssistantToolError catch (e) {
      return e.code;
    }
  }

  /// Cohort evidence retains the same live source checks used by its reads.
  /// Per-run only: fresh child contexts never inherit another task's evidence.
  void Function()? recommendationCheck;
  String? get recommendationError {
    try {
      recommendationCheck?.call();
      return null;
    } on AssistantToolError catch (e) {
      return e.code;
    }
  }

  /// Same servers, screen and services, none of the per-run state.
  AssistantToolContext fresh({AbortController? cancel, AssistantWebServices? web, bool? kidsFilter}) =>
      AssistantToolContext(
        servers: servers,
        screen: screen,
        catalog: catalog,
        insights: insights,
        requests: requests,
        media: media,
        playback: playback,
        spoilers: spoilers,
        personal: personal,
        web: web ?? this.web,
        titleFacts: titleFacts,
        kidsAges: kidsAges,
        region: region,
        cancel: cancel ?? this.cancel,
        kidsFilter: kidsFilter ?? this.kidsFilter,
      );

  /// Domain services the UI layer hands in. A missing one keeps its tools
  /// out of the run; nothing here grants rights on a server.
  final AssistantCatalogServices? catalog;
  final AssistantInsightServices? insights;
  final AssistantRequestServices? requests;
  final AssistantMediaServices? media;
  final AssistantPlaybackServices? playback;
  final AssistantSpoilerServices? spoilers;
  String? spoilerQuestion;
  AssistantSpoilerContext? spoilerEvidence;
  Future<AssistantSpoilerContext> safeSpoilerContext() async => spoilerEvidence ??= await buildAssistantSpoilerContext(
    services: spoilers,
    clientFor: (id) => userClient(ServerId(id)),
    cancelled: () => cancelled,
    question: spoilerQuestion ?? '',
  );
  AssistantPlaybackSnapshot? _playbackEvidence;

  void bindPlaybackEvidence(AssistantPlaybackSnapshot snapshot) => _playbackEvidence = snapshot;
  bool get playbackEvidenceCurrent =>
      (_playbackEvidence == null || (playback?.isCurrent(_playbackEvidence!) ?? false)) &&
      (spoilerEvidence?.position == null || spoilerEvidence!.current());

  /// Who is asking and what this profile watched; null keeps my_watching out
  /// and the system prompt without a name.
  final AssistantPersonalServices? personal;

  /// Web lookup for find_title; null when the user switched it off.
  final AssistantWebServices? web;

  /// Age ratings, genres, score and services per title; null leaves them out.
  final TitleFactsService? titleFacts;

  /// The ages of this profile's children, for the age gate; null or empty
  /// leaves it off.
  final Future<List<int>> Function()? kidsAges;

  /// False for one ask the viewer ran "Zonder filter": no age gate, and no
  /// ages card either.
  final bool kidsFilter;

  /// The region whose age ratings count (`NL`); the device's by default.
  final String Function() region;

  /// This ask picks for children: the prompt said so, or a title tool got
  /// `for_kids`. Titles then pass only through the age gate.
  bool kidsMode = false;

  /// The youngest child's age once a title tool read it.
  int? kidsAge;

  /// Titles the age gate turned down this ask, with the rating that decided.
  final List<({String title, int? year, String reason})> ageRejected = [];

  /// Titles the age gate let through this ask: in kids mode the answer may
  /// name only these.
  final List<({String title, int? year})> ageAllowed = [];

  /// Shown job ids per server, with the title list_jobs gave them.
  final Map<String, Map<String, String>> _jobs = {};
  final Map<String, Set<String>> _items = {};
  final Map<String, Map<String, AssistantKnownUser>> _users = {};
  final Map<String, List<MediaLibrary>> _libraries = {};

  /// Visible servers of the active profile, online or not. Personal tools
  /// (search, rows, downloads) act here; administration needs
  /// [administeredServers].
  List<ServerId> get userServers => [
    for (final id in servers.serverIds)
      if (servers.isServerVisible(ServerId(id))) ServerId(id),
  ];

  /// The client for [serverId] when it is visible and online, for what any
  /// profile may do as itself.
  MediaServerClient? userClient(ServerId serverId) =>
      servers.isServerVisible(serverId) && servers.isServerOnline(serverId) ? servers.getClient(serverId) : null;

  /// Visible servers the active profile may administer, online or not. Every
  /// administration tool rests on this (Big P's visibility does not, see
  /// DEC-142); [adminClient] adds "online now".
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
    final client = userClient(serverId);
    if (client == null) throw const AssistantToolError('server_not_available');
    // Every library, hidden ones included: hiding is a browse preference of
    // this profile, and access edits must see what they replace.
    final libraries = await client.fetchLibraries();
    return _libraries[serverId.value] = libraries;
  }

  Future<MediaLibrary> library(ServerId serverId, String libraryId) async {
    final match = (await libraries(serverId)).where((l) => l.id == libraryId).firstOrNull;
    if (match == null) throw const AssistantToolError('unknown_library_id');
    return match;
  }

  void showJob(ServerId serverId, String id, String title) => (_jobs[serverId.value] ??= {})[id] = title;
  void showItem(ServerId serverId, String id) => (_items[serverId.value] ??= {}).add(id);
  void showUser(ServerId serverId, String id, AssistantKnownUser user) => (_users[serverId.value] ??= {})[id] = user;

  /// The job's title as list_jobs showed it.
  String requireShownJob(ServerId serverId, String id) =>
      _jobs[serverId.value]?[id] ?? (throw const AssistantToolError('unknown_job_id'));

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
