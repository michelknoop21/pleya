import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_find_match.dart';
import 'package:pleya/assistant/assistant_find_route.dart';
import 'package:pleya/assistant/assistant_plot_index.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/assistant/assistant_web_lookup.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/utils/external_ids.dart';

import '../test_helpers/prefs.dart';
import 'assistant_find_fakes.dart';

const _matrixPlot = 'A hacker learns that reality is a simulation run by machines.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    resetSharedPreferencesForTest();
    AssistantWebCache.shared.clear();
  });

  test('the own synopsis answers first: no Wikipedia, Wikidata or web call', () async {
    final web = FakeWeb();
    final server = FakeServer(
      'zolder',
      libraries: {
        'films': [
          fakeItem('1', 'The Matrix', year: 1999, summary: _matrixPlot),
          fakeItem('2', 'Amélie', year: 2001, summary: 'A shy waitress in Paris.'),
        ],
      },
    );
    final ctx = findCtx([server], libraries: [fakeLib('zolder', 'films')], web: web);
    final data = await runFind(ctx, {
      'candidates': [
        {'title': 'The Matrix', 'year': 1999},
      ],
      'variants': ['hacker reality simulation machines', 'hacker werkelijkheid simulatie'],
    });

    final top = matchesOf(data).first;
    expect(top['title'], 'The Matrix');
    expect(top['confidence'], 'high');
    expect(top['in_library'], isTrue);
    expect(top['servers'], ['zolder']);
    expect(top['sources'], containsAll(['model', 'library_plot']));
    expect(web.hosts, isEmpty);
    expect(web.search.queries, isEmpty);
    ctx.requireShownItem(ServerId('zolder'), '1');
  });

  test('a subject finds plots about it, not titles that only carry the word', () async {
    final server = FakeServer(
      'zolder',
      libraries: {
        'films': [
          fakeItem('1', 'Space Jam', year: 1996, summary: 'Michael Jordan plays basketball with the Looney Tunes.'),
          fakeItem('2', 'Safe Space', year: 2021, summary: 'A comedian navigates a campus controversy.'),
          fakeItem('3', 'Gravity', year: 2013, summary: 'Two astronauts are stranded in space after an accident.'),
          fakeItem('4', 'Apollo 13', year: 1995, summary: 'NASA must bring a damaged spacecraft back to Earth.'),
        ],
      },
    );
    final ctx = findCtx([server], libraries: [fakeLib('zolder', 'films')]);
    final titles = [
      for (final m in matchesOf(
        await runFind(ctx, {
          'kind': 'movie',
          'subject': true,
          // What qwen3:8b sent for "een film over de ruimte".
          'variants': ['space', 'ruimte'],
        }),
      ))
        m['title'],
    ];
    expect(titles, ['Gravity']);

    // Named by the model, a title still comes up on its title alone.
    final named = await runFind(ctx, {
      'candidates': [
        {'title': 'Space Jam'},
      ],
      'variants': ['basketball cartoon', 'tekenfilm basketbal'],
    });
    expect(matchesOf(named).first['title'], 'Space Jam');
  });

  test('a Wikipedia hit is normalised through Seerr search, without Wikidata', () async {
    final web = FakeWeb()
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
    final seerr = FakeSeerr()
      ..search = {
        'Inception': [
          {'id': 27205, 'mediaType': 'movie', 'title': 'Inception', 'releaseDate': '2010-07-15'},
        ],
      };
    final ctx = findCtx(const [], seerr: seerr, web: web);
    final data = await runFind(ctx, {
      'variants': ['dream heist inside dreams', 'diefstal in dromen'],
    });

    final top = matchesOf(data).single;
    expect(top['title'], 'Inception');
    expect(top['seerr_id'], 'movie:27205');
    expect(top['seerr_status'], 'not_requested');
    expect(web.hosts, isNot(contains('www.wikidata.org')));
    // Registered in the request allow-list.
    final picked = await assistantRequestFromOption(ctx, 'movie:27205');
    expect(picked is AssistantToolResult ? picked.data['error'] : null, isNot('unknown_seerr_id'));
  });

  test('without Seerr, Wikidata bridges the id to the library', () async {
    final web = FakeWeb()
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
    final server = FakeServer(
      'zolder',
      libraries: {
        'films': [fakeItem('9', 'Origine', year: 2010)],
      },
      ids: {'9': const ExternalIds(tmdb: 27205)},
    );
    final ctx = findCtx([server], libraries: [fakeLib('zolder', 'films')], web: web);
    final data = await runFind(ctx, {
      'variants': ['dream heist inside dreams', 'dromen'],
    });

    expect(web.hosts.where((h) => h == 'www.wikidata.org'), hasLength(1));
    final top = matchesOf(data).first;
    expect(top['in_library'], isTrue);
    expect(top['item_id'], '9');
    expect(server.identities.single.externalIds.tmdb, 27205);
  });

  test('copies on several servers stay one title', () async {
    final a = FakeServer(
      'zolder',
      libraries: {
        'films': [fakeItem('a1', 'Heat', year: 1995, summary: 'A detective hunts a crew of bank robbers.')],
      },
      ids: {'a1': const ExternalIds(tmdb: 949)},
    );
    final b = FakeServer(
      'kelder',
      libraries: {
        'movies': [fakeItem('b1', 'Heat', year: 1995, summary: 'Bank robbers and a detective in Los Angeles.')],
      },
      ids: {'b1': const ExternalIds(tmdb: 949)},
    );
    final ctx = findCtx([a, b], libraries: [fakeLib('zolder', 'films'), fakeLib('kelder', 'movies')]);
    final data = await runFind(ctx, {
      'candidates': [
        {'title': 'Heat', 'year': 1995},
      ],
      'variants': ['detective bank robbers', 'bankrovers'],
    });

    final heat = matchesOf(data).where((m) => m['title'] == 'Heat').toList();
    expect(heat, hasLength(1));
    expect(heat.single['servers'], unorderedEquals(['zolder', 'kelder']));
  });

  test('a hidden library and a hidden server stay out', () async {
    final a = FakeServer(
      'zolder',
      libraries: {
        'films': [fakeItem('1', 'Amélie', summary: 'A shy waitress in Paris.')],
        'kids': [fakeItem('2', 'The Matrix', summary: _matrixPlot)],
      },
    );
    final b = FakeServer(
      'kelder',
      libraries: {
        'movies': [fakeItem('3', 'The Matrix', summary: _matrixPlot)],
      },
    );
    final kids = fakeLib('zolder', 'kids');
    final ctx = findCtx(
      [a, b],
      libraries: [fakeLib('zolder', 'films'), kids, fakeLib('kelder', 'movies')],
      hidden: {kids.globalKey},
      visible: {'zolder'},
    );
    final data = await runFind(ctx, {
      'candidates': [
        {'title': 'The Matrix'},
      ],
      'variants': ['hacker reality simulation', 'simulatie'],
    });

    expect(matchesOf(data).where((m) => m['in_library'] == true), isEmpty);
  });

  test('an episode is found among its series\' children', () async {
    final server = FakeServer(
      'zolder',
      libraries: {
        'series': [fakeItem('dw', 'Doctor Who', kind: MediaKind.show, summary: 'A time traveller.')],
      },
      children: {
        'dw': [fakeItem('s3', 'Season 3', kind: MediaKind.season).copyWith(index: 3)],
        's3': [
          fakeItem(
            'e1',
            'Smith and Jones',
            kind: MediaKind.episode,
            summary: 'A hospital moves to the moon.',
          ).copyWith(index: 1, parentIndex: 3),
          fakeItem(
            'e10',
            'Blink',
            kind: MediaKind.episode,
            summary: 'Weeping angels: statues that move when you blink.',
          ).copyWith(index: 10, parentIndex: 3),
        ],
      },
    );
    final ctx = findCtx([server], libraries: [fakeLib('zolder', 'series', kind: MediaKind.show)]);
    final data = await runFind(ctx, {
      'kind': 'episode',
      'series': 'Doctor Who',
      'variants': ['statues angels move blink', 'beelden engelen'],
    });

    final top = matchesOf(data).first;
    expect(top['kind'], 'episode');
    expect(top['title'], 'Blink');
    expect(top['series'], 'Doctor Who');
    expect([top['season'], top['episode']], [3, 10]);
    expect(top['item_id'], 'e10');
    ctx.requireShownItem(ServerId('zolder'), 'e10');
  });

  test('the web is searched once, and only when the cheap sources fall short', () async {
    final web = FakeWeb();
    web.search.hits = [
      (title: 'Primer (2004) - IMDb', url: 'https://imdb.example', snippet: 'Engineers build a time machine.'),
      (title: 'Primer (film) - Wikipedia', url: 'https://wiki.example', snippet: 'Primer is a 2004 film.'),
    ];
    final ctx = findCtx(const [], web: web);
    final data = await runFind(ctx, {
      'variants': ['garage engineers accidental time machine', 'tijdmachine'],
    });

    expect(web.search.queries, ['garage engineers accidental time machine']);
    expect(data['web_searched'], isTrue);
    expect(matchesOf(data).first['title'], 'Primer', reason: 'without Seerr the web page is still shown');
  });

  test('with Seerr the film from the web becomes a requestable card', () async {
    final web = FakeWeb();
    web.search.hits = [
      (title: 'Primer (2004) - IMDb', url: 'https://imdb.example', snippet: 'Engineers build a time machine.'),
    ];
    final ctx = findCtx(const [], web: web, seerr: primerSeerr());
    final data = await runFind(ctx, {
      'variants': ['garage engineers accidental time machine', 'tijdmachine'],
    });

    expect(matchesOf(data).first['title'], 'Primer');
    expect(matchesOf(data).first['seerr_id'], 'movie:14337');
  });

  test('ids from the model are never used', () async {
    final seerr = FakeSeerr();
    final ctx = findCtx(const [], seerr: seerr);
    await runFind(ctx, {
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
    final web = FakeWeb()..stall = Completer();
    final server = FakeServer(
      'zolder',
      libraries: {
        'films': [
          fakeItem('1', 'Amélie', summary: 'A shy waitress in Paris.'),
          fakeItem('2', 'Chocolat', summary: 'A shy waitress in a French village, far from Paris.'),
        ],
      },
    );
    final ctx = findCtx([server], libraries: [fakeLib('zolder', 'films')], web: web);
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
    // The stalled Wikipedia calls are cut on the wire, not left running.
    await pumpEventQueue();
    expect(web.aborted, isNotEmpty);
    expect(web.aborted, everyElement(endsWith('wikipedia.org')));
  });

  test('with the web off nothing external is asked', () async {
    final seerr = FakeSeerr()
      ..search = {
        'Heat': [
          {'id': 949, 'mediaType': 'movie', 'title': 'Heat', 'releaseDate': '1995-12-15'},
        ],
      };
    final ctx = findCtx(const [], seerr: seerr);
    final data = await runFind(ctx, {
      'candidates': [
        {'title': 'Heat'},
      ],
      'variants': ['bank robbers', 'bankrovers'],
    });

    final top = matchesOf(data).single;
    expect(top['seerr_id'], 'movie:949');
    expect(top['sources'], isNot(anyOf(contains('wikipedia'), contains('web'))));
    expect(ctx.web, isNull);
  });

  test('web titles drop the site name and keep the year', () {
    expect(webTitle('Primer (2004) - IMDb'), (title: 'Primer', year: 2004));
    expect(webTitle('Heat (film) | Wikipedia'), (title: 'Heat', year: null));
  });
}
