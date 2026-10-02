import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_find_match.dart';
import 'package:pleya/assistant/assistant_find_route.dart';
import 'package:pleya/assistant/assistant_plot_index.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/assistant/assistant_web_lookup.dart';
import 'package:pleya/assistant/assistant_web_search.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_identity.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/seerr/seerr_client.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/seerr/seerr_session.dart';
import 'package:pleya/services/unified_catalog/home_custom_row_loader.dart';
import 'package:pleya/utils/external_ids.dart';

import '../test_helpers/prefs.dart';

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: const {'content-type': 'application/json'});

MediaItem _item(String id, String title, {MediaKind kind = MediaKind.movie, int? year, String? summary, String? lib}) =>
    MediaItem(
      id: id,
      backend: MediaBackend.jellyfin,
      kind: kind,
      title: title,
      year: year,
      summary: summary,
      libraryId: lib,
    );

/// A media server holding [libraries] (library id → items), with external
/// ids per item and children per parent.
class _Server implements MediaServerClient {
  _Server(String id, {this.libraries = const {}, this.ids = const {}, this.children = const {}})
    : serverId = ServerId(id);
  @override
  final ServerId serverId;
  final Map<String, List<MediaItem>> libraries;
  final Map<String, ExternalIds> ids;
  final Map<String, List<MediaItem>> children;
  final identities = <MediaIdentity>[];

  @override
  MediaBackend get backend => MediaBackend.jellyfin;
  @override
  String get serverName => serverId.value;

  Iterable<MediaItem> get _all => libraries.entries.expand((e) => e.value.map((i) => i.copyWith(libraryId: e.key)));

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryContent(String libraryId, LibraryQuery query) async {
    final items = [
      for (final i in libraries[libraryId] ?? const <MediaItem>[])
        if (i.kind == query.kind) i.copyWith(libraryId: libraryId),
    ];
    return LibraryPage(items: query.offset == 0 ? items : const [], totalCount: items.length);
  }

  @override
  Future<List<MediaItem>> findAllByIdentity(MediaIdentity identity) async {
    identities.add(identity);
    final tmdb = identity.externalIds.tmdb;
    return [
      for (final i in _all)
        if (tmdb != null ? ids[i.id]?.tmdb == tmdb : i.title == identity.title) i,
    ];
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => ids[itemId] ?? const ExternalIds();

  @override
  Future<List<MediaItem>> fetchChildren(String parentId) async => children[parentId] ?? const [];

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaLibrary _lib(String server, String id, {MediaKind kind = MediaKind.movie}) =>
    MediaLibrary(id: id, backend: MediaBackend.jellyfin, title: id, kind: kind, serverId: server, serverName: server);

/// Wikipedia, Wikidata and the web search behind fakes, counting every call.
class _Web {
  final hosts = <String>[];
  Map<String, Object> wiki = const {};
  Map<String, Object> entities = const {};
  Completer<http.Response>? stall;
  final search = _Search();

  late final services = AssistantWebServices(
    search: search,
    client: MockClient((request) async {
      hosts.add(request.url.host);
      if (stall != null) return stall!.future;
      if (request.url.host == 'www.wikidata.org') return _json({'entities': entities});
      final pages = request.url.host.startsWith('en.') ? wiki[request.url.queryParameters['gsrsearch']] : null;
      return _json({
        if (pages != null) 'query': {'pages': pages},
      });
    }),
  );
}

class _Search implements WebSearchClient {
  final queries = <String>[];
  List<WebSearchHit> hits = const [];
  @override
  Future<List<WebSearchHit>> search(String query, {int maxResults = 5}) async {
    queries.add(query);
    return hits;
  }
}

/// Overseerr behind fake HTTP.
class _Seerr {
  final paths = <String>[];
  Map<String, List<Map<String, Object?>>> search = {};
  Map<String, Map<String, Object?>> details = {};

  late final client = SeerrClient(
    SeerrSession(baseUrl: 'http://seerr.lan', authMode: SeerrAuthMode.apiKey, apiKey: 'k'),
    httpClient: MockClient((request) async {
      final path = request.url.path.replaceFirst('/api/v1', '');
      paths.add(path == '/search' ? 'search:${request.url.queryParameters['query']}' : path);
      if (path == '/search') {
        return _json({'page': 1, 'totalPages': 1, 'results': search[request.url.queryParameters['query']] ?? []});
      }
      return _json(details[path] ?? {});
    }),
  );
}

AssistantToolContext _ctx(
  List<_Server> servers, {
  List<MediaLibrary> libraries = const [],
  Set<String> hidden = const {},
  Set<String>? visible,
  _Seerr? seerr,
  _Web? web,
}) {
  final m = MultiServerManager();
  addTearDown(m.dispose);
  for (final s in servers) {
    m.debugRegisterClientForTesting(s);
  }
  m.setVisibleServerIds(visible);
  return AssistantToolContext(
    servers: m,
    catalog: AssistantCatalogServices(
      rowLoader: CatalogHomeCustomRowLoader(
        libraries: () => libraries,
        isServerVisible: m.isServerVisible,
        hiddenLibraryKeys: () => hidden,
        clientFor: m.getClient,
      ),
      profileId: 'p',
      activeProfileId: () => 'p',
    ),
    requests: seerr == null ? null : AssistantRequestServices(client: () => seerr.client),
    web: web?.services,
  );
}

Future<Map<String, Object?>> _find(AssistantToolContext ctx, Map<String, Object?> args) async {
  final tool = assistantTools.firstWhere((t) => t.name == 'find_title');
  return ((await tool.run(ctx, null, args)) as AssistantToolResult).data;
}

List<Map<String, Object?>> _matches(Map<String, Object?> data) => (data['matches'] as List).cast();

const _matrixPlot = 'A hacker learns that reality is a simulation run by machines.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetSharedPreferencesForTest);

  test('the own synopsis answers first: no Wikipedia, Wikidata or web call', () async {
    final web = _Web();
    final server = _Server(
      'zolder',
      libraries: {
        'films': [
          _item('1', 'The Matrix', year: 1999, summary: _matrixPlot),
          _item('2', 'Amélie', year: 2001, summary: 'A shy waitress in Paris.'),
        ],
      },
    );
    final ctx = _ctx([server], libraries: [_lib('zolder', 'films')], web: web);
    final data = await _find(ctx, {
      'candidates': [
        {'title': 'The Matrix', 'year': 1999},
      ],
      'variants': ['hacker reality simulation machines', 'hacker werkelijkheid simulatie'],
    });

    final top = _matches(data).first;
    expect(top['title'], 'The Matrix');
    expect(top['confidence'], 'high');
    expect(top['in_library'], isTrue);
    expect(top['servers'], ['zolder']);
    expect(top['sources'], containsAll(['model', 'library_plot']));
    expect(web.hosts, isEmpty);
    expect(web.search.queries, isEmpty);
    ctx.requireShownItem(ServerId('zolder'), '1');
  });

  test('a Wikipedia hit is normalised through Seerr search, without Wikidata', () async {
    final web = _Web()
      ..wiki = {
        'dream heist inside dreams': [
          {
            'title': 'Inception',
            'index': 1,
            'description': '2010 film by Christopher Nolan',
            'pageprops': {'wikibase_item': 'Q25188'},
          },
        ],
      };
    final seerr = _Seerr()
      ..search = {
        'Inception': [
          {'id': 27205, 'mediaType': 'movie', 'title': 'Inception', 'releaseDate': '2010-07-15'},
        ],
      };
    final ctx = _ctx(const [], seerr: seerr, web: web);
    final data = await _find(ctx, {
      'variants': ['dream heist inside dreams', 'diefstal in dromen'],
    });

    final top = _matches(data).single;
    expect(top['title'], 'Inception');
    expect(top['seerr_id'], 'movie:27205');
    expect(top['seerr_status'], 'not_requested');
    expect(web.hosts, isNot(contains('www.wikidata.org')));
    // Registered in the request allow-list.
    final picked = await assistantRequestFromOption(ctx, 'movie:27205');
    expect(picked is AssistantToolResult ? picked.data['error'] : null, isNot('unknown_seerr_id'));
  });

  test('without Seerr, Wikidata bridges the id to the library', () async {
    final web = _Web()
      ..wiki = {
        'dream heist inside dreams': [
          {
            'title': 'Inception (film)',
            'description': '2010 film',
            'pageprops': {'wikibase_item': 'Q25188'},
          },
        ],
      }
      ..entities = {
        'Q25188': {
          'claims': {
            'P4947': [
              {
                'mainsnak': {
                  'datavalue': {'value': '27205'},
                },
              },
            ],
          },
        },
      };
    final server = _Server(
      'zolder',
      libraries: {
        'films': [_item('9', 'Origine', year: 2010)],
      },
      ids: {'9': const ExternalIds(tmdb: 27205)},
    );
    final ctx = _ctx([server], libraries: [_lib('zolder', 'films')], web: web);
    final data = await _find(ctx, {
      'variants': ['dream heist inside dreams', 'dromen'],
    });

    expect(web.hosts.where((h) => h == 'www.wikidata.org'), hasLength(1));
    final top = _matches(data).first;
    expect(top['in_library'], isTrue);
    expect(top['item_id'], '9');
    expect(server.identities.single.externalIds.tmdb, 27205);
  });

  test('copies on several servers stay one title', () async {
    final a = _Server(
      'zolder',
      libraries: {
        'films': [_item('a1', 'Heat', year: 1995, summary: 'A detective hunts a crew of bank robbers.')],
      },
      ids: {'a1': const ExternalIds(tmdb: 949)},
    );
    final b = _Server(
      'kelder',
      libraries: {
        'movies': [_item('b1', 'Heat', year: 1995, summary: 'Bank robbers and a detective in Los Angeles.')],
      },
      ids: {'b1': const ExternalIds(tmdb: 949)},
    );
    final ctx = _ctx([a, b], libraries: [_lib('zolder', 'films'), _lib('kelder', 'movies')]);
    final data = await _find(ctx, {
      'candidates': [
        {'title': 'Heat', 'year': 1995},
      ],
      'variants': ['detective bank robbers', 'bankrovers'],
    });

    final heat = _matches(data).where((m) => m['title'] == 'Heat').toList();
    expect(heat, hasLength(1));
    expect(heat.single['servers'], unorderedEquals(['zolder', 'kelder']));
  });

  test('a hidden library and a hidden server stay out', () async {
    final a = _Server(
      'zolder',
      libraries: {
        'films': [_item('1', 'Amélie', summary: 'A shy waitress in Paris.')],
        'kids': [_item('2', 'The Matrix', summary: _matrixPlot)],
      },
    );
    final b = _Server(
      'kelder',
      libraries: {
        'movies': [_item('3', 'The Matrix', summary: _matrixPlot)],
      },
    );
    final kids = _lib('zolder', 'kids');
    final ctx = _ctx(
      [a, b],
      libraries: [_lib('zolder', 'films'), kids, _lib('kelder', 'movies')],
      hidden: {kids.globalKey},
      visible: {'zolder'},
    );
    final data = await _find(ctx, {
      'candidates': [
        {'title': 'The Matrix'},
      ],
      'variants': ['hacker reality simulation', 'simulatie'],
    });

    expect(_matches(data).where((m) => m['in_library'] == true), isEmpty);
  });

  test('an episode is found among its series\' children', () async {
    final server = _Server(
      'zolder',
      libraries: {
        'series': [_item('dw', 'Doctor Who', kind: MediaKind.show, summary: 'A time traveller.')],
      },
      children: {
        'dw': [_item('s3', 'Season 3', kind: MediaKind.season).copyWith(index: 3)],
        's3': [
          _item(
            'e1',
            'Smith and Jones',
            kind: MediaKind.episode,
            summary: 'A hospital moves to the moon.',
          ).copyWith(index: 1, parentIndex: 3),
          _item(
            'e10',
            'Blink',
            kind: MediaKind.episode,
            summary: 'Weeping angels: statues that move when you blink.',
          ).copyWith(index: 10, parentIndex: 3),
        ],
      },
    );
    final ctx = _ctx([server], libraries: [_lib('zolder', 'series', kind: MediaKind.show)]);
    final data = await _find(ctx, {
      'kind': 'episode',
      'series': 'Doctor Who',
      'variants': ['statues angels move blink', 'beelden engelen'],
    });

    final top = _matches(data).first;
    expect(top['kind'], 'episode');
    expect(top['title'], 'Blink');
    expect(top['series'], 'Doctor Who');
    expect([top['season'], top['episode']], [3, 10]);
    expect(top['item_id'], 'e10');
    ctx.requireShownItem(ServerId('zolder'), 'e10');
  });

  test('the web is searched once, and only when the cheap sources fall short', () async {
    final web = _Web();
    web.search.hits = [
      (title: 'Primer (2004) - IMDb', url: 'https://imdb.example', snippet: 'Engineers build a time machine.'),
      (title: 'Primer (film) - Wikipedia', url: 'https://wiki.example', snippet: 'Primer is a 2004 film.'),
    ];
    final ctx = _ctx(const [], web: web);
    final data = await _find(ctx, {
      'variants': ['garage engineers accidental time machine', 'tijdmachine'],
    });

    expect(web.search.queries, ['garage engineers accidental time machine']);
    expect(data['web_searched'], isTrue);
    expect(_matches(data).first['title'], 'Primer');
  });

  test('ids from the model are never used', () async {
    final seerr = _Seerr();
    final ctx = _ctx(const [], seerr: seerr);
    await _find(ctx, {
      'candidates': [
        {'title': 'tt0133093'},
        {'title': 'tmdb:603'},
        {'title': 'Heat', 'tmdb_id': 999},
      ],
      'variants': ['a', 'b'],
    });

    expect(seerr.paths, ['search:Heat']);
  });

  test('the deadline returns early with what is there, and starts nothing new', () async {
    final web = _Web()..stall = Completer();
    final server = _Server(
      'zolder',
      libraries: {
        'films': [
          _item('1', 'Amélie', summary: 'A shy waitress in Paris.'),
          _item('2', 'Chocolat', summary: 'A shy waitress in a French village, far from Paris.'),
        ],
      },
    );
    final ctx = _ctx([server], libraries: [_lib('zolder', 'films')], web: web);
    final clock = Stopwatch()..start();
    final result = await findTitles(
      ctx,
      const FindQuery(variants: ['shy waitress paris', 'serveerster']),
      budget: const Duration(milliseconds: 300),
      headStart: Duration.zero,
      plots: AssistantPlotIndexCache(),
    );

    expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
    expect(result.partial, isTrue);
    expect(result.matches.map((m) => m.title), contains('Amélie'));
    expect(web.search.queries, isEmpty);
    expect(web.hosts.where((h) => h == 'www.wikidata.org'), isEmpty);
  });

  test('with the web off nothing external is asked', () async {
    final seerr = _Seerr()
      ..search = {
        'Heat': [
          {'id': 949, 'mediaType': 'movie', 'title': 'Heat', 'releaseDate': '1995-12-15'},
        ],
      };
    final ctx = _ctx(const [], seerr: seerr);
    final data = await _find(ctx, {
      'candidates': [
        {'title': 'Heat'},
      ],
      'variants': ['bank robbers', 'bankrovers'],
    });

    final top = _matches(data).single;
    expect(top['seerr_id'], 'movie:949');
    expect(top['sources'], isNot(anyOf(contains('wikipedia'), contains('web'))));
    expect(ctx.web, isNull);
  });

  test('web titles drop the site name and keep the year', () {
    expect(webTitle('Primer (2004) - IMDb'), (title: 'Primer', year: 2004));
    expect(webTitle('Heat (film) | Wikipedia'), (title: 'Heat', year: null));
  });
}
