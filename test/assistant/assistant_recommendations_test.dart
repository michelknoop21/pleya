import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/assistant/assistant_playback.dart';
import 'package:pleya/profiles/profile_server_identity.dart';
import 'package:pleya/assistant/assistant_strict_filters.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_entitlement.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/unified_catalog/home_custom_row.dart';
import 'package:pleya/services/unified_catalog/home_custom_row_loader.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/utils/media_server_http_client.dart' show AbortController;

import '../test_helpers/prefs.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, Object?> _policy({bool all = true, bool disabled = false}) => {
  'IsAdministrator': false,
  'IsDisabled': disabled,
  'EnableAllFolders': all,
  'EnabledFolders': <String>[],
};
Map<String, Object?> _dto(String id, {Object? played = false}) => {
  'Id': id,
  'Name': 'Film $id',
  'Type': 'Movie',
  'ProductionYear': 2001,
  'RunTimeTicks': 90 * 60 * 10000000,
  'Genres': ['Comedy'],
  'OfficialRating': 'PG',
  'CommunityRating': 8.0,
  'UserData': {if (played != null) 'Played': played},
  'MediaSources': [
    {
      'Id': 'v',
      'MediaStreams': [
        {'Index': 0, 'Type': 'Audio', 'Language': 'eng'},
        {'Index': 1, 'Type': 'Subtitle', 'Language': 'nld'},
      ],
    },
  ],
};

class _Loader implements HomeCustomRowLoader {
  _Loader(this.ids);
  final List<String> ids;
  final rows = <HomeCustomRow>[];
  bool exact = true;
  MediaKind kind = MediaKind.movie;

  /// Extra copies of a title on the same server, in "Films 4K".
  final copies = <String, List<String>>{};
  @override
  Future<HomeCustomRowContent> load(HomeCustomRow row, {required int limit}) async {
    rows.add(row);
    return HomeCustomRowContent(
      isExact: exact,
      groups: [for (final id in ids.take(limit)) _group(id, kind: kind, copies: copies[id] ?? const [])],
    );
  }
}

UnifiedMediaGroup _group(String id, {MediaKind kind = MediaKind.movie, List<String> copies = const []}) {
  UnifiedMediaSource copy(String itemId, String libraryId) => UnifiedMediaSource.fromItem(
    MediaItem(
      id: itemId,
      backend: MediaBackend.jellyfin,
      kind: kind,
      title: 'Film $id',
      serverId: 'jf',
      libraryId: libraryId,
    ),
  );
  final source = copy(id, 'films');
  return UnifiedMediaGroup(
    groupId: id,
    identity: CanonicalMediaIdentity.movie(title: 'Film $id', year: 2001),
    sources: [source, for (final extra in copies) copy(extra, 'films4k')],
    representativeSourceKey: source.sourceKey,
    watchState: UnifiedWatchState(representativeSourceKey: source.sourceKey, isWatched: false),
  );
}

class _Fixture {
  final calls = <http.Request>[];
  final played = <String, Object?>{};
  final denied = <String>{};
  final policies = <String, Map<String, Object?>>{};
  final dtos = <String, Map<String, Object?>>{};
  final exactDtos = <String, Map<String, Object?>>{};
  final users = <Map<String, Object?>>[
    {'Id': 'admin', 'Name': 'Admin', 'Policy': _policy()},
    {'Id': 'a', 'Name': 'Alice', 'Policy': _policy()},
    {'Id': 'b', 'Name': 'Bob', 'Policy': _policy()},
  ];
  bool admin = true;
  String meId = 'admin';
  String profile = 'p';
  Future<void> Function(http.Request)? beforeReply;
  late MultiServerManager manager;
  late JellyfinClient client;
  late _Loader loader;
  List<ProfileServerIdentity> aliases = [];
  final cancel = AbortController();

  AssistantToolContext context(List<String> ids, {bool localAdmin = true, bool emby = false}) {
    loader = _Loader(ids);
    client = JellyfinClient.forTesting(
      connection: JellyfinConnection(
        id: 'jf/admin',
        baseUrl: 'https://fixture.invalid',
        serverName: 'Jelly',
        serverMachineId: 'jf',
        userId: 'admin',
        userName: 'Admin',
        accessToken: 'fixture-token',
        deviceId: 'fixture-device',
        isAdministrator: localAdmin,
        isEmby: emby,
        createdAt: DateTime(2026),
      ),
      httpClient: MockClient((r) async {
        calls.add(r);
        await beforeReply?.call(r);
        if (r.url.path == '/Items')
          return _json({
            'Items': [for (final id in ids) dtos[id] ?? _dto(id)],
            'TotalRecordCount': ids.length,
          });
        if (r.url.path == '/Users/Me')
          return _json({
            'Id': meId,
            'Policy': {..._policy(), 'IsAdministrator': admin},
          });
        if (r.url.path == '/Users') return _json(users);
        if (r.url.path.startsWith('/Users/')) {
          final id = r.url.path.split('/').last;
          return _json({'Id': id, 'Policy': policies[id] ?? _policy()});
        }
        if (r.url.path.startsWith('/Items/')) {
          final id = r.url.path.split('/').last;
          final key = '${r.url.queryParameters['userId']}/$id';
          if (denied.contains(key)) return _json({}, 404);
          return _json(exactDtos[key] ?? dtos[id] ?? _dto(id, played: played.containsKey(key) ? played[key] : false));
        }
        return _json({}, 404);
      }),
    );
    manager = MultiServerManager()..debugRegisterJellyfinClientForTesting(client);
    addTearDown(manager.dispose);
    return AssistantToolContext(
      servers: manager,
      cancel: cancel,
      catalog: AssistantCatalogServices(
        rowLoader: loader,
        profileId: 'p',
        activeProfileId: () => profile,
        participantProfiles: (_) async => aliases,
      ),
    );
  }
}

Future<AssistantToolResult> _recommend(AssistantToolContext ctx, [Map<String, Object?> extra = const {}]) async =>
    await assistantTools.firstWhere((t) => t.name == 'recommend_together').run(ctx, ServerId('jf'), {
          'participants': ['Alice', 'Bob'],
          'kind': 'movie',
          ...extra,
        })
        as AssistantToolResult;

const _config = AssistantProviderConfig(
  kind: AssistantProviderKind.ollamaServer,
  baseUrl: 'http://fixture.invalid',
  model: 'fixture',
);

class _Entitlement extends AssistantEntitlement {
  @override
  Future<AssistantEntitlementState> check() async => AssistantEntitlementState.entitled;
}

class _Model extends AssistantModelClient {
  _Model(this.replies) : super(_config, httpClient: MockClient((_) async => _json({})));
  final List<AssistantReply> replies;
  Completer<void>? closingEntered;
  Completer<void>? closingRelease;
  @override
  Future<AssistantReply> chat(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools, {
    AbortController? abort,
  }) async {
    if (replies.length == 1 && closingEntered != null) {
      closingEntered!.complete();
      await closingRelease!.future;
    }
    return replies.isEmpty ? _reply() : replies.removeAt(0);
  }
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
      'content': name == null ? 'Done' : '',
      if (name != null)
        'tool_calls': [
          {
            'id': 'call',
            'type': 'function',
            'function': {'name': name, 'arguments': jsonEncode(args)},
          },
        ],
    },
  );
}

void main() {
  setUp(() => resetSharedPreferencesForTest());
  test('two truly unseen titles survive watched and inaccessible exclusions', () async {
    final f = _Fixture();
    final ctx = f.context(['1', '2', '3', '4']);
    f.played['b/3'] = true;
    f.denied.add('a/4');
    final result = await _recommend(ctx);
    expect((result.data['results'] as List).map((e) => (e as Map)['item_id']), ['1', '2']);
    expect(result.display, isA<AssistantMediaGrid>());
    expect(result.data['can_become_home_row'], isFalse);
    expect(result.data['home_row_unavailable_reason'], isNotEmpty);
    expect(f.calls.any((r) => r.url.path == '/Items'), isFalse);
    expect(f.calls.every((r) => r.method == 'GET'), isTrue);
  });
  test('a title with two copies on the server is proven per title: a watched copy rules it out', () async {
    final f = _Fixture();
    final ctx = f.context(['1', '2']);
    f.loader.copies['1'] = ['1-4k'];
    // Bob watched the 4K copy; the HD copy says Played:false for everyone.
    f.played['b/1-4k'] = true;
    final result = await _recommend(ctx);
    expect((result.data['results'] as List).map((e) => (e as Map)['item_id']), ['2']);
    final coverage = result.data['coverage'] as Map;
    expect((coverage['candidates_checked'], coverage['excluded_watched']), (2, 1));
  });
  test('a title with two copies nobody watched is one result, not two', () async {
    final f = _Fixture();
    final ctx = f.context(['1', '2']);
    f.loader.copies['1'] = ['1-4k'];
    final result = await _recommend(ctx);
    expect((result.data['results'] as List).map((e) => (e as Map)['item_id']), ['1', '2']);
    expect((result.display! as AssistantMediaGrid).entries.map((e) => e.item.id), ['1', '2']);
    final coverage = result.data['coverage'] as Map;
    expect((coverage['candidates_checked'], coverage['copies_read']), (2, 3));
  });
  test('missing or malformed Played is unknown, not absence from capped history', () async {
    final f = _Fixture();
    final ctx = f.context(['1', '2', '3']);
    f.played['b/1'] = null;
    f.played['b/2'] = 'false';
    final result = await _recommend(ctx);
    expect((result.data['results'] as List).map((e) => (e as Map)['item_id']), ['3']);
    expect((result.data['coverage'] as Map)['excluded_unknown'], 2);
    expect(f.calls.any((r) => r.url.queryParameters['Filters'] == 'IsPlayed'), isFalse);
  });
  test('played false with previous play or active progress is not genuinely unseen', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    f.dtos['1'] = {
      ..._dto('1'),
      'UserData': {'Played': false, 'PlaybackPositionTicks': 500},
    };
    expect((await _recommend(ctx)).data['results'], isEmpty);
  });
  test('granted library cannot bypass exact item parental or tag restriction', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    f.denied.add('b/1');
    final result = await _recommend(ctx);
    expect(result.data['results'], isEmpty);
    expect((result.data['coverage'] as Map)['excluded_no_access'], 1);
    expect(f.calls.any((r) => r.url.path == '/Items/1' && r.url.queryParameters['userId'] == 'b'), isTrue);
  });
  test('no library grant excludes before reading participant items', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    f.policies['b'] = _policy(all: false);
    expect((await _recommend(ctx)).data['results'], isEmpty);
    expect(f.calls.where((r) => r.url.queryParameters['userId'] == 'b'), isEmpty);
  });
  test('disabled or malformed participant policy fails closed', () async {
    for (final policy in [
      _policy(disabled: true),
      <String, Object?>{},
      {
        ..._policy(),
        'EnabledFolders': ['films', 2],
      },
    ]) {
      final f = _Fixture();
      final ctx = f.context(['1']);
      f.policies['b'] = policy;
      expect((await _recommend(ctx)).data['results'], isEmpty);
      expect(f.calls.where((r) => r.url.queryParameters['userId'] == 'b'), isEmpty);
    }
  });
  test('nonadmin and Emby capability explicitly unsupported with no admin read', () async {
    for (final emby in [false, true]) {
      final f = _Fixture();
      final ctx = f.context(['1'], localAdmin: emby, emby: emby);
      expect((await _recommend(ctx)).data['status'], 'unsupported_strict_cohort');
      expect(f.calls, isEmpty);
    }
  });
  test('stale cached admin does not escalate live member credential', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    f.admin = false;
    await expectLater(_recommend(ctx), throwsA(anything));
    expect(f.calls.map((r) => r.url.path), ['/Users/Me']);
  });
  test('server error is unavailable evidence, never an empty successful cohort', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    f.beforeReply = (r) async {
      if (r.url.path == '/Users/b') throw StateError('offline');
    };
    await expectLater(_recommend(ctx), throwsA(anything));
  });
  test('profile change during exact read prevents shown item authority', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    f.beforeReply = (r) async {
      if (r.url.path == '/Items/1') f.profile = 'other';
    };
    await expectLater(
      _recommend(ctx),
      throwsA(isA<AssistantToolError>().having((e) => e.code, 'code', 'profile_changed')),
    );
    expect(() => ctx.requireShownItem(ServerId('jf'), '1'), throwsA(isA<AssistantToolError>()));
    expect(f.calls.any((r) => r.url.path == '/Users/b'), isFalse);
  });
  test('cancel during exact read stops further participant reads and publication', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    f.beforeReply = (r) async {
      if (r.url.path == '/Items/1') f.cancel.abort();
    };
    await expectLater(_recommend(ctx), throwsA(anything));
    expect(() => ctx.requireShownItem(ServerId('jf'), '1'), throwsA(isA<AssistantToolError>()));
    expect(f.calls.any((r) => r.url.path == '/Users/b'), isFalse);
  });
  test('disconnect during awaited item discards late response', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    f.beforeReply = (r) async {
      if (r.url.path == '/Items/1') f.manager.setVisibleServerIds({});
    };
    await expectLater(_recommend(ctx), throwsA(isA<AssistantToolError>().having((e) => e.code, 'code', 'not_allowed')));
    expect(() => ctx.requireShownItem(ServerId('jf'), '1'), throwsA(isA<AssistantToolError>()));
  });
  test('live privilege revocation after pending read prevents all cohort disclosure', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    f.beforeReply = (r) async {
      if (r.url.path == '/Items/1') f.admin = false;
    };
    await expectLater(_recommend(ctx), throwsA(anything));
    expect(() => ctx.requireShownItem(ServerId('jf'), '1'), throwsA(isA<AssistantToolError>()));
  });
  test('strict combined filters and deterministic reasons come from exact metadata', () async {
    final f = _Fixture();
    final ctx = f.context(['2', '1', '3']);
    f.dtos['3'] = {
      ..._dto('3'),
      'Genres': ['Comedy', 'Horror'],
    };
    final result = await _recommend(ctx, {
      'genres': ['Comedy'],
      'exclude_genres': ['Horror'],
      'min_runtime_minutes': 85,
      'max_runtime_minutes': 95,
      'year_from': 2000,
      'year_to': 2002,
      'audio_languages': ['en'],
      'subtitle_languages': ['nl'],
      'official_ratings': ['PG'],
      'min_rating': 7,
    });
    final results = result.data['results'] as List;
    expect(results.map((e) => (e as Map)['item_id']), ['1', '2']);
    expect((results.first as Map)['reasons'], {
      'access_proved_for': ['admin', 'a', 'b'],
      'unwatched_proved_for': ['admin', 'a', 'b'],
      'kind': 'movie',
      'genres': ['comedy'],
      'excluded_genres_absent': ['horror'],
      'runtime_minutes': 90.0,
      'year': 2001,
      'audio_languages': ['en'],
      'subtitle_languages': ['nl'],
      'official_rating': 'PG',
      'rating': 8.0,
    });
    expect(f.calls.any((r) => r.url.path == '/Items/3' && r.url.queryParameters['userId'] == 'b'), isFalse);
  });
  test('requested runtime excludes absent and over-limit metadata', () async {
    final f = _Fixture();
    final ctx = f.context(['1', '2', '3']);
    f.dtos['1'] = _dto('1')..remove('RunTimeTicks');
    f.dtos['2'] = {..._dto('2'), 'RunTimeTicks': 120 * 60 * 10000000};
    expect(
      ((await _recommend(ctx, {'max_runtime_minutes': 100})).data['results'] as List).map((e) => (e as Map)['item_id']),
      ['3'],
    );
  });
  test('unknown genres exclude both inclusion and exclusion queries', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    f.dtos['1'] = _dto('1')..remove('Genres');
    expect(
      (await _recommend(ctx, {
        'genres': ['Comedy'],
      })).data['results'],
      isEmpty,
    );
    expect(
      (await _recommend(ctx, {
        'exclude_genres': ['Horror'],
      })).data['results'],
      isEmpty,
    );
  });
  test('unknown audio/subtitle, year and rating do not satisfy requested filters', () async {
    for (final args in [
      {
        'audio_languages': ['en'],
      },
      {
        'subtitle_languages': ['nl'],
      },
      {
        'official_ratings': ['PG'],
      },
      {'year_from': 2000},
      {'min_rating': 5},
    ]) {
      final f = _Fixture();
      final ctx = f.context(['1']);
      f.dtos['1'] = {
        'Id': '1',
        'Type': 'Movie',
        'UserData': {'Played': false},
      };
      expect((await _recommend(ctx, args)).data['results'], isEmpty);
    }
  });
  test('kind, contradictory ranges and malformed lists are rejected', () async {
    for (final args in [
      {'kind': 'episode'},
      {'max_runtime_minutes': 80, 'min_runtime_minutes': 90},
      {'year_from': 2020, 'year_to': 2000},
      {
        'genres': ['Comedy', 1],
      },
      {
        'audio_languages': [''],
      },
      {'min_rating': double.nan},
    ]) {
      expect(() => AssistantStrictFilters.parse(args), throwsA(isA<AssistantToolError>()));
    }
  });
  test('bounded sample honestly reports incomplete catalog coverage', () async {
    final f = _Fixture();
    final ctx = f.context([for (var i = 0; i < 45; i++) '$i']);
    f.loader.exact = false;
    final result = await _recommend(ctx);
    expect((result.data['coverage'] as Map)['sampled'], isTrue);
    expect((result.data['coverage'] as Map)['candidates_checked'], 40);
    expect(result.data['results'] as List, hasLength(10));
  });
  test('Pleya profile label differs from server name and shared identities collapse', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    f.aliases = [
      const ProfileServerIdentity(profileId: 'nikki', displayName: 'Nikki', userIds: {'b'}),
      const ProfileServerIdentity(profileId: 'guest', displayName: 'Guest', userIds: {'b'}),
    ];
    final result = await _recommend(ctx, {
      'participants': ['Nikki', 'Guest', 'me'],
    });
    expect((result.data['participants'] as List).map((e) => (e as Map)['user_id']), ['admin', 'b']);
    expect(result.data['profile_aliases'], {'Nikki': 'b', 'Guest': 'b'});
    expect(f.calls.where((r) => r.url.path == '/Items/1' && r.url.queryParameters['userId'] == 'b'), hasLength(1));
  });
  test('unbound local profile label does not fall back to same-named server user', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    f.aliases = [const ProfileServerIdentity(profileId: 'local', displayName: 'Bob', userIds: {})];
    final result = await _recommend(ctx, {
      'participants': ['Bob'],
    });
    expect(result.data['status'], 'participant_clarification');
    expect(result.data['not_found'], ['Bob']);
    expect(f.calls.where((r) => r.url.path.startsWith('/Items/')), isEmpty);
  });
  test('ambiguous local or server names request clarification rather than guess', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    f.aliases = [
      const ProfileServerIdentity(profileId: 'one', displayName: 'Nikki', userIds: {'a'}),
      const ProfileServerIdentity(profileId: 'two', displayName: 'Nikki', userIds: {'b'}),
    ];
    final result = await _recommend(ctx, {
      'participants': ['Nikki'],
    });
    expect(result.data['status'], 'participant_clarification');
    expect(((result.data['ambiguous'] as List).single as Map)['choices'], hasLength(2));
    expect(f.calls.where((r) => r.url.path.startsWith('/Items/')), isEmpty);
  });
  test('forged user ID never becomes read authority and clarification verifies fresh users', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    await expectLater(
      _recommend(ctx, {
        'participants': [],
        'user_ids': ['forged'],
      }),
      throwsA(isA<AssistantToolError>().having((e) => e.code, 'code', 'unknown_user_id')),
    );
    f.users.removeWhere((u) => u['Id'] == 'b');
    await expectLater(
      _recommend(ctx, {
        'participants': [],
        'user_ids': ['b'],
      }),
      throwsA(isA<AssistantToolError>()),
    );
    expect(f.calls.where((r) => r.url.path.startsWith('/Items/')), isEmpty);
  });
  test('review: a choice offered in this run is the users, the model cannot pick it itself', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    f.aliases = [
      const ProfileServerIdentity(profileId: 'one', displayName: 'Nikki', userIds: {'a'}),
      const ProfileServerIdentity(profileId: 'two', displayName: 'Nikki', userIds: {'b'}),
    ];
    await _recommend(ctx, {
      'participants': ['Nikki'],
    });
    // By id, and by the server name the choice list just handed over.
    for (final pick in [
      {
        'participants': <String>[],
        'user_ids': ['b'],
      },
      {
        'participants': ['Bob'],
      },
    ]) {
      final again = await _recommend(ctx, pick);
      expect(again.data['status'], 'participant_clarification');
      expect(again.data['ask_the_user_which'], ['Bob']);
    }
    expect(f.calls.where((r) => r.url.path.startsWith('/Items/')), isEmpty);
    // The next run carries the user's answer.
    final answered = await _recommend(ctx.fresh(), {
      'participants': [],
      'user_ids': ['b'],
    });
    expect((answered.data['participants'] as List).map((e) => (e as Map)['user_id']), ['admin', 'b']);
  });
  test('review: one GUID written with dashes or capitals is still the same administrator', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    f.meId = 'AD-MIN';
    expect((await _recommend(ctx)).data['status'], 'strict_cohort_results');
  });
  test('review: candidates are this servers titles the requester has not watched', () async {
    final f = _Fixture();
    await _recommend(f.context(['1']));
    final filters = f.loader.rows.single.preferences.filters;
    expect(filters.watchState, UnifiedWatchFilter.unwatched);
    expect(filters.serverIds, {'jf'});
  });
  test('current requester is included even when model only names companion', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    f.played['admin/1'] = true;
    expect(
      (await _recommend(ctx, {
        'participants': ['Bob'],
      })).data['results'],
      isEmpty,
    );
    expect(f.calls.where((r) => r.url.queryParameters['userId'] == 'b'), isEmpty);
  });
  test('exact item reads have three-operation ceiling', () async {
    final f = _Fixture();
    final ctx = f.context(['1', '2', '3', '4']);
    var active = 0;
    var maxActive = 0;
    f.beforeReply = (r) async {
      if (!r.url.path.startsWith('/Items/')) return;
      active++;
      if (active > maxActive) maxActive = active;
      await Future<void>.delayed(Duration.zero);
      active--;
    };
    await _recommend(ctx);
    expect(maxActive, 3);
  });
  test('hidden libraries never generate participant evidence or result authority', () async {
    final f = _Fixture();
    final original = f.context(['1']);
    final libraries = [
      const MediaLibrary(
        id: 'films',
        backend: MediaBackend.jellyfin,
        title: 'Films',
        kind: MediaKind.movie,
        serverId: 'jf',
      ),
    ];
    final hidden = <String>{'jf:films'};
    // Use the production catalog visibility boundary, rather than a fake
    // loader that already promises filtered groups.
    final loader = CatalogHomeCustomRowLoader(
      libraries: () => libraries,
      isServerVisible: f.manager.isServerVisible,
      hiddenLibraryKeys: () => hidden,
      clientFor: f.manager.getClient,
    );
    final ctx = AssistantToolContext(
      servers: f.manager,
      cancel: f.cancel,
      catalog: AssistantCatalogServices(rowLoader: loader, profileId: 'p', activeProfileId: () => f.profile),
    );
    expect((await _recommend(ctx)).data['results'], isEmpty);
    expect(f.calls.where((r) => r.url.path.startsWith('/Items')), isEmpty);
    expect(() => original.requireShownItem(ServerId('jf'), '1'), throwsA(isA<AssistantToolError>()));
  });
  test('recommendation capability integrates into isolated multi-command task results', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    final models = [
      _Model([
        _reply('split_tasks', {
          'tasks': [
            {'title': 'Together', 'intent': 'recommend', 'prompt': 'Recommend for Bob and me'},
            {'title': 'Servers', 'intent': 'list', 'prompt': 'List servers'},
          ],
        }),
      ]),
      _Model([
        _reply('recommend_together', {
          'server_id': 'jf',
          'participants': ['Bob'],
          'kind': 'movie',
        }),
        _reply(),
      ]),
      _Model([_reply('list_servers'), _reply()]),
    ];
    final c = AssistantController(
      buildContext: (_) => ctx,
      rolloutEnabled: true,
      entitlement: _Entitlement(),
      loadConfig: () async => _config,
      modelFor: (_) => models.removeAt(0),
    );
    addTearDown(c.dispose);
    await c.submit('Recommend for Bob and me and list servers');
    expect(c.tasks, hasLength(2));
    expect(c.tasks.map((t) => t.status), everyElement(AssistantTaskStatus.completed));
    expect(c.tasks[0].displays.single, isA<AssistantMediaGrid>());
    expect(c.tasks[1].displays, isEmpty);
    expect(c.tasks[0].actions, isEmpty);
  });
  for (final change in [
    'hide library',
    'remove library',
    'replace client',
    'revoke admin',
    'switch profile',
    'unchanged',
  ]) {
    for (final path in ['controller await', 'direct run await', 'publication callbacks']) {
      test('cohort publication lease: $change at $path', () async {
        final f = _Fixture();
        f.context(['1']);
        final hidden = <String>{};
        var libraries = [
          const MediaLibrary(
            id: 'films',
            backend: MediaBackend.jellyfin,
            title: 'Films',
            kind: MediaKind.movie,
            serverId: 'jf',
          ),
        ];
        final ctx = AssistantToolContext(
          servers: f.manager,
          catalog: AssistantCatalogServices(
            rowLoader: CatalogHomeCustomRowLoader(
              libraries: () => libraries,
              isServerVisible: f.manager.isServerVisible,
              hiddenLibraryKeys: () => hidden,
              clientFor: f.manager.getClient,
            ),
            profileId: 'p',
            activeProfileId: () => f.profile,
          ),
        );
        void revoke() {
          switch (change) {
            case 'hide library':
              hidden.add('jf:films');
            case 'remove library':
              libraries = [];
            case 'replace client':
              final other = _Fixture();
              other.context(['1']);
              f.manager.debugRegisterJellyfinClientForTesting(other.client);
            case 'revoke admin':
              f.manager.setServerAuthorityRestrictions(serverIds: {'jf'});
            case 'switch profile':
              f.profile = 'other';
            case 'unchanged':
              break;
          }
        }

        final cohort =
            _Model([
                _reply('recommend_together', {
                  'server_id': 'jf',
                  'participants': ['Bob'],
                  'kind': 'movie',
                }),
                const AssistantReply(
                  content: 'These suit everyone',
                  toolCalls: [],
                  message: {'role': 'assistant', 'content': 'These suit everyone'},
                ),
              ])
              ..closingEntered = Completer<void>()
              ..closingRelease = Completer<void>();
        if (path == 'controller await') {
          final models = [
            _Model([
              _reply('split_tasks', {
                'tasks': [
                  {'title': 'Together', 'intent': 'recommend', 'prompt': 'Recommend for Bob and me'},
                  {'title': 'Servers', 'intent': 'list', 'prompt': 'List servers'},
                ],
              }),
            ]),
            cohort,
            _Model([_reply('list_servers'), _reply()]),
          ];
          final c = AssistantController(
            buildContext: (_) => ctx,
            rolloutEnabled: true,
            entitlement: _Entitlement(),
            loadConfig: () async => _config,
            modelFor: (_) => models.removeAt(0),
          );
          addTearDown(c.dispose);
          final done = c.submit('Recommend for Bob and me and list servers');
          await cohort.closingEntered!.future;
          expect(
            c.tasks.first.displays.single,
            isA<AssistantMediaGrid>(),
            reason: 'actual cohort grid streamed before revocation',
          );
          revoke();
          cohort.closingRelease!.complete();
          await done;
          expect(c.tasks.last.status, AssistantTaskStatus.completed);
          expect(c.tasks.last.answer, 'Done');
          if (change == 'unchanged') {
            expect(c.tasks.first.displays, hasLength(1));
            expect(c.tasks.first.answer, 'These suit everyone');
          } else {
            expect(c.tasks.first.displays, isEmpty);
            expect(c.tasks.first.steps, isEmpty);
            expect(c.tasks.first.answer, isEmpty);
            expect(c.tasks.first.status, AssistantTaskStatus.failed);
          }
        } else {
          final steps = <AssistantStep>[];
          addTearDown(cohort.close);
          final done = AssistantRun(
            model: cohort,
            context: ctx,
            confirm: (_) async => null,
            entitlement: _Entitlement(),
            refreshHealth: () async {},
            onStep: steps.add,
          ).ask('Recommend for Bob and me');
          await cohort.closingEntered!.future;
          final streamed = steps.singleWhere((step) => step.display is AssistantMediaGrid);
          if (path == 'direct run await') revoke();
          cohort.closingRelease!.complete();
          final result = await done;
          if (path == 'publication callbacks') {
            expect(result.displays, hasLength(1));
            expect(streamed.evidenceCurrent, isNotNull);
            expect(result.displayEvidenceCurrent, isNotNull);
            expect(streamed.evidenceCurrent!(), isTrue);
            expect(result.displayEvidenceCurrent!(), isTrue);
            revoke();
            expect(streamed.evidenceCurrent!(), change == 'unchanged');
            expect(result.displayEvidenceCurrent!(), change == 'unchanged');
          } else if (change == 'unchanged') {
            expect(result.displays, hasLength(1));
            expect(result.text, 'These suit everyone');
          } else {
            expect(result.displays, isEmpty);
            expect(result.text, isEmpty);
            expect(result.error, isNotNull);
          }
        }
      });
    }
  }

  for (final change in ['hide library', 'revoke admin', 'playback only', 'unchanged']) {
    for (final direct in [false, true]) {
      test('cohort and playback composition: $change ${direct ? 'direct' : 'controller'}', () async {
        final f = _Fixture();
        f.context(['1']);
        final hidden = <String>{};
        var playbackCurrent = true;
        var samples = 0;
        final snapshot = AssistantPlaybackSnapshot(sessionId: 'playback', revision: '1');
        final ctx = AssistantToolContext(
          servers: f.manager,
          catalog: AssistantCatalogServices(
            rowLoader: CatalogHomeCustomRowLoader(
              libraries: () => [
                const MediaLibrary(
                  id: 'films',
                  backend: MediaBackend.jellyfin,
                  title: 'Films',
                  kind: MediaKind.movie,
                  serverId: 'jf',
                ),
              ],
              isServerVisible: f.manager.isServerVisible,
              hiddenLibraryKeys: () => hidden,
              clientFor: f.manager.getClient,
            ),
            profileId: 'p',
            activeProfileId: () => f.profile,
          ),
          playback: AssistantPlaybackServices(
            available: () => playbackCurrent,
            sample: () async {
              samples++;
              return snapshot;
            },
            isCurrent: (_) => playbackCurrent,
          ),
        );
        final cohort =
            _Model([
                _reply('recommend_together', {
                  'server_id': 'jf',
                  'participants': ['Bob'],
                  'kind': 'movie',
                }),
                _reply('diagnose_playback'),
                const AssistantReply(
                  content: 'These suit everyone',
                  toolCalls: [],
                  message: {'role': 'assistant', 'content': 'These suit everyone'},
                ),
              ])
              ..closingEntered = Completer<void>()
              ..closingRelease = Completer<void>();
        void revoke() {
          if (change == 'hide library') hidden.add('jf:films');
          if (change == 'revoke admin') f.manager.setServerAuthorityRestrictions(serverIds: {'jf'});
          if (change != 'unchanged') playbackCurrent = false;
        }

        final revokedCohort = change == 'hide library' || change == 'revoke admin';
        if (direct) {
          addTearDown(cohort.close);
          final steps = <AssistantStep>[];
          final done = AssistantRun(
            model: cohort,
            context: ctx,
            confirm: (_) async => null,
            entitlement: _Entitlement(),
            refreshHealth: () async {},
            onStep: steps.add,
          ).ask('Recommend for Bob and me and diagnose current playback');
          await cohort.closingEntered!.future;
          expect(samples, 1);
          expect(steps.any((step) => step.display is AssistantMediaGrid), isTrue);
          expect(
            steps.any((step) => step.tool == 'diagnose_playback' && step.phase == AssistantStepPhase.done),
            isTrue,
          );
          revoke();
          cohort.closingRelease!.complete();
          final result = await done;
          expect(result.displayEvidenceCurrent, isNotNull);
          expect(result.displayEvidenceCurrent!(), !revokedCohort);
          if (change == 'unchanged') {
            expect(result.displays, hasLength(1));
            expect(result.text, 'These suit everyone');
          } else {
            expect(result.error, 'playback_session_changed');
            expect(result.playbackEvidenceCurrent!(), isFalse);
            expect(result.displays, isEmpty);
            expect(result.text, isEmpty);
          }
        } else {
          final models = [
            _Model([
              _reply('split_tasks', {
                'tasks': [
                  {
                    'title': 'Together',
                    'intent': 'recommend',
                    'prompt': 'Recommend for Bob and me and diagnose current playback',
                  },
                  {'title': 'Servers', 'intent': 'list', 'prompt': 'List servers'},
                ],
              }),
            ]),
            cohort,
            _Model([_reply('list_servers'), _reply()]),
          ];
          final c = AssistantController(
            buildContext: (_) => ctx,
            rolloutEnabled: true,
            entitlement: _Entitlement(),
            loadConfig: () async => _config,
            modelFor: (_) => models.removeAt(0),
          );
          addTearDown(c.dispose);
          final done = c.submit('Recommend together, diagnose playback and list servers');
          await cohort.closingEntered!.future;
          expect(samples, 1);
          expect(c.tasks.first.displays.single, isA<AssistantMediaGrid>());
          expect(
            c.tasks.first.steps.any(
              (step) => step.tool == 'diagnose_playback' && step.phase == AssistantStepPhase.done,
            ),
            isTrue,
          );
          revoke();
          cohort.closingRelease!.complete();
          await done;
          expect(c.tasks.last.status, AssistantTaskStatus.completed);
          expect(c.tasks.last.answer, 'Done');
          if (revokedCohort) {
            expect(c.tasks.first.displays, isEmpty);
            expect(c.tasks.first.steps, isEmpty);
            expect(c.tasks.first.answer, isEmpty);
            expect(c.tasks.first.status, AssistantTaskStatus.failed);
          } else {
            expect(c.tasks.first.displays, hasLength(1), reason: 'still-authorized cohort evidence is retained');
            expect(c.tasks.first.answer, change == 'unchanged' ? 'These suit everyone' : '');
          }
        }
      });
    }
  }

  test('same-title groups never transfer another servers access or watch evidence', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    f.dtos['1'] = {
      ..._dto('different-id'),
      'UserData': {'Played': false},
    };
    final result = await _recommend(ctx);
    expect(result.data['results'], isEmpty);
    expect((result.data['coverage'] as Map)['excluded_unknown'], 1);
  });
  test('ambiguous backend names also require conversational selection', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    f.users.add({'Id': 'c', 'Name': 'Bob', 'Policy': _policy()});
    final result = await _recommend(ctx, {
      'participants': ['Bob'],
    });
    expect(result.data['status'], 'participant_clarification');
    expect(((result.data['ambiguous'] as List).single as Map)['choices'], hasLength(2));
  });
  test('rating ordering is deterministic before identity tiebreak', () async {
    final f = _Fixture();
    final ctx = f.context(['1', '3', '2']);
    f.dtos['3'] = {..._dto('3'), 'CommunityRating': 9.0};
    expect(((await _recommend(ctx)).data['results'] as List).map((e) => (e as Map)['item_id']), ['3', '1', '2']);
  });
  test('library hidden while exact read pending invalidates the read', () async {
    final f = _Fixture();
    f.context(['1']);
    final hidden = <String>{};
    final loader = CatalogHomeCustomRowLoader(
      libraries: () => [
        const MediaLibrary(
          id: 'films',
          backend: MediaBackend.jellyfin,
          title: 'Films',
          kind: MediaKind.movie,
          serverId: 'jf',
        ),
      ],
      isServerVisible: f.manager.isServerVisible,
      hiddenLibraryKeys: () => hidden,
      clientFor: f.manager.getClient,
    );
    final ctx = AssistantToolContext(
      servers: f.manager,
      cancel: f.cancel,
      catalog: AssistantCatalogServices(rowLoader: loader, profileId: 'p', activeProfileId: () => f.profile),
    );
    f.beforeReply = (r) async {
      if (r.url.path == '/Items/1') hidden.add('jf:films');
    };
    await expectLater(
      _recommend(ctx),
      throwsA(isA<AssistantToolError>().having((e) => e.code, 'code', 'catalog_changed')),
    );
    expect(() => ctx.requireShownItem(ServerId('jf'), '1'), throwsA(isA<AssistantToolError>()));
  });
  test('malformed progress or play count never proves genuinely unseen state', () async {
    for (final data in [
      {'Played': false, 'PlaybackPositionTicks': '500'},
      {'Played': false, 'PlayCount': -1},
    ]) {
      final f = _Fixture();
      final ctx = f.context(['1']);
      f.dtos['1'] = {..._dto('1'), 'UserData': data};
      final result = await _recommend(ctx);
      expect(result.data['results'], isEmpty);
      expect((result.data['coverage'] as Map)['excluded_unknown'], 1);
    }
  });
  test('exact metadata with changed or unknown kind never matches catalog candidate', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    f.dtos['1'] = {..._dto('1'), 'Type': 'Book'};
    expect((await _recommend(ctx, {'kind': null})).data['results'], isEmpty);
  });
  test('conflicting explicit top library is never relabelled as visible scope', () async {
    final f = _Fixture();
    f.context(['1']);
    f.dtos['1'] = {..._dto('1'), 'ParentLibraryId': 'hidden'};
    final loader = CatalogHomeCustomRowLoader(
      libraries: () => [
        const MediaLibrary(
          id: 'films',
          backend: MediaBackend.jellyfin,
          title: 'Films',
          kind: MediaKind.movie,
          serverId: 'jf',
        ),
        const MediaLibrary(
          id: 'hidden',
          backend: MediaBackend.jellyfin,
          title: 'Hidden',
          kind: MediaKind.movie,
          serverId: 'jf',
        ),
      ],
      isServerVisible: f.manager.isServerVisible,
      hiddenLibraryKeys: () => {'jf:hidden'},
      clientFor: f.manager.getClient,
    );
    final ctx = AssistantToolContext(
      servers: f.manager,
      catalog: AssistantCatalogServices(rowLoader: loader, profileId: 'p', activeProfileId: () => f.profile),
    );
    expect((await _recommend(ctx)).data['results'], isEmpty);
    expect(f.calls.where((r) => r.url.path.startsWith('/Items/')), isEmpty);
  });
  test('fix I1 partially watched series aggregate excludes despite zero parent plays', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    f.loader.kind = MediaKind.show;
    f.dtos['1'] = {
      ..._dto('1'),
      'Type': 'Series',
      'RecursiveItemCount': 2,
      'UserData': {
        'Played': false,
        'PlayCount': 0,
        'PlaybackPositionTicks': 0,
        'PlayedPercentage': 50,
        'UnplayedItemCount': 1,
      },
    };
    final result = await _recommend(ctx, {'kind': 'show'});
    expect(result.data['results'], isEmpty);
    expect((result.data['coverage'] as Map)['excluded_watched'], 1);
    expect(f.calls.where((r) => r.url.queryParameters['userId'] == 'b'), isEmpty);
  });
  test('fix I1 missing malformed or zero series aggregate cannot prove no child progress', () async {
    // Folder.FillUserDataDtoValues counts completed children only: a zero
    // percentage with all children unplayed still allows a started episode.
    for (final data in [
      <String, Object?>{},
      {'PlayedPercentage': '0', 'UnplayedItemCount': 2},
      {'PlayedPercentage': -1, 'UnplayedItemCount': 2},
      {'PlayedPercentage': 0, 'UnplayedItemCount': 2},
    ]) {
      final f = _Fixture();
      final ctx = f.context(['1']);
      f.loader.kind = MediaKind.show;
      f.dtos['1'] = {
        ..._dto('1'),
        'Type': 'Series',
        'RecursiveItemCount': 2,
        'UserData': {'Played': false, 'PlayCount': 0, 'PlaybackPositionTicks': 0, ...data},
      };
      final result = await _recommend(ctx, {'kind': 'show'});
      expect(result.data['results'], isEmpty);
      expect((result.data['coverage'] as Map)['excluded_unknown'], 1);
      expect((result.data['coverage'] as Map)['series_unseen_supported'], isFalse);
      expect(result.data['series_unsupported'], isTrue, reason: 'an empty series list is the tool\'s limit, said so');
    }
  });
  test('a film question carries no series_unsupported', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    final result = await _recommend(ctx, {'kind': 'movie'});
    expect(result.data.containsKey('series_unsupported'), isFalse);
  });
  test('fix I2 exact-only hidden top library blocks companion reads and shown authority', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    f.exactDtos['admin/1'] = {..._dto('1'), 'ParentLibraryId': 'hidden'};
    final result = await _recommend(ctx);
    expect(result.data['results'], isEmpty);
    expect(f.calls.where((r) => r.url.queryParameters['userId'] == 'b'), isEmpty);
    expect(() => ctx.requireShownItem(ServerId('jf'), '1'), throwsA(isA<AssistantToolError>()));
  });
  test('fix I2 companion exact top-library conflict cannot inherit requester scope', () async {
    final f = _Fixture();
    final ctx = f.context(['1']);
    f.exactDtos['b/1'] = {..._dto('1'), 'ParentLibraryId': 'hidden'};
    final result = await _recommend(ctx);
    expect(result.data['results'], isEmpty);
    expect(() => ctx.requireShownItem(ServerId('jf'), '1'), throwsA(isA<AssistantToolError>()));
  });
  test('fix I2 exact top scope is retained while absent top may inherit proved catalog scope', () async {
    for (final top in ['films', null]) {
      final f = _Fixture();
      final ctx = f.context(['1']);
      f.exactDtos['admin/1'] = {..._dto('1'), if (top != null) 'ParentLibraryId': top, 'ParentId': 'nested-folder'};
      final result = await _recommend(ctx);
      expect(result.data['results'] as List, hasLength(1));
      expect((result.display as AssistantMediaGrid).entries.single.item.libraryId, 'films');
    }
  });
  test('fix I2 malformed explicit exact top scope is unknown rather than inherited', () async {
    for (final top in ['', 3]) {
      final f = _Fixture();
      final ctx = f.context(['1']);
      f.exactDtos['admin/1'] = {..._dto('1'), 'ParentLibraryId': top};
      final result = await _recommend(ctx);
      expect(result.data['results'], isEmpty);
      expect((result.data['coverage'] as Map)['excluded_unknown'], 1);
      expect(f.calls.where((r) => r.url.queryParameters['userId'] == 'b'), isEmpty);
    }
  });
}
