// The answers of mockup 39 E, F and G as displays, for the results test
// and the shots.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_suggestions.dart';

import '../../widgets/big_p/fake_assistant_controller.dart';

/// A controller for the shots, disposed after the test: its examples and
/// follow-ups come from [seed], so a shot shows the same pick on every run.
FakeAssistantController shotController({int seed = 1}) {
  final c = FakeAssistantController();
  BigPSuggestions.install(c, BigPSuggestions(random: Random(seed)));
  addTearDown(c.dispose);
  return c;
}

AssistantTitleTarget nasTarget(String id, String title, int year) => (
  serverId: ServerId('nas'),
  serverName: 'NAS',
  item: MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: title, year: year, serverId: 'nas'),
);

AssistantTitleMatch libraryMatch(String id, String title, int year) => AssistantTitleMatch(
  matchId: id,
  title: title,
  year: year,
  kind: 'movie',
  confidence: 'high',
  targets: [nasTarget(id, title, year)],
);

const springRequest = AssistantRequestOption(
  seerrId: 'movie:400160',
  title: 'Spring',
  year: 2019,
  kind: 'movie',
  posterUrl: '',
  overview: 'Een herder en zijn hond.',
  status: 'not_requested',
);

const spring = AssistantTitleMatch(
  matchId: 'spring',
  title: 'Spring',
  year: 2019,
  kind: 'movie',
  confidence: 'high',
  targets: [],
  request: springRequest,
);

/// 39 E: two titles in the library, one to request.
void answerTitles(FakeAssistantController c) => c
  ..prompt = 'Welke animatiefilms heb ik nog niet gezien?'
  ..answer = 'Drie nog niet. Spring staat niet op je server, die kan ik aanvragen.'
  ..state = AssistantSurfaceState.result
  ..displays = [
    AssistantTitleMatches(AssistantToolContext(servers: MultiServerManager()), [
      libraryMatch('tos', 'Tears of Steel', 2012),
      libraryMatch('ed', 'Elephants Dream', 2006),
      spring,
    ]),
  ];

/// Device feedback on build 323: a long answer over two title cards.
void answerLongTitles(FakeAssistantController c) => c
  ..prompt = 'What was added to my library lately?'
  ..answer =
      'The latest additions are mostly 2026 releases: «Tears of Steel» (2012) and «Sintel» (2010) joined alongside '
      'a handful of older favourites. Also recently added: «Elephants Dream» (2006), Caminandes (2013) and a '
      'few shorts from the Blender studio, so there is plenty to pick from tonight.'
  ..state = AssistantSurfaceState.result
  ..displays = [
    AssistantTitleMatches(AssistantToolContext(servers: MultiServerManager()), [
      libraryMatch('tos', 'Tears of Steel', 2012),
      libraryMatch('s', 'Sintel', 2010),
    ]),
  ];

/// 39 H: three titles, all in the library.
void answerLibraryTitles(FakeAssistantController c) => c
  ..prompt = 'Welke animatiefilms heb ik nog niet gezien?'
  ..answer = 'Drie nog niet.'
  ..state = AssistantSurfaceState.result
  ..displays = [
    AssistantTitleMatches(AssistantToolContext(servers: MultiServerManager()), [
      libraryMatch('tos', 'Tears of Steel', 2012),
      libraryMatch('ed', 'Elephants Dream', 2006),
      libraryMatch('s', 'Sintel', 2010),
    ]),
  ];

/// 39 F: who watched most this week.
void answerWatchStats(FakeAssistantController c) => c
  ..prompt = 'Wie heeft deze week het meest gekeken?'
  ..answer = 'Robin keek het meest, vooral Sintel.'
  ..state = AssistantSurfaceState.result
  ..displays = [
    AssistantWatchStats(
      serverName: 'NAS',
      days: 7,
      users: const [
        (name: 'Robin', plays: 36, seconds: 0),
        (name: 'Michel', plays: 19, seconds: 0),
        (name: 'Sam', plays: 17, seconds: 0),
        (name: 'Noor', plays: 8, seconds: 0),
        (name: 'Jan', plays: 3, seconds: 0),
      ],
      titles: [
        (
          title: 'Sintel',
          plays: 19,
          viewers: const ['Robin', 'Sam'],
          show: false,
          target: nasTarget('s', 'Sintel', 2010),
        ),
        (
          title: 'Caminandes',
          plays: 9,
          viewers: const ['Noor'],
          show: false,
          target: nasTarget('cam', 'Caminandes', 2016),
        ),
      ],
    ),
  ];

/// 39 G: a new user waits for the Pleya card.
AssistantPendingAction createSam({AssistantPasswordMode password = AssistantPasswordMode.none}) =>
    AssistantPendingAction(
      kind: AssistantActionKind.createUser,
      serverId: ServerId('nas'),
      serverName: 'NAS',
      subject: 'Sam',
      libraryNames: const ['Kids'],
      password: password,
      execute: ({password}) async => const {},
    );

/// One Plex server that answers every search with [items], for Zoeken.
class FakeSearchServer implements MediaServerClient {
  FakeSearchServer(this.items);

  final List<MediaItem> items;

  @override
  ServerId get serverId => ServerId('nas');

  @override
  String? get serverName => 'NAS';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<List<MediaItem>> searchItems(String query, {int limit = 100}) async => items;

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
