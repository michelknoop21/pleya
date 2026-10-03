import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_find_match.dart';
import 'package:pleya/assistant/assistant_find_route.dart';
import 'package:pleya/assistant/assistant_plot_index.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/assistant/assistant_web_lookup.dart';
import 'package:pleya/media/media_identity.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/utils/external_ids.dart';

import '../test_helpers/prefs.dart';
import 'assistant_find_fakes.dart';

FakeServer _doctorWho({String blinkSummary = 'The Doctor is trapped in 1969.'}) => FakeServer(
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
        summary: 'A hospital.',
      ).copyWith(index: 1, parentIndex: 3),
      fakeItem('e10', 'Blink', kind: MediaKind.episode, summary: blinkSummary).copyWith(index: 10, parentIndex: 3),
    ],
  },
);

const _episodeArgs = {
  'kind': 'episode',
  'series': 'Doctor Who',
  'variants': ['statues that move when you look away', 'beelden'],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    resetSharedPreferencesForTest();
    AssistantWebCache.shared.clear();
  });

  group('identity through the unified layer', () {
    test('a Seerr title attaches to the library copy by its TMDB id, under another name', () async {
      final seerr = FakeSeerr()
        ..search = {
          'Inception': [
            {'id': 27205, 'mediaType': 'movie', 'title': 'Inception', 'releaseDate': '2010-07-15'},
          ],
        };
      final server = FakeServer(
        'zolder',
        libraries: {
          'films': [fakeItem('9', 'Origine', year: 2010, summary: 'A thief steals secrets inside dreams.')],
        },
        ids: {'9': const ExternalIds(tmdb: 27205)},
      );
      final ctx = findCtx([server], libraries: [fakeLib('zolder', 'films')], seerr: seerr);
      final data = await runFind(ctx, {
        'candidates': [
          {'title': 'Inception', 'year': 2010},
        ],
        'variants': ['thief secrets dreams', 'dromen'],
      });

      final rows = matchesOf(data);
      expect(rows, hasLength(1), reason: 'plot hit, model guess and Seerr are one title');
      expect(rows.single['item_id'], '9');
      expect(rows.single['seerr_id'], 'movie:27205');
      expect(rows.single['sources'], containsAll(['model', 'library_plot', 'seerr']));
    });

    test('the same title with another year stays two titles, as the catalog groups it', () async {
      final a = FakeServer(
        'zolder',
        libraries: {
          'films': [fakeItem('a1', 'Solaris', year: 1972, summary: 'A psychologist on a space station.')],
        },
      );
      final b = FakeServer(
        'kelder',
        libraries: {
          'movies': [fakeItem('b1', 'Solaris', year: 2002, summary: 'A psychologist on a space station.')],
        },
      );
      final ctx = findCtx([a, b], libraries: [fakeLib('zolder', 'films'), fakeLib('kelder', 'movies')]);
      final data = await runFind(ctx, {
        'variants': ['psychologist space station', 'ruimtestation'],
      });

      final solaris = matchesOf(data).where((m) => m['title'] == 'Solaris').toList();
      expect(solaris, hasLength(2));
      expect({for (final m in solaris) m['year']}, {1972, 2002});
    });

    test('namesSameTitle: an id is proof, a contradicting id keeps titles apart', () {
      final seerr = FindMatch('Inception', kind: MediaKind.movie)..ids = const ExternalIds(tmdb: 27205);
      final library = FindMatch('Origine', kind: MediaKind.movie)..ids = const ExternalIds(tmdb: 27205);
      final remake = FindMatch('Inception', kind: MediaKind.movie)..ids = const ExternalIds(tmdb: 1);
      expect(seerr.namesSameTitle(library), isTrue);
      expect(seerr.namesSameTitle(remake), isFalse);
      expect(FindMatch('Inception').namesSameTitle(FindMatch('inception', year: 2010)), isTrue);
    });
  });

  group('episodes from outside evidence', () {
    test('a Wikipedia episode page names the episode; it resolves to the library copy', () async {
      final web = FakeWeb()
        ..wiki = {
          'Doctor Who episode statues that move when you look away': [
            {'title': 'Blink (Doctor Who)', 'index': 1, 'description': '2007 Doctor Who episode'},
          ],
        };
      final ctx = findCtx(
        [_doctorWho()],
        libraries: [fakeLib('zolder', 'series', kind: MediaKind.show)],
        web: web,
      );
      final top = matchesOf(await runFind(ctx, _episodeArgs)).first;

      expect(
        [top['kind'], top['title'], top['season'], top['episode'], top['item_id']],
        ['episode', 'Blink', 3, 10, 'e10'],
      );
      expect(top['sources'], contains('wikipedia'));
      expect(web.search.queries, isEmpty);
    });

    test('without Wikipedia, the one web search gives the numbers', () async {
      final web = FakeWeb();
      web.search.hits = [(title: 'Doctor Who S03E10 recap', url: 'https://tv.example', snippet: 'The weeping angels.')];
      final ctx = findCtx(
        [_doctorWho()],
        libraries: [fakeLib('zolder', 'series', kind: MediaKind.show)],
        web: web,
      );
      final data = await runFind(ctx, _episodeArgs);
      final top = matchesOf(data).first;

      expect(web.search.queries, ['Doctor Who episode statues that move when you look away']);
      expect(data['web_searched'], isTrue);
      expect([top['title'], top['item_id']], ['Blink', 'e10']);
      expect(top['sources'], contains('web'));
    });
  });

  group('cancellation', () {
    test('Wikipedia is aborted once the own synopsis settles the question', () async {
      final web = FakeWeb()..stall = Completer();
      final server = FakeServer(
        'zolder',
        libraries: {
          'films': [fakeItem('1', 'The Matrix', year: 1999, summary: 'A hacker learns reality is a simulation.')],
        },
      )..latency = const Duration(milliseconds: 20);
      final ctx = findCtx([server], libraries: [fakeLib('zolder', 'films')], web: web);
      final result = await findTitles(
        ctx,
        const FindQuery(
          candidates: [(title: 'The Matrix', year: 1999, kind: null)],
          variants: ['hacker reality simulation', 'simulatie'],
        ),
        headStart: Duration.zero,
        plots: AssistantPlotIndexCache(),
        webCache: AssistantWebCache(),
      );

      expect(result.matches.first.title, 'The Matrix');
      expect(result.matches.first.confidence, 'high');
      expect(result.partial, isFalse, reason: 'an abort on purpose is not a failure');
      expect(web.aborted, isNotEmpty);
      expect(web.aborted, everyElement(endsWith('wikipedia.org')));
    });
  });

  group('web cache', () {
    test('a repeated question is answered from the session cache', () async {
      final web = FakeWeb();
      web.search.hits = [(title: 'Primer (2004) - IMDb', url: '', snippet: 'Engineers build a time machine.')];
      final cache = AssistantWebCache();
      const q = FindQuery(variants: ['garage engineers accidental time machine', 'tijdmachine']);
      final ctx = findCtx(const [], web: web);
      final first = await findTitles(ctx, q, plots: AssistantPlotIndexCache(), webCache: cache);
      final calls = web.hosts.length;
      final second = await findTitles(ctx, q, plots: AssistantPlotIndexCache(), webCache: cache);

      expect(web.hosts, hasLength(calls), reason: 'no second Wikipedia call');
      expect(web.search.queries, hasLength(1));
      expect(second.matches.first.title, first.matches.first.title);
    });

    test('entries last 30 minutes per profile; failures are not kept', () async {
      var now = DateTime(2026, 10, 2, 20);
      final cache = AssistantWebCache(now: () => now);
      var fetches = 0;
      Future<List<String>> fetch() async => ['hit ${++fetches}'];

      expect(await cache.get('p', 'web', 'Time  Machine', fetch), ['hit 1']);
      expect(await cache.get('p', 'web', 'time machine', fetch), ['hit 1'], reason: 'normalised key');
      now = now.add(const Duration(minutes: 29));
      expect(await cache.get('p', 'web', 'time machine', fetch), ['hit 1']);
      now = now.add(const Duration(minutes: 2));
      expect(await cache.get('p', 'web', 'time machine', fetch), ['hit 2'], reason: 'expired');
      expect(await cache.get('q', 'web', 'time machine', fetch), ['hit 3'], reason: 'another profile session');
      await expectLater(
        cache.get<List<String>>('q', 'web', 'boom', () async => throw StateError('x')),
        throwsStateError,
      );
      expect(await cache.get('q', 'web', 'boom', fetch), ['hit 4']);
    });
  });

  test('search_catalog free text leaves hidden libraries and servers out, as Home does', () async {
    final a = FakeServer(
      'zolder',
      libraries: {
        'films': [fakeItem('1', 'Alien', year: 1979)],
        'kids': [fakeItem('2', 'Alien Babies', year: 2020)],
      },
    );
    final b = FakeServer(
      'kelder',
      libraries: {
        'movies': [fakeItem('3', 'Aliens', year: 1986)],
      },
    );
    final kids = fakeLib('zolder', 'kids');
    final ctx = findCtx(
      [a, b],
      libraries: [fakeLib('zolder', 'films'), kids, fakeLib('kelder', 'movies')],
      hidden: {kids.globalKey},
      visible: {'zolder'},
    );
    final tool = assistantTools.firstWhere((t) => t.name == 'search_catalog');
    final data = ((await tool.run(ctx, null, {'text': 'alien'})) as AssistantToolResult).data;

    expect([for (final r in (data['results'] as List).cast<Map>()) r['item_id']], ['1']);
  });
  test('find_media leaves hidden libraries out too', () async {
    final a = FakeServer(
      'zolder',
      libraries: {
        'films': [fakeItem('1', 'Alien', year: 1979)],
        'kids': [fakeItem('2', 'Alien Babies', year: 2020)],
      },
    );
    final kids = fakeLib('zolder', 'kids');
    final ctx = findCtx([a], libraries: [fakeLib('zolder', 'films'), kids], hidden: {kids.globalKey});
    final tool = assistantTools.firstWhere((t) => t.name == 'find_media');
    final data = ((await tool.run(ctx, ServerId('zolder'), {'query': 'alien'})) as AssistantToolResult).data;

    expect([for (final r in (data['items'] as List).cast<Map>()) r['item_id']], ['1']);
  });
  test('a copy whose library id names a sub-folder is kept, as normal search keeps it', () async {
    final a = FakeServer(
      'zolder',
      libraries: {
        'films': [fakeItem('a1', 'Heat', year: 1995, summary: 'A detective hunts a crew of bank robbers.')],
      },
      ids: {'a1': const ExternalIds(tmdb: 949)},
    );
    final b = _ParentFolderServer(
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

    final heat = matchesOf(data).where((m) => m['title'] == 'Heat').single;
    expect(heat['servers'], unorderedEquals(['zolder', 'kelder']));
  });
}

class _ParentFolderServer extends FakeServer {
  _ParentFolderServer(super.id, {super.libraries, super.ids});

  // Jellyfin's mapper falls back to ParentId, which can name a sub-folder
  // instead of the library.
  @override
  Future<List<MediaItem>> findAllByIdentity(MediaIdentity identity) async => [
    for (final i in await super.findAllByIdentity(identity)) i.copyWith(libraryId: 'folder-${i.id}'),
  ];
}
