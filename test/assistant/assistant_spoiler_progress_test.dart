import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_spoiler_context.dart';
import 'package:pleya/assistant/assistant_spoiler_progress.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/services/jellyfin_api_cache.dart';
import 'package:pleya/services/jellyfin_auth_header.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import '../test_helpers/prefs.dart';
import 'assistant_find_fakes.dart' as find;

Map<String, dynamic> _episode(
  String id,
  int number, {
  int position = 10000,
  String type = 'Episode',
  String show = 'show',
}) => {
  'Id': id,
  'Type': type,
  'SeasonId': 'season',
  'ParentId': 'season',
  'SeriesId': show,
  'ParentIndexNumber': 1,
  'IndexNumber': number,
  'RunTimeTicks': 600000000,
  'Name': 'FUTURE_TITLE',
  'Overview': 'PARTIAL_SECRET',
  'People': [
    {'Name': 'CAST_SECRET'},
  ],
  'UserData': {'Played': position == 0, 'PlayCount': position == 0 ? 1 : 0, 'PlaybackPositionTicks': position * 10000},
};

class _Fixture {
  final requests = <http.Request>[];
  List<Object?> rows = [_episode('current', 3)];
  int? total;
  bool missingTotal = false, malformedExact = false, mismatchedExact = false, hidden = false, active = true;
  bool otherHidden = true;
  String? explicitTop;
  int reads = 0;
  Future<void> Function(http.Request)? beforeReply;
  late final JellyfinClient client = JellyfinClient.forTesting(
    connection: JellyfinConnection(
      id: 'jf/member',
      baseUrl: 'https://fixture.invalid',
      serverName: 'Jelly',
      serverMachineId: 'jf',
      userId: 'member',
      userName: 'Member',
      accessToken: 'fixture-token',
      deviceId: 'fixture-device',
      createdAt: DateTime(2026),
    ),
    httpClient: MockClient((request) async {
      requests.add(request);
      await beforeReply?.call(request);
      Object body;
      if (request.url.path.endsWith('/Resume')) {
        reads++;
        body = {'Items': rows, if (!missingTotal) 'TotalRecordCount': total ?? rows.length};
      } else if (request.url.path == '/Users/member/Views') {
        body = {
          'Items': [
            {'Id': 'library', 'Name': 'TV', 'CollectionType': 'tvshows'},
            {'Id': 'other', 'Name': 'Other', 'CollectionType': 'tvshows'},
          ],
        };
      } else if (request.url.path == '/Items' && request.url.queryParameters.containsKey('Ids')) {
        final exact = [
          for (final row in rows.whereType<Map<String, dynamic>>())
            if ((row['UserData'] as Map?)?['PlaybackPositionTicks'] != 0)
              {...row, if (explicitTop != null) 'ParentLibraryId': explicitTop, if (mismatchedExact) 'Id': 'other'},
        ];
        body = {
          'Items': malformedExact ? [null] : exact,
          'TotalRecordCount': exact.length,
        };
      } else if (request.url.path == '/Shows/show/Seasons') {
        body = {
          'Items': [
            {'Id': 'season', 'Type': 'Season', 'ParentId': 'show', 'IndexNumber': 1},
          ],
          'TotalRecordCount': 1,
        };
      } else if (request.url.path.startsWith('/Shows/')) {
        body = {'Items': [], 'TotalRecordCount': 0};
      } else if (request.url.path == '/Items' && request.url.queryParameters['ParentId'] == 'season') {
        body = {
          'Items': [
            {..._episode('earlier', 1, position: 0), 'Name': 'Earlier', 'Overview': 'SAFE_SOURCE Anna gardener'},
            _episode('current', 3),
            _episode('future', 4, position: 0),
          ],
          'TotalRecordCount': 3,
        };
      } else {
        body = {};
      }
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    }),
  );
  late final manager = MultiServerManager()..debugRegisterJellyfinClientForTesting(client);
  bool stopped = false;
  bool playbackStarted = false;
  bool profileCurrent() => active && !playbackStarted;
  List<ServerId> servers() => [
    for (final id in manager.serverIds)
      if (manager.isServerVisible(ServerId(id))) ServerId(id),
  ];
  bool visible(String server, String library) =>
      !hidden && (library == 'library' || (library == 'other' && !otherHidden));
  Future<AssistantSpoilerResumeEvidence?> discover(bool Function() cancelled) => discoverAssistantSpoilerProgress(
    profileId: 'p',
    profileCurrent: profileCurrent,
    visibleServers: servers,
    clientFor: (id) => manager.isServerOnline(id) ? manager.getClient(id) : null,
    libraryVisible: visible,
    cancelled: cancelled,
  );
  Future<AssistantSpoilerContext> build() => buildAssistantSpoilerContext(
    services: AssistantSpoilerServices(
      profileId: 'p',
      profileCurrent: profileCurrent,
      boundary: () => null,
      boundaryCurrent: (_) => false,
      libraryVisible: visible,
      resume: discover,
    ),
    clientFor: (id) => manager.getClient(ServerId(id)),
    cancelled: () => stopped,
    question: 'Anna gardener',
    cache: AssistantSpoilerIndexCache(),
  );
}

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    JellyfinApiCache.initialize(db);
    addTearDown(db.close);
  });
  _Fixture fixture() {
    final f = _Fixture();
    addTearDown(f.manager.dispose);
    return f;
  }

  test('Home no-player current-user HTTP evidence establishes corroborated position and earlier-only index', () async {
    final f = fixture();
    final result = await f.build();
    expect(result.position?.episodeId, 'current');
    expect(result.position?.positionMs, 10000);
    expect(result.matches.single.item.summary, 'SAFE_SOURCE Anna gardener');
    expect(result.index!.search(['PARTIAL_SECRET', 'FUTURE_TITLE', 'CAST_SECRET']), isEmpty);
    expect(f.reads, 2);
    for (final request in f.requests.where((r) => r.url.path.endsWith('/Resume'))) {
      expect(request.url.path, f.client.connection.resumeItemsPath);
      expect(request.url.queryParameters['userId'], 'member');
      expect(request.url.queryParameters['Limit'], '101');
      expect(request.url.queryParameters['StartIndex'], '0');
      expect(request.url.queryParameters['EnableUserData'], 'true');
      expect(request.url.queryParameters['EnableTotalRecordCount'], 'true');
      expect(request.url.queryParameters['ExcludeActiveSessions'], 'false');
      expect(request.url.queryParameters['Fields'], isNot(contains('Overview')));
    }
    for (final request in f.requests.where((r) => r.url.queryParameters.containsKey('Ids'))) {
      expect(request.url.queryParameters['userId'], 'member');
      expect(request.url.queryParameters['ParentId'], 'library');
      expect(request.url.queryParameters['Ids'], 'current');
      expect(request.url.queryParameters['Recursive'], 'true');
    }
  });

  test('raw two same-series partial episodes and concurrent partial movie remain ambiguous', () async {
    for (final second in [
      _episode('other', 4),
      _episode('movie', 1, type: 'Movie'),
      _episode('unknown', 1, type: 'Unknown'),
    ]) {
      final f = fixture()..rows.add(second);
      expect((await f.build()).position, isNull);
      expect(f.reads, 1);
    }
  });

  test('zero-progress NextUp cannot confer a persisted boundary', () async {
    final f = fixture()..rows = [_episode('nextup', 3, position: 0)];
    expect((await f.build()).position, isNull);
  });

  test('missing totals, cap, parse loss, repeat identity and scoped identity disagreement close coverage', () async {
    for (final change in <void Function(_Fixture)>[
      (f) => f.missingTotal = true,
      (f) => f.total = 101,
      (f) => f.rows = List.generate(101, (i) => _episode('episode-$i', i + 1)),
      (f) => f.total = 2,
      (f) => f.rows.add(null),
      (f) => f.rows = [
        {
          ..._episode('current', 3),
          'UserData': {'PlaybackPositionTicks': 100000000},
        },
      ],
      (f) => f.rows = [
        {
          ..._episode('current', 3),
          'UserData': {'Played': false, 'PlaybackPositionTicks': 'bad'},
        },
      ],
      (f) => f.rows.add({'Type': 'Episode'}),
      (f) => f.rows.add(_episode('current', 3)),
      (f) => f.malformedExact = true,
      (f) => f.mismatchedExact = true,
      (f) => f.explicitTop = 'other-library',
      (f) => f.explicitTop = '',
    ]) {
      final f = fixture();
      change(f);
      expect((await f.build()).position, isNull);
    }
  });

  test('hidden, cancelled or profile-changed inventory yields no source context', () async {
    for (final change in <void Function(_Fixture)>[
      (f) => f.hidden = true,
      (f) => f.active = false,
      (f) => f.playbackStarted = true,
      (f) => f.stopped = true,
    ]) {
      final f = fixture();
      f.beforeReply = (request) async {
        if (request.url.path.endsWith('/Resume')) change(f);
      };
      final result = await f.build();
      expect(result.position, isNull);
      expect(result.matches, isEmpty);
    }
  });

  test('fresh persisted progress is re-read after retrieval; moved position closes context', () async {
    final f = fixture();
    f.beforeReply = (request) async {
      if (request.url.path == '/Items' && request.url.queryParameters['ParentId'] == 'season') {
        f.rows = [_episode('current', 3, position: 20000)];
      }
    };
    expect((await f.build()).position, isNull);
    expect(f.reads, 2);
  });

  test('unsupported visible backend prevents uniqueness even beside a supported source', () async {
    final f = fixture();
    final result = await discoverAssistantSpoilerProgress(
      profileId: 'p',
      profileCurrent: f.profileCurrent,
      visibleServers: () => [...f.servers(), ServerId('unsupported')],
      clientFor: (id) => id.value == 'unsupported' ? find.FakeServer('unsupported') : f.client,
      libraryVisible: f.visible,
      cancelled: () => false,
    );
    expect(result, isNull);
    expect(f.requests, isEmpty);
  });

  test('live source, newly visible root or new playback invalidates built persisted evidence', () async {
    for (final change in <void Function(_Fixture)>[
      (f) => f.hidden = true,
      (f) => f.otherHidden = false,
      (f) => f.playbackStarted = true,
      (f) => f.active = false,
      (f) => f.stopped = true,
    ]) {
      final f = fixture();
      final result = await f.build();
      expect(result.position, isNotNull);
      change(f);
      expect(result.current(), isFalse);
      expect(result.answer('English'), isNot(contains('SAFE_SOURCE')));
    }
  });
}
