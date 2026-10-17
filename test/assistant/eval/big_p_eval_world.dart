import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_memory.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/assistant/assistant_trakt_services.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/models/trakt/trakt_ids.dart';
import 'package:pleya/models/trakt/trakt_title.dart';
import 'package:pleya/services/recommendations/taste_profile.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';

import '../assistant_find_fakes.dart';
import '../assistant_memory_support.dart';
import '../../services/memory/memory_test_support.dart';
import 'big_p_eval_fixtures.dart';

// Extra surroundings of the Big P evaluation set (BP-11a2): a second profile
// of the household, a second server that is offline, Trakt and Seerr with
// static fake data, and profile memory. Each piece is a builder; a case asks
// for the ones it needs through [EvalWorld], and `evalContext(world:)` wires
// them in next to the fixture server. The catalogue of big_p_eval_fixtures
// stays untouched, so the existing cases keep their meaning.

/// Which household member a profile builder speaks for.
class EvalProfile {
  const EvalProfile(this.name, {required this.seenIds, required this.pickIds, required this.tasteGenre});
  final String name;

  /// Fixture ids this profile watched or started.
  final Set<String> seenIds;

  /// Fixture ids of its unwatched picks, in order.
  final List<String> pickIds;
  final String tasteGenre;
}

/// The main profile of the fixture ("Michel"): the same seen set and picks
/// as `personal: true`.
const evalMichel = EvalProfile(
  'Michel',
  seenIds: {'m12', 'm36', 's06', 's07', 's08', 's09', 's10'},
  pickIds: ['s11', 's21', 's12'],
  tasteGenre: 'comedy',
);

/// The partner profile: watched other titles than Michel and shares none of
/// his seen titles or picks. The fixture servers carry only Michel's watch
/// state (`EvalTitle.seen`), so a case as Sanne would measure his; a second
/// profile reaches the checks through `EvalOnlyProfile` and memory.
const evalSanne = EvalProfile(
  'Sanne',
  seenIds: {'m06', 'm28', 'm33', 's22', 'm22'},
  pickIds: ['m09', 'm24', 's20'],
  tasteGenre: 'family',
);

AssistantPersonalServices evalPersonalFor(EvalProfile p) {
  EvalTitle byId(String id) => evalTitles.firstWhere((t) => t.id == id);
  final seen = {for (final id in p.seenIds) byId(id).item.globalKey};
  final picks = [for (final id in p.pickIds) byId(id).item];
  return AssistantPersonalServices(
    userName: p.name,
    recent: () async => const [],
    everSeen: () async => seen,
    taste: () async => AffinityVector({
      'genre': {p.tasteGenre: 1.0},
    }, eventCount: 3),
    picks: (_) async => [MediaHub(id: 'rows', title: 'Voor ${p.name}', type: 'mixed', items: picks)],
  );
}

/// The titles on the second server. None is on the main server.
const evalOfflineTitles = <(String, String, int)>[
  ('k01', 'De Wereld van Sofie', 1999),
  ('k02', 'Het Eiland', 2015),
  ('k03', 'Tirza', 2010),
];

/// A second library server that is registered but offline: its libraries
/// cannot be read, and Big P must say so rather than skip it.
FakeServer evalOfflineServer() => _OfflineServer(
  'kelder',
  libraries: {
    'films': [
      for (final (id, title, year) in evalOfflineTitles)
        MediaItem(id: id, backend: MediaBackend.jellyfin, kind: MediaKind.movie, title: title, year: year),
    ],
  },
);

/// A watchlist on Trakt: two titles the library has (Coco, Interstellar) and
/// two it does not (Primer, Severance), one film and one series each.
AssistantTraktServices evalTrakt({String? blockedBy, List<TraktTitle>? titles}) =>
    AssistantTraktServices(blocked: () => blockedBy, watchlist: () async => titles ?? evalTraktTitles);

const evalTraktTitles = <TraktTitle>[
  TraktTitle(title: 'Coco', year: 2017, ids: TraktIds(trakt: 1, tmdb: 354912), isShow: false),
  TraktTitle(title: 'Interstellar', year: 2014, ids: TraktIds(trakt: 2, tmdb: 157336), isShow: false),
  TraktTitle(title: 'Primer', year: 2004, ids: TraktIds(trakt: 3, tmdb: 14337), isShow: false),
  TraktTitle(title: 'Severance', year: 2022, ids: TraktIds(trakt: 4, tmdb: 95396), isShow: true),
];

/// A Seerr that knows Primer (film) and Severance (series) and nothing else.
FakeSeerr evalSeerr() => FakeSeerr()
  ..search['Primer'] = [
    {
      'id': 14337,
      'mediaType': 'movie',
      'title': 'Primer',
      'releaseDate': '2004-10-08',
      'originalLanguage': 'en',
      'voteCount': 1500,
    },
  ]
  ..search['Severance'] = [
    {
      'id': 95396,
      'mediaType': 'tv',
      'name': 'Severance',
      'firstAirDate': '2022-02-18',
      'originalLanguage': 'en',
      'voteCount': 4000,
    },
  ]
  ..details['/auth/me'] = {'id': 7, 'permissions': SeerrPermission.request}
  ..details['/movie/14337'] = {'id': 14337, 'title': 'Primer', 'releaseDate': '2004-10-08'}
  ..details['/tv/95396'] = {
    'id': 95396,
    'name': 'Severance',
    'firstAirDate': '2022-02-18',
    'seasons': [
      for (final n in [0, 1, 2]) {'seasonNumber': n, 'episodeCount': 9},
    ],
  };

/// The memory of two profiles on one in-memory database, so a case can prove
/// that a fact of one never reaches the other.
class EvalMemory {
  EvalMemory._(this.michel, this.sanne, this.db);
  final MemoryProfile michel;
  final MemoryProfile sanne;
  final AppDatabase db;

  static Future<EvalMemory> open({List<String> michelFacts = const [], List<String> sanneFacts = const []}) async {
    await resetMemoryPrefs();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final michel = MemoryProfile(db, 'michel');
    final sanne = MemoryProfile(db, 'sanne');
    for (final f in michelFacts) {
      await michel.store(f);
    }
    for (final f in sanneFacts) {
      await sanne.store(f);
    }
    return EvalMemory._(michel, sanne, db);
  }

  AssistantMemoryServices get services => michel.services;
}

/// What a case adds around the fixture server. Every field is optional;
/// the default is the plain fixture of `evalContext`.
class EvalWorld {
  const EvalWorld({
    this.profile,
    this.offlineServer = false,
    this.trakt,
    this.seerr,
    this.memory,
    this.memoryOfSecond = false,
  });

  /// The asking profile's personal source; overrides `personal: true`.
  final EvalProfile? profile;

  /// Register the second server, offline.
  final bool offlineServer;
  final AssistantTraktServices? trakt;
  final FakeSeerr? seerr;
  final EvalMemory? memory;

  /// The asking profile is the second one of [memory] (Sanne).
  final bool memoryOfSecond;

  AssistantMemoryServices? get memoryServices =>
      memory == null ? null : (memoryOfSecond ? memory!.sanne.services : memory!.services);
}

class _OfflineServer extends FakeServer {
  _OfflineServer(super.id, {super.libraries});
  @override
  Future<HealthStatus> checkHealth() async => HealthStatus.offline;
}
