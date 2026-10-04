import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/assistant/assistant_entitlement.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/server_administration.dart';
import 'package:pleya/services/jellyfin_mappers.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/unified_catalog/home_custom_row_loader.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/media_server_http_client.dart' show AbortController;

import 'assistant_find_fakes.dart' as find;

const _config = AssistantProviderConfig(
  kind: AssistantProviderKind.ollamaServer,
  baseUrl: 'http://model.test',
  model: 'm',
);
final _id = ServerId('s');

class _Entitlement extends AssistantEntitlement {
  @override
  Future<AssistantEntitlementState> check() async => AssistantEntitlementState.entitled;
}

class _Manager extends MultiServerManager {
  bool admin = true;
  @override
  bool canAdministerServer(ServerId serverId) => admin && serverId == _id;
  @override
  Future<void> checkServerHealth() async {}
}

class _Server extends find.FakeServer implements LibraryScanClient, ItemMetadataRefreshClient {
  _Server() : super('s');
  final items = <String, MediaItem>{};
  final pages = <String, List<MediaItem>>{};
  final totals = <String, int>{};
  final writes = <String>[];
  final reads = <String>[];
  Completer<void>? stall;
  Completer<void>? pageStall;
  bool repeat = false;
  @override
  bool get supportsServerAdministration => true;
  @override
  Future<List<MediaLibrary>> fetchLibraries() async => [
    find.fakeLib('s', 'films'),
    find.fakeLib('s', 'series', kind: MediaKind.show),
  ];
  @override
  Future<MediaItem?> fetchItem(String id) async {
    reads.add('item:$id');
    if (stall != null) await stall!.future;
    return items[id];
  }

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
    bool requireTotalCount = false,
  }) async {
    reads.add('library:$libraryId');
    if (pageStall != null) await pageStall!.future;
    final rows = pages[libraryId] ?? [];
    final start = repeat ? 0 : query.offset.clamp(0, rows.length);
    return LibraryPage(
      items: rows.skip(start).take(query.limit).toList(),
      offset: query.offset,
      totalCount: totals[libraryId] ?? rows.length,
    );
  }

  @override
  Future<LibraryPage<MediaItem>> fetchChildrenPage(
    String parentId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    reads.add('children:$parentId');
    final rows = pages[parentId] ?? [];
    return LibraryPage(
      items: rows.skip(start ?? 0).take(size ?? 50).toList(),
      offset: start ?? 0,
      totalCount: totals[parentId] ?? rows.length,
    );
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds(tmdb: 10);
  @override
  Future<void> scanLibrary(String libraryId) async => writes.add('scan:$libraryId');
  @override
  Future<void> refreshItemMetadata(String itemId) async => writes.add('refresh:$itemId');
}

// This normalized fixture explicitly stands for the strict adapter contract.
// Raw count/mapping-loss behavior is tested through the real HTTP client below.
class _StrictServer extends _Server implements JellyfinClient {
  @override
  final connection = JellyfinConnection(
    id: 's/user',
    baseUrl: 'https://doctor-jellyfin.test',
    serverName: 'Doctor test',
    serverMachineId: 's',
    userId: 'user',
    userName: 'Test',
    accessToken: 'test-token',
    deviceId: 'test-device',
    isAdministrator: true,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
  @override
  bool get canChangeLibraryAccess => false;
  @override
  Future<void> closeGracefully({Duration drainTimeout = const Duration(seconds: 2)}) async => close();
  @override
  bool Function()? canManageServerMetadata;
  @override
  bool Function()? canAdministerServer;
  @override
  Future<LibraryPage<MediaItem>> fetchLibraryContent(
    String libraryId,
    LibraryQuery query, {
    AbortController? abort,
    bool requireTotalCount = false,
  }) => fetchLibraryPagedContent(libraryId, query: query, abort: abort, requireTotalCount: requireTotalCount);
}

MediaItem _mapped(
  String id,
  String type, {
  String parent = 'films',
  int? number,
  int? season,
  Object? end,
  String? overview = 'Known summary',
  List<Map<String, Object?>>? sources,
}) => JellyfinMappers.mediaItem(
  {
    'Id': id,
    'Type': type,
    'Name': id,
    'ParentId': parent,
    'ParentLibraryId': type == 'Movie' ? 'films' : 'series',
    'ProductionYear': 2001,
    'Overview': overview,
    'IndexNumber': ?number,
    'ParentIndexNumber': ?season,
    'IndexNumberEnd': ?end,
    if (type == 'Episode') 'SeriesId': 'show',
    'MediaSources': ?sources,
    if (type == 'Episode') 'PremiereDate': '2020-01-${(number ?? 1).toString().padLeft(2, '0')}',
  },
  serverId: _id,
  absolutizer: null,
)!;

class _Fixture {
  final manager = _Manager();
  final server = _StrictServer();
  final hidden = <String>{};
  final libraries = [find.fakeLib('s', 'films'), find.fakeLib('s', 'series', kind: MediaKind.show)];
  String profile = 'p';
  final seerr = find.FakeSeerr();
  late final ctx = AssistantToolContext(
    servers: manager,
    catalog: AssistantCatalogServices(
      rowLoader: CatalogHomeCustomRowLoader(
        libraries: () => libraries,
        isServerVisible: manager.isServerVisible,
        hiddenLibraryKeys: () => hidden,
        clientFor: manager.getClient,
      ),
      profileId: 'p',
      activeProfileId: () => profile,
    ),
    requests: AssistantRequestServices(client: () => seerr.client),
  );
  _Fixture() {
    manager.debugRegisterClientForTesting(server);
    addTearDown(manager.dispose);
    final movie = _mapped('movie', 'Movie', overview: null);
    server.items[movie.id] = movie;
    server.pages['films'] = [movie];
    final show = _mapped('show', 'Series', parent: 'series');
    server.items[show.id] = show;
    server.pages['series'] = [show];
    server.pages['show'] = [_mapped('season', 'Season', parent: 'show', number: 1)];
    server.pages['season'] = [
      _mapped('e1', 'Episode', parent: 'season', number: 1, season: 1),
      _mapped('e3', 'Episode', parent: 'season', number: 3, season: 1),
    ];
    seerr.details['/tv/10'] = {
      'id': 10,
      'seasons': [
        {'seasonNumber': 1, 'episodeCount': 3},
      ],
    };
    seerr.details['/tv/10/season/1'] = {
      'seasonNumber': 1,
      'episodes': [
        for (var n = 1; n <= 3; n++)
          {'seasonNumber': 1, 'episodeNumber': n, 'airDate': '2020-01-${n.toString().padLeft(2, '0')}'},
      ],
    };
  }
  Future<Map<String, Object?>> diagnose({
    Map<String, Object?> args = const {'library_id': 'series', 'server_id': 's'},
  }) async => (await _tool('diagnose_library').run(ctx, null, args) as AssistantToolResult).data;
}

AssistantTool _tool(String name) => assistantTools.firstWhere((t) => t.name == name);
AssistantReply _reply(String? tool, [Map<String, Object?> args = const {}]) => AssistantReply(
  content: 'Closing answer',
  toolCalls: tool == null ? [] : [AssistantToolCall(id: 'call', name: tool, arguments: jsonEncode(args))],
  message: {'role': 'assistant', 'content': ''},
);

class _Model extends AssistantModelClient {
  _Model(this.replies) : super(_config, httpClient: MockClient((_) async => http.Response('', 500)));
  final List<AssistantReply> replies;
  final specs = <List<String>>[];
  Completer<void>? closing;
  Future<AssistantReply> Function(List<Map<String, Object?>> messages)? respond;
  @override
  Future<AssistantReply> chat(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools, {
    AbortController? abort,
  }) async {
    specs.add([for (final t in tools) (t['function'] as Map)['name'] as String]);
    if (specs.length > 1 && closing != null) await closing!.future;
    if (respond != null) return respond!(messages);
    return replies.isEmpty ? _reply(null) : replies.removeAt(0);
  }
}

void main() {
  for (final evidence in ['missing_total', 'discarded_row_without_total', 'discarded_row_with_total', 'complete']) {
    test('actual Jellyfin confirmation requires lossless explicit coverage: $evidence', () async {
      final f = _Fixture();
      var confirmation = false;
      final writes = <String>[];
      final membershipQueries = <Uri>[];
      final raw = Map<String, Object?>.from(f.server.items['movie']!.raw!)..remove('ParentLibraryId');
      final client = JellyfinClient.forTesting(
        connection: JellyfinConnection(
          id: 's/user',
          baseUrl: 'https://doctor-jellyfin.test',
          serverName: 'Doctor test',
          serverMachineId: 's',
          userId: 'user',
          userName: 'Test',
          accessToken: 'test-token',
          deviceId: 'test-device',
          isAdministrator: true,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
        httpClient: MockClient((request) async {
          Object? response;
          if (request.method == 'POST') {
            writes.add(request.url.path);
            return http.Response('', 204);
          }
          if (request.url.path == '/Items') {
            final scoped = request.url.queryParameters['ParentId'] == 'films';
            if (confirmation && scoped) membershipQueries.add(request.url);
            response = {
              'Items': [raw, if (confirmation && scoped && evidence.startsWith('discarded')) 'malformed raw row'],
              if (!confirmation || !scoped || evidence == 'complete' || evidence == 'discarded_row_with_total')
                'TotalRecordCount': 1,
            };
          } else if (request.url.path == '/Users/user/Items/movie') {
            response = raw;
          } else {
            return http.Response('', 404);
          }
          return http.Response(jsonEncode(response), 200, headers: {'content-type': 'application/json'});
        }),
      );
      f.manager.debugRegisterJellyfinClientForTesting(client);
      final data = await f.diagnose(args: {'server_id': 's', 'library_id': 'films'});
      final proposal = Map<String, Object?>.from((data['actions'] as List).single as Map);
      final action = await _tool('refresh_metadata').run(f.ctx, _id, proposal) as AssistantPendingAction;
      expect(writes, isEmpty);
      confirmation = true;
      if (evidence == 'complete') {
        await action.execute();
        expect(writes, ['/Items/movie/Refresh']);
      } else {
        await expectLater(action.execute(), throwsA(anything));
        expect(writes, isEmpty);
      }
      expect(membershipQueries, hasLength(1));
      expect(membershipQueries.single.queryParameters['ParentId'], 'films');
      expect(membershipQueries.single.queryParameters['SearchTerm'], 'movie');
    });
  }
  test('Doctor omits actions when the backend cannot prove fresh membership', () async {
    final f = _Fixture();
    final unsupported = _Server()
      ..items.addAll(f.server.items)
      ..pages.addAll(f.server.pages);
    f.manager.debugRegisterClientForTesting(unsupported);
    final data = await f.diagnose(args: {'server_id': 's', 'library_id': 'films'});
    expect(data['items'], hasLength(1));
    expect(data['actions'], isEmpty);
    expect(f.ctx.libraryDoctorActions, isEmpty);
    expect(unsupported.writes, isEmpty);
  });
  test('Library Doctor is registered as a read capability', () {
    expect(assistantTools.where((t) => t.name == 'diagnose_library'), hasLength(1));
    expect(_tool('diagnose_library').risk, AssistantToolRisk.read);
  });
  test('initial library diagnosis cannot directly execute administration', () async {
    final f = _Fixture();
    final model = _Model([
      _reply('scan_library', {'server_id': 's', 'library_id': 'films'}),
    ]);
    await AssistantRun(
      model: model,
      context: f.ctx,
      confirm: (_) async => throw StateError('No proposal exists'),
      entitlement: _Entitlement(),
      refreshHealth: () async {},
    ).ask('Diagnose my library');
    expect(f.server.writes, isEmpty);
    expect(model.specs.first, isNot(contains('scan_library')));
  });
  for (final prompt in [
    'Mist er iets in seizoen 3?',
    'Waarom staat aflevering 6 er niet tussen?',
    'Heb ik dubbele versies?',
    'Welke films hebben geen Nederlandse ondertiteling?',
    'Klopt deze metadata?',
    'Diagnose missing Dutch subtitles',
    'Welke films missen Nederlandse ondertitels?',
    'Welke films hebben geen Nederlandse ondertitels?',
    'Check duplicate movies',
    'Welke films staan dubbel?',
    'Which titles have incomplete metadata?',
    'Welke titels hebben onvolledige metadata?',
    'Which movies have incorrect metadata?',
    'Which episodes are missing from season 3?',
    'Welke afleveringen ontbreken in seizoen 3?',
  ]) {
    test('initial category diagnosis fences admin-only reply: $prompt', () async {
      final f = _Fixture();
      final model = _Model([
        _reply('scan_library', {'server_id': 's', 'library_id': 'films'}),
      ]);
      await AssistantRun(
        model: model,
        context: f.ctx,
        confirm: (_) async => throw StateError('No proposal exists'),
        entitlement: _Entitlement(),
        refreshHealth: () async {},
      ).ask(prompt);
      expect(f.server.writes, isEmpty, reason: prompt);
      expect(model.specs.first, contains('diagnose_library'), reason: prompt);
      expect(model.specs.first, isNot(contains('scan_library')), reason: prompt);
    });
  }
  test('visible row moved hidden during Jellyfin hydration publishes no item evidence', () async {
    final f = _Fixture();
    f.server.stall = Completer<void>();
    final running = f.diagnose(args: {'server_id': 's', 'library_id': 'films'});
    await pumpEventQueue();
    expect(f.server.reads, ['library:films', 'item:movie']);
    final raw = Map<String, dynamic>.from(f.server.items['movie']!.raw!)
      ..remove('ParentLibraryId')
      ..['ParentId'] = 'hidden-folder'
      ..['Overview'] = 'Hidden private summary'
      ..['MediaSources'] = [
        {'Id': 'hidden-version', 'Name': 'Hidden private edition'},
      ];
    f.server.items['movie'] = JellyfinMappers.mediaItem(raw, serverId: _id, absolutizer: null)!;
    f.server.pages['films'] = [];
    f.server.stall!.complete();
    final data = await running;
    expect(data['items'], isEmpty);
    expect(data['actions'], isEmpty);
    expect(jsonEncode(data), isNot(contains('Hidden private')));
    expect(() => f.ctx.requireShownItem(_id, 'movie'), throwsA(isA<AssistantToolError>()));
    expect(data['partial'], true);
    expect(f.server.writes, isEmpty);
  });
  test('confirmed mapped Jellyfin item moved to hidden root cannot refresh', () async {
    final f = _Fixture();
    final proposal = Map<String, Object?>.from(
      ((await f.diagnose(args: {'server_id': 's', 'library_id': 'films'}))['actions'] as List).single as Map,
    );
    final action = await _tool('refresh_metadata').run(f.ctx, _id, proposal) as AssistantPendingAction;
    final raw = Map<String, dynamic>.from(f.server.items['movie']!.raw!)
      ..remove('ParentLibraryId')
      ..['ParentId'] = 'hidden-folder';
    final moved = JellyfinMappers.mediaItem(raw, serverId: _id, absolutizer: null)!;
    expect(moved.libraryId, 'hidden-folder');
    expect(moved.parentId, 'hidden-folder');
    expect(moved.guid, f.server.items['movie']!.guid);
    expect(moved.title, f.server.items['movie']!.title);
    expect(moved.year, f.server.items['movie']!.year);
    f.server.items['movie'] = moved;
    f.server.pages['films'] = [];
    await expectLater(action.execute(), throwsA(isA<AssistantToolError>()));
    expect(f.server.writes, isEmpty);
  });
  test('confirmed Jellyfin missing explicit root succeeds with current visible membership', () async {
    final f = _Fixture();
    final raw = Map<String, dynamic>.from(f.server.items['movie']!.raw!)..remove('ParentLibraryId');
    f.server.items['movie'] = JellyfinMappers.mediaItem(raw, serverId: _id, absolutizer: null)!;
    f.server.pages['films'] = [f.server.items['movie']!];
    final proposal = Map<String, Object?>.from(
      ((await f.diagnose(args: {'server_id': 's', 'library_id': 'films'}))['actions'] as List).single as Map,
    );
    final action = await _tool('refresh_metadata').run(f.ctx, _id, proposal) as AssistantPendingAction;
    raw['ParentId'] = 'visible-nested-folder';
    final nested = JellyfinMappers.mediaItem(raw, serverId: _id, absolutizer: null)!;
    f.server.items['movie'] = nested;
    f.server.pages['films'] = [nested];
    f.server.reads.clear();
    await action.execute();
    expect(f.server.reads, contains('library:films'));
    expect(f.server.writes, ['refresh:movie']);
  });
  for (final tool in ['scan_library', 'refresh_metadata']) {
    for (final partial in [false, true]) {
      test('confirmed $tool refuses ${partial ? 'partial' : 'missing'} visible membership', () async {
        final f = _Fixture();
        final library = tool == 'scan_library' ? 'series' : 'films';
        final data = await f.diagnose(args: {'server_id': 's', 'library_id': library});
        final proposal = Map<String, Object?>.from(
          (data['actions'] as List).firstWhere((a) => a['tool'] == tool) as Map,
        );
        final action = await _tool(tool).run(f.ctx, _id, proposal) as AssistantPendingAction;
        if (partial) {
          f.server.totals[library] = 2;
        } else {
          f.server.pages[library] = [];
        }
        await expectLater(action.execute(), throwsA(isA<AssistantToolError>()));
        expect(f.server.writes, isEmpty);
      });
    }
  }
  test('confirmation rechecks live authority around the visible membership await', () async {
    for (final tool in ['scan_library', 'refresh_metadata']) {
      for (final change in ['profile', 'hidden', 'client', 'downgrade', 'cancel']) {
        final f = _Fixture();
        final cancel = AbortController();
        final ctx = f.ctx.fresh(cancel: cancel);
        final library = tool == 'scan_library' ? 'series' : 'films';
        final data =
            (await _tool('diagnose_library').run(ctx, null, {'server_id': 's', 'library_id': library})
                    as AssistantToolResult)
                .data;
        final proposal = Map<String, Object?>.from(
          (data['actions'] as List).firstWhere((a) => a['tool'] == tool) as Map,
        );
        final action = await _tool(tool).run(ctx, _id, proposal) as AssistantPendingAction;
        f.server.reads.clear();
        f.server.pageStall = Completer<void>();
        final running = action.execute();
        final rejected = expectLater(running, throwsA(isA<AssistantToolError>()));
        await pumpEventQueue();
        expect(f.server.reads, contains('library:$library'), reason: '$tool $change');
        expect(f.server.writes, isEmpty);
        switch (change) {
          case 'profile':
            f.profile = 'other';
          case 'hidden':
            f.hidden.add('s:$library');
          case 'client':
            f.manager.debugRegisterClientForTesting(_Server());
          case 'downgrade':
            f.manager.admin = false;
          case 'cancel':
            cancel.abort();
        }
        if (change == 'cancel') await rejected.timeout(const Duration(seconds: 1));
        f.server.pageStall!.complete();
        await rejected;
        await pumpEventQueue();
        expect(f.server.writes, isEmpty, reason: '$tool $change');
      }
    }
  });
  test('confirmed scan executes once after fresh visible membership', () async {
    final f = _Fixture();
    final data = await f.diagnose();
    final proposal = Map<String, Object?>.from(
      (data['actions'] as List).firstWhere((a) => a['tool'] == 'scan_library') as Map,
    );
    final action = await _tool('scan_library').run(f.ctx, _id, proposal) as AssistantPendingAction;
    f.server.reads.clear();
    await action.execute();
    expect(f.server.reads, ['item:show', 'library:series']);
    expect(f.server.writes, ['scan:series']);
  });
  test('complete compatible evidence distinguishes gap from proved missing aired episode', () async {
    final f = _Fixture();
    final data = await f.diagnose();
    final season = ((data['items'] as List).single['seasons'] as List).single;
    expect(season['numbering_gaps'], [2]);
    expect(season['missing_aired'], [2]);
    expect(data['partial'], false);
    expect(f.server.writes, isEmpty);
  });
  test('gap alone and unaired expected episode never prove absence', () async {
    final f = _Fixture();
    f.seerr.details['/tv/10/season/1'] = {};
    var data = await f.diagnose();
    var season = ((data['items'] as List).single['seasons'] as List).single;
    expect(season['numbering_gaps'], [2]);
    expect(season['missing_aired'], isEmpty);
    f.seerr.details['/tv/10/season/1'] = {
      'seasonNumber': 1,
      'episodes': [
        for (var n = 1; n <= 3; n++)
          {
            'seasonNumber': 1,
            'episodeNumber': n,
            'airDate': n == 2 ? '2099-01-01' : '2020-01-${n.toString().padLeft(2, '0')}',
          },
      ],
    };
    data = await f.diagnose();
    season = ((data['items'] as List).single['seasons'] as List).single;
    expect(season['missing_aired'], isEmpty);
  });
  test('raw compound numbering covers every contained episode', () async {
    final f = _Fixture();
    f.server.pages['season']![0] = _mapped('e1', 'Episode', parent: 'season', number: 1, season: 1, end: 2);
    final season = (((await f.diagnose())['items'] as List).single['seasons'] as List).single;
    expect(season['numbering_gaps'], isEmpty);
    expect(season['missing_aired'], isEmpty);
  });
  test('malformed numbering and partial child pages cannot prove missing', () async {
    for (final malformed in [false, true]) {
      final f = _Fixture();
      if (malformed) {
        f.server.pages['season']![0] = _mapped('e1', 'Episode', parent: 'season', number: 1, season: 1, end: '2');
      } else {
        f.server.totals['season'] = 9;
      }
      final data = await f.diagnose();
      final season = ((data['items'] as List).single['seasons'] as List).single;
      expect(season['missing_aired'], isEmpty);
      if (!malformed) expect(data['partial'], true);
    }
  });
  test('raw stream provenance keeps editions and present absent unknown separate', () async {
    final f = _Fixture();
    f.server.items['movie'] = _mapped(
      'movie',
      'Movie',
      sources: [
        {
          'Id': 'dutch',
          'Name': 'Director cut',
          'MediaStreams': [
            {'Type': 'Subtitle', 'Language': 'nld', 'Index': 0},
          ],
        },
        {
          'Id': 'english',
          'Name': 'Theatrical',
          'MediaStreams': [
            {'Type': 'Subtitle', 'Language': 'eng', 'Index': 0},
          ],
        },
        {'Id': 'omitted', 'Name': 'Unknown'},
        {
          'Id': 'unlabelled',
          'MediaStreams': [
            {'Type': 'Subtitle', 'Index': 0},
          ],
        },
      ],
    );
    final data = await f.diagnose(args: {'server_id': 's', 'library_id': 'films'});
    final versions = (data['items'] as List).single['versions'] as List;
    expect([for (final v in versions) v['dutch_subtitles']], ['present', 'absent', 'unknown', 'unknown']);
    expect(versions.first['name'], 'Director cut');
    expect(data['groups'], everyElement(containsPair('duplicate_status', 'not_proven')));
  });
  test('hidden library and forged or unshown item are refused', () async {
    final f = _Fixture();
    f.hidden.add('s:series');
    await expectLater(f.diagnose(), throwsA(isA<AssistantToolError>()));
    expect(f.server.reads, isEmpty);
    await expectLater(
      f.diagnose(args: {'server_id': 's', 'library_id': 'films', 'item_id': 'forged'}),
      throwsA(isA<AssistantToolError>()),
    );
    expect(f.server.reads, isEmpty);
  });
  test('pure missing-episode questions advertise Doctor while narrative questions remain fenced', () async {
    for (final prompt in ['Welke afleveringen missen in seizoen 3?', 'Which episodes are missing from season 3?']) {
      final f = _Fixture();
      final model = _Model([_reply(null)]);
      await AssistantRun(
        model: model,
        context: f.ctx,
        confirm: (_) async => null,
        entitlement: _Entitlement(),
        refreshHealth: () async {},
      ).ask(prompt);
      expect(model.specs.first, contains('diagnose_library'), reason: prompt);
      expect(model.specs.first, isNot(contains('scan_library')));
    }
    for (final prompt in [
      'Welke aflevering was dat waarin Anna verdween?',
      'Which episodes are missing and what happens in the finale?',
      'Which episodes are missing? Explain the story.',
    ]) {
      final f = _Fixture();
      final model = _Model([_reply(null)]);
      await AssistantRun(
        model: model,
        context: f.ctx,
        confirm: (_) async => null,
        entitlement: _Entitlement(),
        refreshHealth: () async {},
      ).ask(prompt);
      expect(model.specs.first, ['spoiler_context'], reason: prompt);
    }
  });
  test('closing model wait cannot publish stale Doctor facts or hallucinated repairs', () async {
    final f = _Fixture();
    final model = _Model([
      _reply('diagnose_library', {'server_id': 's', 'library_id': 'series'}),
    ])..closing = Completer<void>();
    final controller = AssistantController(
      buildContext: (_) => f.ctx,
      entitlement: _Entitlement(),
      loadConfig: () async => _config,
      modelFor: (_) => model,
    );
    addTearDown(controller.dispose);
    final running = controller.submit('Diagnose my library');
    await pumpEventQueue();
    expect(model.specs, hasLength(2));
    f.profile = 'other';
    model.closing!.complete();
    await running;
    expect(controller.tasks.single.answer, isEmpty);
    expect(controller.tasks.single.error, 'profile_changed');
    expect(controller.tasks.single.steps, isEmpty);
  });
  test('fresh Doctor answer is grounded and labels unknown rather than closing model prose', () async {
    final f = _Fixture();
    f.seerr.details['/tv/10/season/1'] = {};
    final result = await AssistantRun(
      model: _Model([
        _reply('diagnose_library', {'server_id': 's', 'library_id': 'series'}),
      ]),
      context: f.ctx,
      confirm: (_) async => null,
      entitlement: _Entitlement(),
      refreshHealth: () async {},
      languageName: 'English',
    ).ask('Diagnose my library');
    expect(result.text, contains('Numbering gaps: 2'));
    expect(result.text, contains('unknown'));
    expect(result.text, isNot(contains('Closing answer')));
  });
  test('Doctor refresh proposal uses existing confirmation and writes only on execute', () async {
    final f = _Fixture();
    final data = await f.diagnose(args: {'server_id': 's', 'library_id': 'films'});
    final proposal = (data['actions'] as List).single as Map;
    final outcome = await _tool('refresh_metadata').run(f.ctx, _id, Map<String, Object?>.from(proposal));
    expect(outcome, isA<AssistantPendingAction>());
    expect(f.server.writes, isEmpty);
    final action = outcome as AssistantPendingAction;
    expect(action.kind, AssistantActionKind.refreshMetadata);
    await action.execute();
    expect(f.server.writes, ['refresh:movie']);
    await expectLater(action.execute(), throwsA(isA<AssistantToolError>()));
    expect(f.server.writes, hasLength(1));
  });
  test(
    'Doctor mode rejects missing forged cross-context and wrong-identity proposal without legacy fallthrough',
    () async {
      final f = _Fixture();
      final data = await f.diagnose(args: {'server_id': 's', 'library_id': 'films'});
      final proposal = Map<String, Object?>.from((data['actions'] as List).single as Map);
      for (final args in [
        {'item_id': 'movie'},
        {...proposal, 'doctor_option_id': 'forged'},
        {...proposal, 'item_id': 'other'},
        {...proposal, 'library_id': 'series'},
      ]) {
        await expectLater(_tool('refresh_metadata').run(f.ctx, _id, args), throwsA(isA<AssistantToolError>()));
      }
      await expectLater(
        _tool('refresh_metadata').run(f.ctx.fresh(), _id, proposal),
        throwsA(isA<AssistantToolError>()),
      );
      await expectLater(
        _tool('scan_library').run(f.ctx, _id, {'library_id': 'films'}),
        throwsA(isA<AssistantToolError>()),
      );
      expect(f.server.writes, isEmpty);
    },
  );
  test('proposal rechecks downgrade profile root and item scope at confirmed execute', () async {
    for (final change in <void Function(_Fixture)>[
      (f) => f.manager.admin = false,
      (f) => f.profile = 'other',
      (f) => f.hidden.add('s:films'),
      (f) => f.server.items['movie'] = _mapped('other', 'Movie'),
    ]) {
      final f = _Fixture();
      final proposal = Map<String, Object?>.from(
        ((await f.diagnose(args: {'server_id': 's', 'library_id': 'films'}))['actions'] as List).single as Map,
      );
      final outcome = await _tool('refresh_metadata').run(f.ctx, _id, proposal);
      expect(outcome, isA<AssistantPendingAction>());
      change(f);
      await expectLater((outcome as AssistantPendingAction).execute(), throwsA(isA<AssistantToolError>()));
      expect(f.server.writes, isEmpty);
    }
  });
  test('ordinary single-command scan retains existing immediate policy', () async {
    final f = _Fixture();
    await AssistantRun(
      model: _Model([
        _reply('scan_library', {'server_id': 's', 'library_id': 'films'}),
      ]),
      context: f.ctx,
      confirm: (_) async => throw StateError('Ordinary scan needs no card'),
      entitlement: _Entitlement(),
      refreshHealth: () async {},
    ).ask('Scan my library');
    expect(f.server.writes, ['scan:films']);
  });
  test('unknown raw language never proves absent Dutch subtitles', () async {
    final f = _Fixture();
    f.server.items['movie'] = _mapped(
      'movie',
      'Movie',
      sources: [
        {
          'Id': 'bad',
          'MediaStreams': [
            {'Type': 'Subtitle', 'Language': 'unrecognised'},
          ],
        },
      ],
    );
    final data = await f.diagnose(args: {'server_id': 's', 'library_id': 'films'});
    expect(((data['items'] as List).single['versions'] as List).single['dutch_subtitles'], 'unknown');
  });
  test('alternate scan target cannot use a real Doctor token', () async {
    final f = _Fixture();
    final data = await f.diagnose();
    final proposal = Map<String, Object?>.from(
      (data['actions'] as List).firstWhere((a) => a['tool'] == 'scan_library') as Map,
    );
    for (final args in [
      {...proposal, 'library_id': 'films'},
      {...proposal, 'item_id': 'other'},
      {...proposal, 'doctor_option_id': 'forged'},
    ]) {
      await expectLater(_tool('scan_library').run(f.ctx, _id, args), throwsA(isA<AssistantToolError>()));
    }
    expect(f.server.writes, isEmpty);
  });
  test('missing-episode diagnosis phrasing closes initial direct-admin bypass', () async {
    for (final prompt in [
      'Diagnose missing episodes in Dune',
      'Find missing episodes in season 3',
      'Controleer afleveringen in seizoen 3',
    ]) {
      final f = _Fixture();
      final model = _Model([
        _reply('scan_library', {'server_id': 's', 'library_id': 'films'}),
      ]);
      await AssistantRun(
        model: model,
        context: f.ctx,
        confirm: (_) async => throw StateError('No proposal'),
        entitlement: _Entitlement(),
        refreshHealth: () async {},
      ).ask(prompt);
      expect(f.server.writes, isEmpty, reason: prompt);
      expect(model.specs.first, isNot(contains('scan_library')));
    }
  });
  test('confirmation refusal and cancellation run existing queue with zero writes', () async {
    for (final cancel in [false, true]) {
      final f = _Fixture();
      final model = _Model([]);
      model.respond = (messages) async {
        if (model.specs.length == 1) return _reply('diagnose_library', {'server_id': 's', 'library_id': 'films'});
        final toolMessages = messages.where((m) => m['role'] == 'tool');
        if (model.specs.length == 2) {
          final data = jsonDecode(toolMessages.last['content'] as String) as Map;
          return _reply('refresh_metadata', Map<String, Object?>.from((data['actions'] as List).single as Map));
        }
        return _reply(null);
      };
      final controller = AssistantController(
        buildContext: (_) => f.ctx,
        entitlement: _Entitlement(),
        loadConfig: () async => _config,
        modelFor: (_) => model,
      );
      addTearDown(controller.dispose);
      final running = controller.submit('Diagnose my library');
      await pumpEventQueue();
      final task = controller.tasks.single;
      expect(controller.pendingConfirmation, isNotNull);
      expect(f.server.writes, isEmpty);
      if (cancel) {
        controller.cancelTask(task.id);
      } else {
        controller.cancelPending();
      }
      await running;
      expect(f.server.writes, isEmpty);
      expect(controller.actions, isEmpty);
    }
  });
  test('nonabortable hydration cancellation and new question discard late Doctor callbacks', () async {
    final f = _Fixture();
    f.server.stall = Completer<void>();
    var count = 0;
    final controller = AssistantController(
      buildContext: (_) => f.ctx,
      entitlement: _Entitlement(),
      loadConfig: () async => _config,
      modelFor: (_) => _Model([
        ++count == 1 ? _reply('diagnose_library', {'server_id': 's', 'library_id': 'films'}) : _reply(null),
      ]),
    );
    addTearDown(controller.dispose);
    final old = controller.submit('Diagnose my library');
    await pumpEventQueue();
    expect(f.server.reads, contains('item:movie'));
    await controller.submit('hello');
    await old.timeout(const Duration(seconds: 1));
    f.server.stall!.complete();
    await pumpEventQueue();
    expect(controller.tasks.single.title, 'hello');
    expect(controller.answer, 'Closing answer');
    expect(controller.steps.every((s) => s.tool != 'diagnose_library'), isTrue);
    expect(f.server.writes, isEmpty);
  });
  test('specials repeated pages wrong source and explicit date mismatch remain unproved', () async {
    for (final change in <void Function(_Fixture)>[
      (f) => f.server.pages['show']![0] = _mapped('season', 'Season', parent: 'show', number: 0),
      (f) => f.server.pages['season']![0] = _mapped('e1', 'Episode', parent: 'other', number: 1, season: 1),
      (f) => f.server.pages['season']![0] = _mapped(
        'e1',
        'Episode',
        parent: 'season',
        number: 1,
        season: 1,
      ).copyWith(originallyAvailableAt: '2021-01-01'),
      (f) {
        f.server.repeat = true;
        f.server.totals['series'] = 3;
      },
    ]) {
      final f = _Fixture();
      change(f);
      final data = await f.diagnose();
      final seasons = (data['items'] as List).single['seasons'] as List;
      expect(seasons.map((s) => s['missing_aired']), everyElement(isEmpty));
      expect((data['coverage'] as Map)['read_operations'], lessThanOrEqualTo(100));
    }
  });
  test('confirmation validation has its own bound after diagnosis deadline has elapsed', () async {
    final f = _Fixture();
    final proposal = Map<String, Object?>.from(
      ((await f.diagnose(args: {'server_id': 's', 'library_id': 'films'}))['actions'] as List).single as Map,
    );
    final action = await _tool('refresh_metadata').run(f.ctx, _id, proposal) as AssistantPendingAction;
    await Future<void>.delayed(const Duration(seconds: 16));
    await action.execute();
    expect(f.server.writes, ['refresh:movie']);
  });
  test('copies preserve concrete metadata differences in the grounded final answer', () async {
    final f = _Fixture();
    final a = _mapped('a', 'Movie', overview: 'First summary').copyWith(title: 'Same title');
    final b = _mapped('b', 'Movie', overview: 'Second summary').copyWith(title: 'Same title');
    f.server.pages['films'] = [a, b];
    f.server.items.addAll({'a': a, 'b': b});
    final result = await AssistantRun(
      model: _Model([
        _reply('diagnose_library', {'server_id': 's', 'library_id': 'films'}),
      ]),
      context: f.ctx,
      confirm: (_) async => null,
      entitlement: _Entitlement(),
      refreshHealth: () async {},
      languageName: 'English',
    ).ask('Diagnose my library');
    expect(result.text, contains('First summary'));
    expect(result.text, contains('Second summary'));
    expect(result.text, contains('duplicates are not proved'));
  });
  test('actual split children keep Doctor mode and reject another child proposal token', () async {
    final f = _Fixture();
    final firstProposal = Completer<Map<String, Object?>>();
    var created = 0;
    final controller = AssistantController(
      buildContext: (_) => f.ctx,
      entitlement: _Entitlement(),
      loadConfig: () async => _config,
      modelFor: (_) {
        final index = created++;
        if (index == 0) {
          return _Model([
            _reply('split_tasks', {
              'tasks': [
                {'title': 'diagnosis', 'intent': 'read', 'prompt': 'Diagnose films'},
                {'title': 'repair', 'intent': 'scan', 'prompt': 'Scan films'},
              ],
            }),
          ]);
        }
        final model = _Model([]);
        model.respond = (messages) async {
          if (model.specs.length == 1) return _reply('diagnose_library', {'server_id': 's', 'library_id': 'films'});
          if (model.specs.length == 2) {
            final last = messages.lastWhere((m) => m['role'] == 'tool');
            final data = jsonDecode(last['content'] as String) as Map;
            final own = Map<String, Object?>.from((data['actions'] as List).single as Map);
            if (index == 1) {
              firstProposal.complete(own);
            } else {
              return _reply('refresh_metadata', await firstProposal.future);
            }
          }
          return _reply(null);
        };
        return model;
      },
    );
    addTearDown(controller.dispose);
    await controller.submit('Diagnose my library and inspect another library');
    expect(controller.tasks, hasLength(2));
    expect(controller.tasks.last.error, 'unknown_doctor_option');
    expect(f.server.writes, isEmpty);
    expect(controller.pendingConfirmation, isNull);
    expect(controller.tasks.first.answer, contains('Library diagnosis'));
  });
  test('scope changes during nonabortable hydration refuse facts before registering IDs', () async {
    for (final change in <void Function(_Fixture)>[
      (f) => f.profile = 'other',
      (f) => f.hidden.add('s:films'),
      (f) => f.manager.setVisibleServerIds({}),
      (f) => f.manager.debugRegisterClientForTesting(_Server()),
    ]) {
      final f = _Fixture();
      f.server.stall = Completer<void>();
      final future = f.diagnose(args: {'server_id': 's', 'library_id': 'films'});
      final rejected = expectLater(future, throwsA(isA<AssistantToolError>()));
      await pumpEventQueue();
      change(f);
      f.server.stall!.complete();
      await rejected;
      expect(() => f.ctx.requireShownItem(_id, 'movie'), throwsA(isA<AssistantToolError>()));
      expect(f.server.writes, isEmpty);
    }
  });
  test('confirmation callback refuses downgrade during its fresh item await', () async {
    final f = _Fixture();
    final proposal = Map<String, Object?>.from(
      ((await f.diagnose(args: {'server_id': 's', 'library_id': 'films'}))['actions'] as List).single as Map,
    );
    final action = await _tool('refresh_metadata').run(f.ctx, _id, proposal) as AssistantPendingAction;
    f.server.stall = Completer<void>();
    final running = action.execute();
    final rejected = expectLater(running, throwsA(isA<AssistantToolError>()));
    await pumpEventQueue();
    f.manager.admin = false;
    f.server.stall!.complete();
    await rejected;
    expect(f.server.writes, isEmpty);
  });
  test('initial offline source reports partial coverage with unknown facts', () async {
    final f = _Fixture();
    f.manager.debugRegisterClientForTesting(f.server, online: false);
    final data = await f.diagnose();
    expect(data['partial'], true);
    expect(data['items'], isEmpty);
    expect((data['coverage'] as Map)['limits'], contains('server_unavailable'));
    expect(f.server.reads, isEmpty);
  });
  test('opaque model IDs are compared exactly without truncation', () async {
    final f = _Fixture();
    final id = 'l' * 120;
    f.libraries.add(find.fakeLib('s', id));
    final data = await f.diagnose(args: {'server_id': 's', 'library_id': id});
    expect(data['items'], isEmpty);
    expect(data['partial'], false);
    expect(f.server.reads, ['library:$id']);
    f.server.reads.clear();
    await expectLater(
      f.diagnose(args: {'server_id': 's', 'library_id': '${id}forged'}),
      throwsA(isA<AssistantToolError>()),
    );
    expect(f.server.reads, isEmpty);
  });
  test('a reply introducing Doctor fences earlier administrative siblings', () async {
    final f = _Fixture();
    final reply = AssistantReply(
      content: '',
      toolCalls: [
        AssistantToolCall(
          id: 'write-first',
          name: 'scan_library',
          arguments: jsonEncode({'server_id': 's', 'library_id': 'films'}),
        ),
        AssistantToolCall(
          id: 'doctor-second',
          name: 'diagnose_library',
          arguments: jsonEncode({'server_id': 's', 'library_id': 'films'}),
        ),
      ],
      message: {'role': 'assistant', 'content': ''},
    );
    await AssistantRun(
      model: _Model([reply]),
      context: f.ctx,
      confirm: (_) async => null,
      entitlement: _Entitlement(),
      refreshHealth: () async {},
    ).ask('Check the collection');
    expect(f.server.writes, isEmpty);
  });
  test('ordinary metadata refresh is compatible outside a Doctor diagnosis', () async {
    final f = _Fixture();
    final show = AssistantTool(
      name: 'show_movie',
      description: 'Test read',
      risk: AssistantToolRisk.read,
      needsServer: false,
      properties: const {},
      serves: (_, _) => true,
      run: (ctx, _, _) async {
        ctx.showItem(_id, 'movie');
        return const AssistantToolResult({'item_id': 'movie', 'server_id': 's'});
      },
    );
    final model = _Model([
      _reply('show_movie'),
      _reply('refresh_metadata', {'server_id': 's', 'item_id': 'movie'}),
    ]);
    await AssistantRun(
      model: model,
      context: f.ctx,
      tools: [show, _tool('refresh_metadata'), _tool('diagnose_library')],
      confirm: (_) async => throw StateError('Ordinary refresh needs no card'),
      entitlement: _Entitlement(),
      refreshHealth: () async {},
    ).ask('Refresh metadata for this library item');
    expect(f.server.writes, ['refresh:movie']);
  });
  test('Doctor tool-free reply cannot invent evidence or a repair', () async {
    final f = _Fixture();
    final result = await AssistantRun(
      model: _Model([_reply(null)]),
      context: f.ctx,
      confirm: (_) async => null,
      entitlement: _Entitlement(),
      refreshHealth: () async {},
      languageName: 'English',
    ).ask('Diagnose my library');
    expect(result.text, contains('unknown'));
    expect(result.text, isNot(contains('Closing answer')));
    expect(f.server.writes, isEmpty);
  });
}
