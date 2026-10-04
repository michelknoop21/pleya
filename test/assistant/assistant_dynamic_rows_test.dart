import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/services/jellyfin_api_cache.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_entitlement.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/providers/home_layout_provider.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/unified_catalog/home_custom_row.dart';
import 'package:pleya/services/unified_catalog/home_custom_row_loader.dart';
import 'package:pleya/utils/media_server_http_client.dart' show AbortController;

import '../test_helpers/prefs.dart';

AssistantTool _tool(String name) => assistantTools.firstWhere((tool) => tool.name == name);

Map<String, Object?> _film(String id, {int? minutes = 90, List<String>? genres = const ['Sci-Fi']}) => {
  'Id': id,
  'Name': 'Film $id',
  'Type': 'Movie',
  'ProductionYear': 2024,
  'ParentLibraryId': 'films',
  'OfficialRating': 'PG-13',
  if (minutes != null) 'RunTimeTicks': minutes * 60 * 10000000,
  'Genres': ?genres,
  'UserData': {'Played': false},
  'MediaSources': [
    {
      'Id': 'source',
      'MediaStreams': [
        {'Index': 0, 'Type': 'Audio', 'Language': 'nld'},
        {'Index': 1, 'Type': 'Subtitle', 'Language': 'eng'},
      ],
    },
  ],
};

class _Fixture {
  final details = <String, Map<String, Object?>>{};
  final requests = <http.Request>[];
  final hidden = <String>{};
  final failedDetails = <String>{};
  final cancelled = AbortController();
  String profile = 'p';
  bool exact = true;
  Future<void> Function(http.Request)? beforeReply;
  late MultiServerManager manager;
  late CatalogHomeCustomRowLoader loader;
  late HomeLayoutProvider layout;
  late AssistantToolContext context;

  Future<void> initialize() async {
    layout = HomeLayoutProvider(profileId: 'p');
    await layout.ensureInitialized();
    addTearDown(layout.dispose);
    final client = JellyfinClient.forTesting(
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
        var status = 200;
        if (request.url.path == '/Users/Me') {
          body = {
            'Id': 'member',
            'Policy': {'IsAdministrator': false},
          };
        } else if (request.url.path == '/Users/member/Views') {
          body = {
            'Items': [
              {'Id': 'films', 'Name': 'Films', 'CollectionType': 'movies'},
            ],
          };
        } else if (request.url.path == '/Persons') {
          body = {
            'Items': [
              {'Id': 'person', 'Name': 'Person'},
            ],
          };
        } else if (request.url.path == '/Items') {
          final query = request.url.queryParameters;
          // Simulate the native singleton filters independently; browse DTOs
          // intentionally omit Genres/MediaSources, like the actual client.
          final films = details.values.where((item) {
            if (query['Genres'] case final String genre) {
              if (!genre.split('|').any((g) => (item['Genres'] as List? ?? []).contains(g))) return false;
            }
            if (query['OfficialRatings'] case final String rating) {
              if (!rating.split('|').contains(item['OfficialRating'] as String?)) return false;
            }
            return true;
          }).toList();
          body = {
            'Items': [
              for (final item in films)
                {
                  for (final entry in item.entries)
                    if (!{'Genres', 'MediaSources'}.contains(entry.key)) entry.key: entry.value,
                },
            ],
            'TotalRecordCount': exact ? films.length : 1000,
          };
        } else if (request.url.path.startsWith('/Users/member/Items/')) {
          body = details[request.url.path.split('/').last] ?? {};
          if ((body as Map).isEmpty) status = 404;
          if (failedDetails.contains(request.url.path.split('/').last)) status = 500;
        } else {
          body = {};
          status = 404;
        }
        return http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
      }),
    );
    manager = MultiServerManager()..debugRegisterJellyfinClientForTesting(client);
    addTearDown(manager.dispose);
    loader = CatalogHomeCustomRowLoader(
      libraries: () => [
        const MediaLibrary(
          id: 'films',
          backend: MediaBackend.jellyfin,
          title: 'Films',
          kind: MediaKind.movie,
          serverId: 'jf',
        ),
      ],
      isServerVisible: manager.isServerVisible,
      hiddenLibraryKeys: () => hidden,
      clientFor: manager.getClient,
    );
    context = AssistantToolContext(
      servers: manager,
      cancel: cancelled,
      catalog: AssistantCatalogServices(
        rowLoader: loader,
        profileId: 'p',
        activeProfileId: () => profile,
        saveRow: layout.saveCustomRow,
      ),
    );
  }

  Future<Map<String, Object?>> search(Map<String, Object?> args, {AssistantToolContext? ctx}) async =>
      (await _tool('search_catalog').run(ctx ?? context, null, {'kind': 'movie', ...args}) as AssistantToolResult).data;

  Future<AssistantPendingAction> create(Map<String, Object?> result, {AssistantToolContext? ctx}) async =>
      await _tool('create_home_row').run(ctx ?? context, null, {'query_id': result['query_id'], 'title': 'Filmavond'})
          as AssistantPendingAction;
}

List<Object?> _ids(Map<String, Object?> result) => [
  for (final item in result['results'] as List) (item as Map)['item_id'],
];

const _config = AssistantProviderConfig(
  kind: AssistantProviderKind.ollamaServer,
  baseUrl: 'http://fixture.invalid',
  model: 'fixture',
);

class _Entitlement extends AssistantEntitlement {
  AssistantEntitlementState state = AssistantEntitlementState.entitled;
  @override
  Future<AssistantEntitlementState> check() async => state;
}

class _Model extends AssistantModelClient {
  _Model(this.replies) : super(_config, httpClient: MockClient((_) async => http.Response('', 500)));
  final List<AssistantReply> replies;
  @override
  Future<AssistantReply> chat(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools, {
    AbortController? abort,
  }) async => replies.isEmpty ? _reply() : replies.removeAt(0);
}

AssistantReply _reply([String? name, Map<String, Object?> args = const {}]) {
  final calls = name == null
      ? <AssistantToolCall>[]
      : [AssistantToolCall(id: 'call', name: name, arguments: jsonEncode(args))];
  return AssistantReply(
    content: name == null ? 'Done' : '',
    toolCalls: calls,
    message: {
      'role': 'assistant',
      'content': '',
      'tool_calls': [
        for (final call in calls)
          {
            'id': call.id,
            'type': 'function',
            'function': {'name': call.name, 'arguments': call.arguments},
          },
      ],
    },
  );
}

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    JellyfinApiCache.initialize(db);
    addTearDown(db.close);
  });

  for (final route in ['text', 'person']) {
    for (final constraint in ['audio_languages', 'official_ratings']) {
      test('$route + $constraint keeps genre OR after hydration with positive evidence', () async {
        final wrong = _film('wrong', genres: ['Sci-Fi', 'Horror'])
          ..['OfficialRating'] = 'R'
          ..['MediaSources'] = [
            {
              'Id': 'source',
              'MediaStreams': [
                {'Index': 0, 'Type': 'Audio', 'Language': 'deu'},
              ],
            },
          ];
        final fixture = _Fixture()
          ..details.addAll({
            'yes': _film('yes'),
            'no': _film('no', genres: ['Drama']),
            'unknown': _film('unknown', genres: null),
            'wrong': wrong,
          });
        await fixture.initialize();
        final args = <String, Object?>{
          route: route == 'text' ? 'Film' : 'Person',
          'genres': ['Sci-Fi', 'Horror'],
          constraint: constraint == 'audio_languages' ? ['nld'] : ['PG-13'],
        };
        final result = await fixture.search(args);
        expect(_ids(result), ['yes']);
        expect(result['can_become_home_row'], isFalse);
        expect((result['coverage'] as Map)['excluded_metadata_or_watch'], 3);
        expect(fixture.requests.any((r) => r.url.path == '/Users/member/Items/yes'), isTrue);

        // A genuine strict temporary constraint continues to require ALL
        // genres, even though the same singleton audio/rating is present.
        final strict = await fixture.search({...args, 'max_runtime_minutes': 120});
        expect(_ids(strict), isEmpty);
      });
    }
  }

  test('runtime and exclusion hydrate sparse Jellyfin browse metadata; unknown never matches or saves', () async {
    final fixture = _Fixture();
    fixture.details.addAll({
      'yes': _film('yes', minutes: 119),
      'boundary': _film('boundary', minutes: 120),
      'long': _film('long', minutes: 121),
      'excluded': _film('excluded', genres: ['Sci-Fi', 'Horror']),
      'unknown': _film('unknown', minutes: null, genres: null),
    });
    await fixture.initialize();
    final result = await fixture.search({
      'genres': ['Sci-Fi'],
      'exclude_genres': ['Horror'],
      'max_runtime_minutes': 119,
      'unwatched': true,
    });
    expect(_ids(result), ['yes']);
    expect(result['can_become_home_row'], isFalse);
    expect(result['home_row_unavailable_reason'], isNotEmpty);
    expect(fixture.requests.any((r) => r.url.path == '/Users/member/Items/yes'), isTrue);
    await expectLater(fixture.create(result), throwsA(isA<AssistantToolError>()));
    expect(fixture.layout.customRows, isEmpty);
  });

  test('nested Jellyfin parent is not mistaken for a different top-level library', () async {
    final nested = _film('nested')
      ..remove('ParentLibraryId')
      ..['ParentId'] = 'nested-folder';
    final fixture = _Fixture()..details['nested'] = nested;
    await fixture.initialize();
    final result = await fixture.search({
      'subtitle_languages': ['en'],
    });
    expect(_ids(result), ['nested']);
  });

  test('under two hours includes fractional minutes and excludes exactly two hours', () async {
    final almost = _film('almost')..['RunTimeTicks'] = (120 * 60 - 1) * 10000000;
    final fixture = _Fixture()..details.addAll({'almost': almost, 'exact': _film('exact', minutes: 120)});
    await fixture.initialize();
    final result = await fixture.search({'max_runtime_minutes': 120, 'max_runtime_exclusive': true});
    expect(_ids(result), ['almost']);
    expect(result['can_become_home_row'], isFalse);
  });

  test('multiple required audio languages and subtitles stay temporary and require proved tracks', () async {
    final fixture = _Fixture()..details['nl'] = _film('nl');
    await fixture.initialize();
    final matches = await fixture.search({
      'subtitle_languages': ['en'],
      'audio_languages': ['nl'],
    });
    expect(_ids(matches), ['nl']);
    expect(matches['can_become_home_row'], isFalse);
    final noMatch = await fixture.search({
      'audio_languages': ['nl', 'de'],
    });
    expect(_ids(noMatch), isEmpty);
    expect(noMatch['can_become_home_row'], isFalse);
    expect(noMatch['home_row_unavailable_reason'], isNotEmpty);
  });

  test('supported query survives confirmation, layout reload, refresh and native filter replay', () async {
    final fixture = _Fixture()..details['yes'] = _film('yes');
    await fixture.initialize();
    final result = await fixture.search({
      'genres': ['Sci-Fi'],
      'audio_languages': ['nld'],
      'official_ratings': ['PG-13'],
      'year_from': 2023,
      'year_to': 2024,
      'unwatched': true,
      'sort': 'released',
    });
    expect(result['can_become_home_row'], isTrue);
    final action = await fixture.create(result);
    expect(fixture.layout.customRows, isEmpty);
    await action.execute();
    final reload = HomeLayoutProvider(profileId: 'p');
    addTearDown(reload.dispose);
    await reload.ensureInitialized();
    await reload.refresh();
    final row = HomeCustomRow.decode(reload.customRows.single.encode())!;
    expect(row.filters.audioLanguages, {'nld'});
    expect(row.filters.officialRatings, {'PG-13'});
    expect(row.filters.genres, {'Sci-Fi'});
    expect(row.filters.years, {2023, 2024});
    expect(row.filters.serverIds, {'jf'});
    fixture.requests.clear();
    final content = await fixture.loader.load(row, limit: 20);
    expect(content.groups.single.representativeSource.item.id, 'yes');
    final query = fixture.requests.single.url.queryParameters;
    expect(query['AudioLanguages'], 'nld');
    expect(query['OfficialRatings'], 'PG-13');
    expect(query['Genres'], 'Sci-Fi');
    expect(query['Years'], '2023,2024');
    expect(query['Filters'], 'IsUnplayed');
    expect(query['SortBy'], 'PremiereDate');
    expect(query['SortOrder'], 'Descending');
  });

  test('native genre OR query preserves every requested value instead of truncating before save', () async {
    final fixture = _Fixture()..details['yes'] = _film('yes');
    await fixture.initialize();
    final result = await fixture.search({
      'genres': ['Sci-Fi', 'Drama', 'Comedy', 'Family', 'Thriller', 'Horror'],
    });
    await (await fixture.create(result)).execute();
    expect(fixture.layout.customRows.single.filters.genres, {
      'Sci-Fi',
      'Drama',
      'Comedy',
      'Family',
      'Thriller',
      'Horror',
    });
  });

  test('an open year window stays temporary rather than freezing its future upper bound', () async {
    final fixture = _Fixture()..details['yes'] = _film('yes');
    await fixture.initialize();
    final result = await fixture.search({'year_from': 2023});
    expect(result['can_become_home_row'], isFalse);
    expect(result['home_row_unavailable_reason'], isNotEmpty);
  });

  test('hiding a candidate during metadata hydration cannot publish or later save it', () async {
    final fixture = _Fixture()..details['yes'] = _film('yes');
    await fixture.initialize();
    fixture.beforeReply = (request) async {
      if (request.url.path == '/Users/member/Items/yes') fixture.hidden.add('jf:films');
    };
    await expectLater(
      fixture.search({
        'exclude_genres': ['Horror'],
      }),
      throwsA(isA<AssistantToolError>().having((e) => e.code, 'code', 'catalog_changed')),
    );
    expect(fixture.layout.customRows, isEmpty);
  });

  test('confirmation rechecks visibility and task cancellation before any row write', () async {
    for (final cancel in [false, true]) {
      final fixture = _Fixture()..details['yes'] = _film('yes');
      await fixture.initialize();
      final result = await fixture.search({
        'audio_languages': ['nld'],
      });
      final action = await fixture.create(result);
      if (cancel) {
        fixture.cancelled.abort();
      } else {
        fixture.manager.setVisibleServerIds({});
      }
      await expectLater(action.execute(), throwsA(isA<AssistantToolError>()));
      expect(fixture.layout.customRows, isEmpty);
    }
  });

  test('a known server authorization failure voids a pending row card', () async {
    final fixture = _Fixture()..details['yes'] = _film('yes');
    await fixture.initialize();
    final result = await fixture.search({
      'audio_languages': ['nld'],
    });
    final action = await fixture.create(result);
    fixture.manager.debugMarkAuthErrorForTesting(ServerId('jf'));
    await expectLater(action.execute(), throwsA(isA<AssistantToolError>()));
    expect(fixture.layout.customRows, isEmpty);
  });

  test('a profile switch during hydration aborts publication', () async {
    final fixture = _Fixture()..details['yes'] = _film('yes');
    await fixture.initialize();
    fixture.beforeReply = (request) async {
      if (request.url.path == '/Users/member/Items/yes') fixture.profile = 'other';
    };
    await expectLater(
      fixture.search({
        'subtitle_languages': ['en'],
      }),
      throwsA(isA<AssistantToolError>().having((e) => e.code, 'code', 'profile_changed')),
    );
  });

  test('failed detail reads exclude exactly one candidate with explicit partial coverage', () async {
    final fixture = _Fixture()..details.addAll({'a': _film('a'), 'b': _film('b'), 'c': _film('c')});
    await fixture.initialize();
    fixture.beforeReply = (request) async {
      if (request.url.path == '/Users/member/Items/b') fixture.failedDetails.add('b');
    };
    final result = await fixture.search({'max_runtime_minutes': 100});
    expect(_ids(result), ['a', 'c']);
    expect(result['partial'], isTrue);
    expect((result['coverage'] as Map)['unavailable_metadata'], 1);
  });

  test('strict unseen rejects detail watch state that became unknown', () async {
    final fixture = _Fixture()..details['yes'] = _film('yes');
    await fixture.initialize();
    fixture.beforeReply = (request) async {
      if (request.url.path == '/Users/member/Items/yes') fixture.details['yes']!.remove('UserData');
    };
    final result = await fixture.search({'max_runtime_minutes': 100, 'unwatched': true});
    expect(_ids(result), isEmpty);
  });

  test('hidden libraries are excluded before any detail read', () async {
    final fixture = _Fixture()..details['yes'] = _film('yes');
    await fixture.initialize();
    fixture.hidden.add('jf:films');
    final result = await fixture.search({
      'subtitle_languages': ['en'],
    });
    expect(_ids(result), isEmpty);
    expect(fixture.requests, isEmpty);
  });

  test('bounded temporary filters report sampling when the catalog exceeds the candidate cap', () async {
    final fixture = _Fixture()..exact = false;
    for (var i = 0; i < 120; i++) {
      fixture.details['f$i'] = _film('f$i');
    }
    await fixture.initialize();
    final result = await fixture.search({'max_runtime_minutes': 100});
    expect(result['sampled'], isTrue);
    expect((result['coverage'] as Map)['candidates_checked'], 100);
    expect(fixture.requests.where((r) => r.url.path.startsWith('/Users/member/Items/')), hasLength(100));
  });

  test('two real controller tasks keep their q1 row authorities isolated', () async {
    final fixture = _Fixture()..details['yes'] = _film('yes');
    await fixture.initialize();
    final models = [
      _Model([
        _reply('split_tasks', {
          'tasks': [
            {'title': 'Saved', 'intent': 'search', 'prompt': 'NL audio'},
            {'title': 'Temporary', 'intent': 'search', 'prompt': 'Under two hours'},
          ],
        }),
      ]),
      _Model([
        _reply('search_catalog', {
          'kind': 'movie',
          'audio_languages': ['nld'],
        }),
        _reply('create_home_row', {'query_id': 'q1', 'title': 'NL films'}),
      ]),
      _Model([
        _reply('search_catalog', {'kind': 'movie', 'max_runtime_minutes': 120}),
        _reply('create_home_row', {'query_id': 'q1', 'title': 'Runtime'}),
      ]),
    ];
    var next = 0;
    final controller = AssistantController(
      buildContext: (_) => fixture.context,
      entitlement: _Entitlement(),
      loadConfig: () async => _config,
      modelFor: (_) => models[next++],
      tools: [_tool('search_catalog'), _tool('create_home_row')],
    );
    addTearDown(controller.dispose);
    final done = controller.submit('Two film rows');
    await pumpEventQueue(times: 50);
    final pending = controller.pendingConfirmation;
    expect(pending, isNotNull);
    controller.confirmTask(pending!.taskId, pending.id);
    await done;
    expect(controller.tasks.map((t) => t.status), [AssistantTaskStatus.completed, AssistantTaskStatus.failed]);
    expect(controller.tasks.last.error, 'query_not_row_compatible');
    expect(fixture.layout.customRows.single.name, 'NL films');
    expect(fixture.layout.customRows.single.filters.audioLanguages, {'nld'});
  });

  test('row confirmation uses the live entitlement gate', () async {
    final fixture = _Fixture()..details['yes'] = _film('yes');
    await fixture.initialize();
    final entitlement = _Entitlement();
    final model = _Model([
      _reply('search_catalog', {
        'kind': 'movie',
        'audio_languages': ['nld'],
      }),
      _reply('create_home_row', {'query_id': 'q1', 'title': 'NL films'}),
    ]);
    final controller = AssistantController(
      buildContext: (_) => fixture.context,
      entitlement: entitlement,
      loadConfig: () async => _config,
      modelFor: (_) => model,
      tools: [_tool('search_catalog'), _tool('create_home_row')],
    );
    addTearDown(controller.dispose);
    final done = controller.submit('Save NL films');
    await pumpEventQueue(times: 50);
    final pending = controller.pendingConfirmation;
    expect(pending, isNotNull);
    entitlement.state = AssistantEntitlementState.notEntitled;
    controller.confirmTask(pending!.taskId, pending.id);
    await done;
    expect(fixture.layout.customRows, isEmpty);
    expect(controller.tasks.single.error, 'not_entitled');
  });

  test('query ids belong to originating fresh task context', () async {
    final fixture = _Fixture()..details['yes'] = _film('yes');
    await fixture.initialize();
    final first = fixture.context.fresh();
    final second = fixture.context.fresh();
    final result = await fixture.search({
      'audio_languages': ['nld'],
    }, ctx: first);
    await expectLater(fixture.create(result, ctx: second), throwsA(isA<AssistantToolError>()));
    final secondResult = await fixture.search({'max_runtime_minutes': 100}, ctx: second);
    expect(secondResult['query_id'], result['query_id']);
    await expectLater(fixture.create(secondResult, ctx: second), throwsA(isA<AssistantToolError>()));
    await (await fixture.create(result, ctx: first)).execute();
    expect(fixture.layout.customRows.single.filters.audioLanguages, {'nld'});
  });
}
