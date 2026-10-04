import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_title_facts.dart';
import 'package:pleya/assistant/assistant_title_facts_cache.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/utils/external_ids.dart';

import 'assistant_find_fakes.dart';

/// Facts per title, as the chain would have found them.
class _Facts extends TitleFactsService {
  _Facts({super.tmdbKey, super.httpClient}) : super(cache: TitleFactsCache());
  static const byTitle = {
    'Harry Potter': TitleFacts(certifications: {'NL': '12', 'US': 'PG-13'}),
    'Toy Story': TitleFacts(certifications: {'NL': 'AL', 'US': 'G'}),
  };
  @override
  Future<List<TitleFacts>> factsFor(List<TitleRef> refs) async => [
    for (final r in refs) byTitle[r.title] ?? const TitleFacts(),
  ];
}

Map<String, Object?> _film(int id, String title, String date) => {
  'id': id,
  'mediaType': 'movie',
  'title': title,
  'releaseDate': date,
};

Map<String, Object?> _page(List<Map<String, Object?>> results) => {'page': 1, 'totalPages': 1, 'results': results};

AssistantToolContext _ctx({FakeSeerr? seerr, FakeServer? server, String? tmdbKey, http.Client? net, int? age}) {
  final base = findCtx(
    [?server],
    libraries: server == null ? const [] : [fakeLib('w', 'films'), fakeLib('w', 'shows', kind: MediaKind.show)],
    seerr: seerr,
  );
  return AssistantToolContext(
    servers: base.servers,
    catalog: base.catalog,
    requests: base.requests,
    titleFacts: _Facts(tmdbKey: () => tmdbKey, httpClient: net),
    kidsAges: () async => [?age],
    region: () => 'NL',
  );
}

Future<Map<String, Object?>> _run(AssistantToolContext ctx, String name, Map<String, Object?> args) async =>
    ((await assistantTools.firstWhere((t) => t.name == name).run(ctx, null, args)) as AssistantToolResult).data;

List<Map<String, Object?>> _titles(Map<String, Object?> data) => (data['titles'] as List).cast();

Object _tmdbList(List<Map<String, Object?>> results) => {'results': results};

void main() {
  late FakeServer library;
  setUp(() {
    library = FakeServer(
      'w',
      libraries: {
        'films': [fakeItem('ts', 'Toy Story', year: 1995)],
        'shows': [fakeItem('dk', 'Dark', kind: MediaKind.show, year: 2017)],
      },
      ids: {'ts': const ExternalIds(tmdb: 862), 'dk': const ExternalIds(tmdb: 70523)},
    );
  });

  test('trending via Seerr: a library hit is a library card, a missing title can be requested', () async {
    final seerr = FakeSeerr()
      ..details['/discover/trending'] = _page([
        _film(862, 'Toy Story', '1995-11-22'),
        _film(438631, 'Dune', '2021-09-15'),
        {'id': 5, 'mediaType': 'person', 'name': 'Someone'},
      ])
      // The request card reads the title fresh and checks it is this one.
      ..details['/movie/438631'] = {'id': 438631, 'title': 'Dune', 'releaseDate': '2021-09-15'};
    final ctx = _ctx(seerr: seerr, server: library);
    final data = await _run(ctx, 'trending_titles', {'kind': 'movie'});

    final rows = _titles(data);
    expect([for (final r in rows) r['title']], ['Toy Story', 'Dune']);
    expect(rows[0]['in_library'], isTrue);
    expect(rows[0]['item_id'], 'ts');
    expect(rows[1]['in_library'], isFalse);
    expect(rows[1]['seerr_id'], 'movie:438631');
    // The shown id is accepted: the request flow reads that title fresh from
    // Seerr. What follows (library and rights evidence) is the request tests'.
    final request = await assistantRequestFromOption(ctx, 'movie:438631');
    if (request case AssistantToolResult(:final data)) expect(data['error'], isNot('unknown_seerr_id'));
    expect(seerr.paths, contains('/movie/438631'));
  });

  test('trending without Seerr: TMDB on the own key, one kind only when asked', () async {
    final paths = <String>[];
    final net = MockClient((request) async {
      paths.add(request.url.path);
      return jsonResponse(
        _tmdbList([
          {'id': 603, 'title': 'The Matrix', 'release_date': '1999-03-31'},
        ]),
      );
    });
    final ctx = _ctx(tmdbKey: 'key', net: net);
    final data = await _run(ctx, 'trending_titles', {'kind': 'movie'});
    expect(paths.where((p) => p.contains('trending')), ['/3/trending/movie/week']);
    expect([for (final r in _titles(data)) r['title']], ['The Matrix']);
    expect(_titles(data).single['year'], 1999);
  });

  test('trending without Seerr and without a TMDB key is no_source', () async {
    for (final name in ['trending_titles', 'similar_titles']) {
      await expectLater(
        _run(_ctx(), name, {'title': 'Dark'}),
        throwsA(isA<AssistantToolError>().having((e) => e.code, 'code', 'no_source')),
      );
    }
  });

  test(
    'similar: the library names the id, Seerr recommends and finds similar, deduped without the title itself',
    () async {
      final seerr = FakeSeerr()
        ..search['Dark'] = [
          {'id': 70523, 'mediaType': 'tv', 'name': 'Dark', 'firstAirDate': '2017-12-01', 'originalLanguage': 'de'},
        ]
        ..details['/tv/70523/recommendations'] = _page([
          {'id': 1, 'mediaType': 'tv', 'name': 'Biohackers', 'firstAirDate': '2020-08-20'},
          {'id': 70523, 'mediaType': 'tv', 'name': 'Dark', 'firstAirDate': '2017-12-01'},
        ])
        ..details['/tv/70523/similar'] = _page([
          {'id': 1, 'mediaType': 'tv', 'name': 'Biohackers', 'firstAirDate': '2020-08-20'},
          {'id': 2, 'mediaType': 'tv', 'name': 'The OA', 'firstAirDate': '2016-12-16'},
        ]);
      final ctx = _ctx(seerr: seerr, server: library);
      final data = await _run(ctx, 'similar_titles', {'title': 'Dark', 'kind': 'show'});

      expect([for (final r in _titles(data)) r['title']], ['Biohackers', 'The OA']);
      expect(_titles(data).first['seerr_id'], 'tv:1');
      expect(seerr.paths, containsAll(['/tv/70523/recommendations', '/tv/70523/similar']));
    },
  );

  test('similar without Seerr: TMDB searches the title and lists recommendations plus similar', () async {
    final net = MockClient((request) async {
      final p = request.url.path;
      if (p == '/3/search/multi') {
        return jsonResponse(
          _tmdbList([
            {'id': 603, 'media_type': 'movie', 'title': 'The Matrix', 'release_date': '1999-03-31'},
          ]),
        );
      }
      if (p == '/3/movie/603/recommendations') {
        return jsonResponse(
          _tmdbList([
            {'id': 604, 'title': 'The Matrix Reloaded', 'release_date': '2003-05-15'},
          ]),
        );
      }
      if (p == '/3/movie/603/similar') {
        return jsonResponse(
          _tmdbList([
            {'id': 604, 'title': 'The Matrix Reloaded', 'release_date': '2003-05-15'},
            {'id': 55, 'title': 'Dark City', 'release_date': '1998-02-27'},
          ]),
        );
      }
      return jsonResponse({});
    });
    final data = await _run(_ctx(tmdbKey: 'key', net: net), 'similar_titles', {'title': 'The Matrix'});
    expect([for (final r in _titles(data)) r['title']], ['The Matrix Reloaded', 'Dark City']);
  });

  test('for_kids with age 8 drops PG-13 titles, requestable ones included', () async {
    final seerr = FakeSeerr()
      ..details['/discover/trending'] = _page([
        _film(12445, 'Harry Potter', '2011-07-07'),
        _film(862, 'Toy Story', '1995-11-22'),
      ]);
    final ctx = _ctx(seerr: seerr, age: 8);
    final data = await _run(ctx, 'trending_titles', {'for_kids': true});
    expect([for (final r in _titles(data)) r['title']], ['Toy Story']);
    expect(data['filtered_for_age'], 1);
    final refused = await assistantRequestFromOption(ctx, 'movie:12445');
    expect((refused as AssistantToolResult).data, {'error': 'unknown_seerr_id'});
  });

  test('for_kids without saved ages is kids_ages_unknown', () async {
    await expectLater(
      _run(_ctx(seerr: FakeSeerr()), 'trending_titles', {'for_kids': true}),
      throwsA(isA<AssistantToolError>().having((e) => e.code, 'code', 'kids_ages_unknown')),
    );
  });
}
