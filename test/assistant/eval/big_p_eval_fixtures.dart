import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_age_gate.dart';
import 'package:pleya/assistant/assistant_memory.dart';
import 'package:pleya/assistant/assistant_named_titles.dart';
import 'package:pleya/assistant/assistant_title_facts.dart';
import 'package:pleya/assistant/assistant_title_facts_cache.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/recommendations/taste_profile.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_administration.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/profiles/household_kids_store.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/unified_catalog/home_custom_row.dart';
import 'package:pleya/services/unified_catalog/home_custom_row_loader.dart';
import 'package:pleya/utils/media_server_http_client.dart' show AbortController;

import '../assistant_find_fakes.dart';
import 'big_p_eval_world.dart';

// The fake catalogue of the Big P evaluation set (BP-11a): about sixty titles
// on one Jellyfin server, films and series mixed. Ratings are NL (AL/6/9/12/
// 16) and US-only (G/PG/TV-Y/TV-Y7/TV-PG); some titles carry none, with and
// without a family genre. A few adult titles are watched or in progress, for
// the "not what I already saw" case.

enum EvalSeen { no, watched, inProgress }

class EvalTitle {
  const EvalTitle(
    this.id,
    this.title,
    this.year, {
    this.kind = MediaKind.movie,
    this.certs = const {},
    this.genres = const [],
    this.seen = EvalSeen.no,
  });

  final String id;
  final String title;
  final int year;
  final MediaKind kind;
  final Map<String, String> certs;
  final List<String> genres;
  final EvalSeen seen;

  bool get isShow => kind == MediaKind.show;
  TitleFacts get facts => TitleFacts(certifications: certs, genres: genres);

  /// Whether the age gate lets a child of [age] see it in [region].
  bool allowedFor(int age, String region) => AgeGate.allows(facts, age, region);

  /// The library row, with the watch state a real server would send.
  MediaItem get item => MediaItem(
    id: id,
    backend: MediaBackend.jellyfin,
    kind: kind,
    title: title,
    year: year,
    serverId: 'zolder',
    serverName: 'zolder',
    durationMs: isShow ? null : 6000000,
    viewOffsetMs: !isShow && seen == EvalSeen.inProgress ? 1800000 : null,
    viewCount: !isShow && seen == EvalSeen.watched ? 1 : null,
    // A day count between 1 and 25 by position, so "recently added" has an answer.
    addedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 - (1 + evalTitles.indexOf(this) % 25) * 86400,
    leafCount: isShow ? 20 : null,
    viewedLeafCount: isShow ? const {EvalSeen.no: 0, EvalSeen.watched: 20, EvalSeen.inProgress: 6}[seen] : null,
  );
}

const _anim = ['Animation', 'Family'];

const evalTitles = <EvalTitle>[
  // Films, NL rated.
  EvalTitle('m01', 'Toy Story', 1995, certs: {'NL': 'AL', 'US': 'G'}, genres: _anim),
  EvalTitle('m02', 'Finding Nemo', 2003, certs: {'NL': 'AL'}, genres: _anim),
  EvalTitle('m03', 'Frozen', 2013, certs: {'NL': '6', 'US': 'PG'}, genres: _anim),
  EvalTitle('m04', 'Paddington', 2014, certs: {'NL': 'AL'}, genres: ['Family', 'Comedy']),
  EvalTitle('m05', 'Shrek', 2001, certs: {'NL': '6'}, genres: _anim),
  EvalTitle('m06', 'Coco', 2017, certs: {'NL': '6'}, genres: _anim),
  EvalTitle('m07', 'The Lion King', 1994, certs: {'NL': 'AL'}, genres: _anim),
  EvalTitle('m08', 'Matilda', 1996, certs: {'NL': '6'}, genres: ['Family', 'Comedy']),
  EvalTitle('m09', 'Harry Potter and the Philosopher\'s Stone', 2001, certs: {'NL': '9'}, genres: ['Fantasy']),
  EvalTitle('m10', 'Jurassic Park', 1993, certs: {'NL': '12', 'US': 'PG-13'}, genres: ['Adventure']),
  EvalTitle('m11', 'The Dark Knight', 2008, certs: {'NL': '16'}, genres: ['Action', 'Crime']),
  EvalTitle('m12', 'Inception', 2010, certs: {'NL': '12'}, genres: ['Science Fiction'], seen: EvalSeen.watched),
  EvalTitle('m13', 'Saw', 2004, certs: {'NL': '16', 'US': 'R'}, genres: ['Horror']),
  EvalTitle('m14', 'The Exorcist', 1973, certs: {'NL': '16'}, genres: ['Horror']),
  EvalTitle('m15', 'Spirited Away', 2001, certs: {'NL': '6'}, genres: _anim),
  EvalTitle('m20', 'Ratatouille', 2007, certs: {'NL': 'AL'}, genres: _anim),
  EvalTitle('m21', 'Despicable Me', 2010, certs: {'NL': 'AL'}, genres: _anim),
  EvalTitle('m22', 'E.T. the Extra-Terrestrial', 1982, certs: {'NL': '6'}, genres: ['Family', 'Science Fiction']),
  EvalTitle('m23', 'The Goonies', 1985, certs: {'NL': '12'}, genres: ['Adventure']),
  EvalTitle('m24', 'Back to the Future', 1985, certs: {'NL': '9'}, genres: ['Adventure', 'Comedy']),
  EvalTitle('m28', 'Moana', 2016, certs: {'NL': '6'}, genres: _anim),
  EvalTitle('m29', 'Gremlins', 1984, certs: {'NL': '12'}, genres: ['Horror', 'Comedy']),
  EvalTitle('m30', 'Alien', 1979, certs: {'NL': '16'}, genres: ['Horror', 'Science Fiction']),
  EvalTitle('m31', 'Pinocchio', 1940, certs: {'NL': 'AL'}, genres: _anim),
  EvalTitle('m33', 'Mary Poppins', 1964, certs: {'NL': 'AL'}, genres: ['Family', 'Musical']),
  EvalTitle('m34', 'Babe', 1995, certs: {'NL': 'AL'}, genres: ['Family']),
  EvalTitle('m35', 'Kung Fu Panda', 2008, certs: {'NL': '6'}, genres: _anim),
  EvalTitle('m36', 'Interstellar', 2014, certs: {'NL': '12'}, genres: ['Science Fiction'], seen: EvalSeen.inProgress),
  EvalTitle('m37', 'Chef', 2014, certs: {'NL': '6'}, genres: ['Comedy']),
  EvalTitle('m38', 'Julie & Julia', 2009, certs: {'NL': 'AL'}, genres: ['Drama', 'Comedy']),
  // Films, US rated only: the gate falls back to the US table.
  EvalTitle('m16', 'Up', 2009, certs: {'US': 'G'}, genres: _anim),
  EvalTitle('m17', 'Cars', 2006, certs: {'US': 'G'}, genres: _anim),
  EvalTitle('m18', 'Night at the Museum', 2006, certs: {'US': 'PG'}, genres: ['Family', 'Comedy']),
  EvalTitle('m19', 'Home Alone', 1990, certs: {'US': 'PG'}, genres: ['Comedy']),
  EvalTitle('m32', 'The Iron Giant', 1999, certs: {'US': 'PG'}, genres: _anim),
  // Films without any rating.
  EvalTitle('m25', 'Kerstverhaal in de Polder', 2019, genres: ['Familie']),
  EvalTitle('m26', 'De Stille Kelder', 2018, genres: ['Thriller']),
  EvalTitle('m27', 'Zomer aan Zee', 2021),
  // Series.
  EvalTitle('s01', 'Bluey', 2018, kind: MediaKind.show, certs: {'NL': 'AL'}, genres: ['Animation', 'Kids']),
  EvalTitle('s02', 'Peppa Pig', 2004, kind: MediaKind.show, certs: {'NL': 'AL'}, genres: ['Animation', 'Kids']),
  EvalTitle('s03', 'Paw Patrol', 2013, kind: MediaKind.show, certs: {'US': 'TV-Y'}, genres: ['Animation', 'Kids']),
  EvalTitle('s04', 'SpongeBob SquarePants', 1999, kind: MediaKind.show, certs: {'US': 'TV-Y7'}, genres: ['Animation']),
  EvalTitle('s05', 'Avatar: The Last Airbender', 2005, kind: MediaKind.show, certs: {'US': 'TV-Y7'}, genres: _anim),
  EvalTitle(
    's06',
    'The Bear',
    2022,
    kind: MediaKind.show,
    certs: {'NL': '16'},
    genres: ['Drama', 'Comedy'],
    seen: EvalSeen.watched,
  ),
  EvalTitle(
    's07',
    'How I Met Your Mother',
    2005,
    kind: MediaKind.show,
    certs: {'NL': '12'},
    genres: ['Comedy'],
    seen: EvalSeen.inProgress,
  ),
  EvalTitle('s08', 'Breaking Bad', 2008, kind: MediaKind.show, certs: {'NL': '16'}, seen: EvalSeen.watched),
  EvalTitle('s09', 'Stranger Things', 2016, kind: MediaKind.show, certs: {'NL': '16'}, seen: EvalSeen.inProgress),
  EvalTitle(
    's10',
    'Friends',
    1994,
    kind: MediaKind.show,
    certs: {'NL': '12'},
    genres: ['Comedy'],
    seen: EvalSeen.watched,
  ),
  EvalTitle('s11', 'The Office', 2005, kind: MediaKind.show, certs: {'NL': '12'}, genres: ['Comedy']),
  EvalTitle('s12', 'Brooklyn Nine-Nine', 2013, kind: MediaKind.show, certs: {'NL': '12'}, genres: ['Comedy']),
  EvalTitle('s13', 'Dribbel', 2005, kind: MediaKind.show, genres: ['Kinderen']),
  EvalTitle('s14', 'Het Geheim van de Molen', 2020, kind: MediaKind.show, genres: ['Drama']),
  EvalTitle('s15', 'MasterChef Junior', 2013, kind: MediaKind.show, certs: {'US': 'TV-PG'}, genres: ['Reality']),
  EvalTitle('s16', 'Sesame Street', 1969, kind: MediaKind.show, certs: {'US': 'TV-Y'}, genres: ['Kids']),
  EvalTitle('s17', 'Pokémon', 1997, kind: MediaKind.show, certs: {'US': 'TV-Y7'}, genres: ['Animation']),
  EvalTitle('s18', 'Doctor Who', 2005, kind: MediaKind.show, certs: {'NL': '12'}, genres: ['Science Fiction']),
  EvalTitle('s19', 'Planet Earth', 2006, kind: MediaKind.show, certs: {'NL': 'AL'}, genres: ['Documentary']),
  EvalTitle('s20', 'The Mandalorian', 2019, kind: MediaKind.show, certs: {'NL': '12'}, genres: ['Science Fiction']),
  EvalTitle('s21', 'Sherlock', 2010, kind: MediaKind.show, certs: {'NL': '12'}, genres: ['Crime']),
  EvalTitle('s22', 'Gilmore Girls', 2000, kind: MediaKind.show, certs: {'NL': '6'}, genres: ['Drama', 'Comedy']),
];

/// The fixture title with [title] (and [year] when given), or null: a title
/// that exists nowhere in the catalogue.
EvalTitle? evalTitle(String title, [int? year]) {
  final key = assistantTitleKey(title);
  return evalTitles
          .where((t) => assistantSameTitle((key: assistantTitleKey(t.title), year: t.year), key, year))
          .firstOrNull ??
      evalTitles.where((t) => assistantTitleKey(t.title) == key).firstOrNull;
}

class _EvalFacts extends TitleFactsService {
  _EvalFacts() : super(cache: TitleFactsCache());
  @override
  Future<List<TitleFacts>> factsFor(List<TitleRef> refs) async => [
    for (final r in refs) evalTitle(r.title, r.year)?.facts ?? const TitleFacts(),
  ];
}

/// What an administrator changed on the eval server, as plain data (BP-12).
class EvalAdminState {
  /// Library ids a scan was started for, in order.
  final scans = <String>[];

  /// Item ids whose metadata was refreshed.
  final refreshed = <String>[];
  final cancelledJobs = <String>[];
  final retriedJobs = <String>[];

  /// The users of the server: name to `all` or its sorted library ids.
  final users = <String, String>{'Michel': 'all', 'Sanne': 'films', 'Oma': 'films,series'};
  final _ids = <String, String>{'Michel': 'u1', 'Sanne': 'u2', 'Oma': 'u3'};
  var _next = 4;

  Map<String, Object?> toJson() => {
    'scans': scans,
    'refreshed': refreshed,
    'cancelled_jobs': cancelledJobs,
    'retried_jobs': retriedJobs,
    'users': users,
  };
}

/// The eval server for a profile that administers it: scans, metadata, two
/// jobs (a running scan that can be cancelled, a failed one that can be
/// retried) and three users. Every change lands in [state].
class EvalAdminServer extends _EvalServer
    implements LibraryScanClient, ItemMetadataRefreshClient, RetryableJobsClient, ServerUserAdministration {
  EvalAdminServer(this.state);
  final EvalAdminState state;

  @override
  bool get supportsServerAdministration => true;
  @override
  Future<void> scanLibrary(String libraryId) async => state.scans.add(libraryId);
  @override
  Future<void> refreshItemMetadata(String itemId) async => state.refreshed.add(itemId);
  @override
  Future<List<ServerJob>> listJobs() async => [
    if (!state.cancelledJobs.contains('j1'))
      const ServerJob(
        id: 'j1',
        title: 'Bibliotheek Films scannen',
        state: ServerJobState.running,
        progress: 0.4,
        libraryId: 'films',
        cancellable: true,
      ),
    ServerJob(
      id: 'j2',
      title: 'Ondertitels ophalen',
      state: state.retriedJobs.contains('j2') ? ServerJobState.queued : ServerJobState.failed,
      error: state.retriedJobs.contains('j2') ? null : 'time-out bij de aanbieder',
      retryable: !state.retriedJobs.contains('j2'),
    ),
  ];
  @override
  Future<void> cancelJob(String jobId) async => state.cancelledJobs.add(jobId);
  @override
  Future<void> retryJob(String jobId) async => state.retriedJobs.add(jobId);

  ServerUser _user(String name) {
    final access = state.users[name]!;
    return ServerUser(
      id: state._ids[name]!,
      name: name,
      role: name == 'Michel' ? ServerUserRole.owner : ServerUserRole.member,
      allLibraries: access == 'all',
      libraryIds: access == 'all' ? const [] : access.split(','),
    );
  }

  @override
  Future<List<ServerUser>> listUsers() async => [for (final name in state.users.keys) _user(name)];
  @override
  bool get createUserRequiresPassword => false;
  @override
  bool get canChangeLibraryAccess => true;
  String _access(bool all, List<String> ids) => all ? 'all' : (List.of(ids)..sort()).join(',');
  @override
  Future<ServerUser> createUser({
    required String name,
    String? password,
    bool allLibraries = false,
    List<String> libraryIds = const [],
  }) async {
    state._ids[name] = 'u${state._next++}';
    state.users[name] = _access(allLibraries, libraryIds);
    return _user(name);
  }

  @override
  Future<void> setUserLibraryAccess(
    String userId, {
    required bool allLibraries,
    List<String> libraryIds = const [],
  }) async {
    final name = state._ids.entries.firstWhere((e) => e.value == userId).key;
    state.users[name] = _access(allLibraries, libraryIds);
  }

  @override
  Future<void> deleteUser(String userId) async {
    final name = state._ids.entries.firstWhere((e) => e.value == userId).key;
    state.users.remove(name);
  }

  @override
  Future<MediaItem?> fetchItem(String itemId) async =>
      evalTitles.where((t) => t.id == itemId).map((t) => t.item).firstOrNull;
}

class _EvalAdminManager extends MultiServerManager {
  @override
  bool canAdministerServer(ServerId id) => id.value == 'zolder';
  @override
  PlexSharingAdministration? plexSharingFor(ServerId serverId) => null;
}

class _EvalServer extends FakeServer {
  _EvalServer()
    : super(
        'zolder',
        libraries: {
          'films': [for (final t in evalTitles.where((t) => !t.isShow)) t.item],
          'series': [for (final t in evalTitles.where((t) => t.isShow)) t.item],
        },
      );
  @override
  Future<HealthStatus> checkHealth() async => HealthStatus.online;

  /// One title by its id, as a tool reads an item it showed before.
  @override
  Future<MediaItem?> fetchItem(String itemId) async => evalTitles.where((t) => t.id == itemId).firstOrNull?.item;

  /// The paged read search_catalog and find_media use, with the filters a
  /// real Jellyfin server applies (kind, search, watch state, paging).
  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    final kind = query.kind ?? libraryKind;
    final search = query.search?.toLowerCase();
    // A real server applies the genre and year filters; without them every
    // genre question returned the whole library (BP-12).
    final genres = {for (final g in query.genres ?? const <String>[]) g.toLowerCase()};
    final years = (query.years ?? const <int>[]).toSet();
    bool facet(MediaItem i) {
      final own = {for (final g in evalTitles.firstWhere((t) => t.id == i.id).genres) g.toLowerCase()};
      return (genres.isEmpty || own.any(genres.contains)) && (years.isEmpty || years.contains(i.year));
    }

    final all = [
      for (final i in libraries[libraryId] ?? const <MediaItem>[])
        if ((kind == null || i.kind == kind) &&
            (search == null || (i.title ?? '').toLowerCase().contains(search)) &&
            facet(i) &&
            (query.includeWatched || !i.isWatched) &&
            (!query.watchedOnly || i.isWatched) &&
            (!query.inProgressOnly || i.hasActiveProgress || i.isPartiallyWatched))
          i.copyWith(libraryId: libraryId),
    ];
    final page = all.skip(query.offset).take(query.limit).toList();
    return LibraryPage(items: page, totalCount: all.length, offset: query.offset);
  }
}

/// A profile with a personal source: nothing seen, a comedy taste, and three
/// unwatched picks. The watched and started titles of the fixture count as
/// seen.
AssistantPersonalServices _evalPersonal() {
  final seen = {
    for (final t in evalTitles)
      if (t.seen != EvalSeen.no) t.item.globalKey,
  };
  final picks = [
    for (final id in const ['s11', 's21', 's12']) evalTitles.firstWhere((t) => t.id == id).item,
  ];
  return AssistantPersonalServices(
    userName: 'Michel',
    recent: () async => const [],
    everSeen: () async => seen,
    taste: () async => const AffinityVector({
      'genre': {'comedy': 1.0},
    }, eventCount: 3),
    picks: (_) async => [MediaHub(id: 'rows', title: 'Voor jou', type: 'mixed', items: picks)],
  );
}

/// The tool context of one eval case: the fixture server, its two libraries,
/// facts from the fixture and the region injected, so the outcome never
/// depends on the machine's locale. [kids] makes it a children's profile
/// whose youngest child is the lowest of [kidsAges].
AssistantToolContext evalContext({
  required bool kids,
  List<int> kidsAges = const [],
  List<HouseholdKid> householdKids = const [],
  String region = 'NL',
  bool personal = false,
  EvalWorld? world,
  void Function(String name)? onSaveRow,
  // Filled with the profile's saved Home rows; the row tools read and change it.
  List<HomeCustomRow>? rowStore,
  // The profile's memory, with the saved "nothing I watched or started" (BP-11d).
  AssistantMemoryServices? memory,
}) {
  final admin = world?.admin;
  final m = admin == null ? MultiServerManager() : _EvalAdminManager();
  addTearDown(m.dispose);
  m.debugRegisterClientForTesting(admin == null ? _EvalServer() : EvalAdminServer(admin));
  if (world?.offlineServer ?? false) m.debugRegisterClientForTesting(evalOfflineServer(), online: false);
  m.setVisibleServerIds(null);
  return AssistantToolContext(
    servers: m,
    catalog: AssistantCatalogServices(
      rowLoader: CatalogHomeCustomRowLoader(
        libraries: () => [fakeLib('zolder', 'films'), fakeLib('zolder', 'series', kind: MediaKind.show)],
        isServerVisible: m.isServerVisible,
        hiddenLibraryKeys: () => const {},
        clientFor: m.getClient,
      ),
      profileId: 'p',
      activeProfileId: () => 'p',
      // A new id is a new row; a known id is an edit that keeps its place.
      saveRow: (row) async {
        final at = rowStore?.indexWhere((r) => r.id == row.id) ?? -1;
        if (at >= 0) {
          rowStore![at] = row;
        } else {
          // At the front, as `HomeLayoutProvider.saveCustomRow` does.
          rowStore?.insert(0, row);
          onSaveRow?.call(row.name);
        }
      },
      rows: rowStore == null ? null : () => List.unmodifiable(rowStore),
      removeRow: rowStore == null ? null : (id) async => rowStore.removeWhere((r) => r.id == id),
    ),
    titleFacts: _EvalFacts(),
    personal: world?.profile != null ? evalPersonalFor(world!.profile!) : (personal ? _evalPersonal() : null),
    trakt: world?.trakt,
    requests: world?.seerr == null ? null : AssistantRequestServices(client: () => world!.seerr!.client),
    watchlist: world?.watchlist?.services,
    kidsAges: () async => kidsAges,
    householdKids: () async => householdKids,
    kidsProfile: () async => kids,
    region: () => region,
    memory: world?.memoryServices ?? memory,
  );
}
