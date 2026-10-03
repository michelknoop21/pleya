import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_web_lookup.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_role.dart';
import 'package:pleya/utils/external_ids.dart';

import '../test_helpers/prefs.dart';
import 'assistant_find_fakes.dart';

// "Ik ben op zoek naar een film over de ruimte" on a real Plex library gave
// Mission: Impossible (twice), Ricky Stanicky and The Instigators next to
// Guardians of the Galaxy, and web news headlines as film cards.

final _space = {
  'Interstellar':
      'The adventures of a group of explorers who make use of a newly discovered wormhole to surpass the '
      'limitations on human space travel and conquer the vast distances involved on an interstellar voyage.',
  'Gravity':
      'Dr. Ryan Stone, a brilliant medical engineer on her first Shuttle mission, with veteran astronaut Matt '
      'Kowalsky in command of his last flight before retiring. But on a seemingly routine spacewalk, disaster '
      'strikes, leaving them tethered to nothing but each other and spiraling out into the blackness of space.',
  'The Martian':
      'During a manned mission to Mars, Astronaut Mark Watney is presumed dead after a fierce storm and left '
      'behind by his crew. But Watney has survived and finds himself stranded and alone on the hostile planet.',
  'Apollo 13':
      'The true story of technical troubles that scuttle the Apollo 13 lunar mission in 1970, risking the lives '
      'of astronaut Jim Lovell and his crew.',
  'Alien':
      'During its return to the earth, commercial spaceship Nostromo intercepts a distress signal from a '
      'distant planet.',
  'Ad Astra':
      'While a mysterious phenomenon menaces to destroy life on planet Earth, astronaut Roy McBride undertakes a '
      'mission across the immensity of space to uncover the truth about a lost expedition.',
  'First Man':
      'A look at the life of the astronaut, Neil Armstrong, and the legendary space mission that led him to '
      'become the first man to walk on the Moon.',
  'Sunshine':
      'Fifty years into the future, the sun is dying. A team of astronauts is sent to revive the Sun, but the '
      'mission fails. Seven years later, a new team is sent to finish the mission.',
  'Life':
      'The six-member crew of the International Space Station is tasked with studying a sample from Mars that '
      'may be the first proof of extra-terrestrial life on Earth.',
  'Lost in Space':
      'The prospects for continuing life on Earth in the year 2058 are grim. So the Robinsons are launched into '
      'space to colonize Alpha Prime, the only other inhabitable planet in the galaxy.',
};

final _noise = {
  'Mission: Impossible - Dead Reckoning Part One':
      'Ethan Hunt and his IMF team embark on their most dangerous mission yet: they must track down a terrifying '
      'new weapon that threatens all of humanity before it falls into the wrong hands.',
  'Mission: Impossible - Rogue Nation':
      'Ethan and team take on their most impossible mission yet, eradicating the Syndicate, an international '
      'rogue organization as highly skilled as they are, committed to destroying the IMF.',
  'Ricky Stanicky':
      'When three childhood best friends pull a prank gone wrong, they invent the imaginary Ricky Stanicky to get '
      'them out of trouble. Twenty years later, they hire a washed-up actor to bring him to life.',
  'The Instigators':
      'Two unlikely partners are thrown together for a heist. When the job goes wrong, they go on the run with '
      'a crew of henchmen and a corrupt mayor on their heels.',
  'Space Jam': 'Michael Jordan agrees to help the Looney Tunes play a basketball game against alien slavers.',
  'Guardians of the Galaxy':
      'Light years from Earth, 26 years after being abducted, Peter Quill finds himself the prime target of a '
      'manhunt after discovering an orb wanted by Ronan the Accuser.',
};

Map<String, Object?> _seerrMovie(int id, String title, String year, {String? language, int? votes}) => {
  'id': id,
  'mediaType': 'movie',
  'title': title,
  'releaseDate': '$year-01-01',
  'originalLanguage': ?language,
  'voteCount': ?votes,
};

Future<List<String>> _titles(Map<String, String> plots, List<String> variants) async {
  var n = 0;
  final server = FakeServer(
    'zolder',
    libraries: {
      'films': [for (final MapEntry(:key, :value) in plots.entries) fakeItem('${++n}', key, summary: value)],
    },
  );
  final ctx = findCtx([server], libraries: [fakeLib('zolder', 'films')]);
  final data = await runFind(ctx, {'kind': 'movie', 'variants': variants, 'subject': true});
  return [for (final m in matchesOf(data)) m['title'] as String];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    resetSharedPreferencesForTest();
    AssistantWebCache.shared.clear();
  });

  // Variant sets as models send them for "een film over de ruimte".
  const variantSets = {
    // qwen3:8b on local Ollama, seen in round 1.
    'qwen3:8b': ['space', 'ruimte'],
    // A weak tool caller (the GLM 5.3 Flash kind): the subject, then loose
    // generic words, one of which is in every Mission: Impossible plot.
    'weak generic words': ['space', 'ruimte', 'space mission', 'crew journey', 'galaxy'],
    'weak single words': ['space', 'ruimte', 'astronaut', 'mission', 'galaxy'],
    // Descriptive phrases, as round 1's tool description asked for.
    'descriptive phrases': ['astronauts in outer space', 'astronauten in de ruimte', 'spacecraft orbit planet'],
  };

  for (final MapEntry(key: model, value: variants) in variantSets.entries) {
    test('a subject finds space films, not titles that share one loose word ($model)', () async {
      final titles = await _titles({
        for (final t in ['Interstellar', 'Gravity']) t: _space[t]!,
        for (final t in [
          'Guardians of the Galaxy',
          'Mission: Impossible - Dead Reckoning Part One',
          'Mission: Impossible - Rogue Nation',
          'Ricky Stanicky',
          'The Instigators',
        ])
          t: _noise[t]!,
      }, variants);

      expect(titles, containsAll(['Interstellar', 'Gravity']));
      expect(titles.where((t) => t.startsWith('Mission') || t == 'Ricky Stanicky' || t == 'The Instigators'), isEmpty);
    });
  }

  test('a subject returns every space film in the library, not five', () async {
    final titles = await _titles(
      {..._space, ..._noise},
      [
        'space',
        'ruimte',
        'astronauts on a space mission',
        'spaceship travelling to another planet',
        'astronaut in orbit',
        'astronauten in een ruimteschip',
      ],
    );

    expect(titles, unorderedEquals(_space.keys));
  });

  test('in a large library one rare word is enough, one common word is not', () async {
    final titles = await _titles(
      {
        for (var i = 0; i < 200; i++)
          'Drama $i': 'A family drama number $i${i % 40 == 0 ? ' about a rescue mission' : ''}.',
        'Apollo 13': 'NASA must devise a strategy to return Apollo 13 to Earth after the spacecraft undergoes damage.',
        'Mission: Impossible - Rogue Nation': _noise['Mission: Impossible - Rogue Nation']!,
      },
      ['space', 'ruimte', 'spacecraft', 'mission'],
    );

    expect(titles, ['Apollo 13']);
  });

  test('one film on two servers and in Seerr is one card', () async {
    final a = FakeServer(
      'zolder',
      libraries: {
        'films': [fakeItem('a1', 'Gravity', year: 2013, summary: _space['Gravity'])],
      },
      ids: {'a1': const ExternalIds(tmdb: 49047)},
    );
    final b = FakeServer(
      'kelder',
      libraries: {
        'movies': [fakeItem('b1', 'Gravity', year: 2013, summary: _space['Gravity'])],
      },
      ids: {'b1': const ExternalIds(tmdb: 49047)},
    );
    final seerr = FakeSeerr()
      ..search['Gravity'] = [_seerrMovie(49047, 'Gravity', '2013', language: 'en', votes: 15000)];
    final ctx = findCtx([a, b], libraries: [fakeLib('zolder', 'films'), fakeLib('kelder', 'movies')], seerr: seerr);
    final data = await runFind(ctx, {
      'candidates': [
        {'title': 'Gravity', 'year': 2013},
      ],
      'variants': ['space', 'ruimte'],
    });

    final rows = matchesOf(data);
    expect(rows, hasLength(1));
    expect(rows.single['servers'], unorderedEquals(['zolder', 'kelder']));
    expect(rows.single['in_library'], isTrue);
  });

  test('a web page that names no film, or nothing Seerr knows, is no card', () async {
    final web = FakeWeb();
    web.search.hits = [
      (
        title: "Liftoff! NASA's SpaceX Crew-13 Begins Journey to International Space Station",
        url: 'https://www.nasa.gov/news',
        snippet: 'The crew lifted off at 11:10 ET.',
      ),
      (title: 'SpaceX - Crew-13 Mission', url: 'https://www.spacex.com/launches', snippet: 'Crew-13 Mission.'),
      (title: 'Cosmic Drift (2019) - IMDb', url: 'https://www.imdb.com/title/x', snippet: 'A drifting crew.'),
    ];
    final seerr = FakeSeerr();
    final ctx = findCtx(const [], web: web, seerr: seerr);
    final data = await runFind(ctx, {
      'variants': ['astronauts in outer space', 'astronauten in de ruimte'],
    });

    expect(web.search.queries, hasLength(1));
    expect(matchesOf(data), isEmpty);
    expect(seerr.paths, ['search:Cosmic Drift'], reason: 'news and company pages are not looked up as titles');
  });

  test('outside the library only popular American and Dutch titles; the library keeps everything', () async {
    final server = FakeServer(
      'zolder',
      libraries: {
        'films': [
          fakeItem(
            '1',
            'Amélie',
            year: 2001,
            summary: 'A shy waitress in Paris decides to change the lives of others.',
          ),
        ],
      },
      ids: {'1': const ExternalIds(tmdb: 194)},
    );
    final seerr = FakeSeerr()
      ..search = {
        'Interstellar': [_seerrMovie(157336, 'Interstellar', '2014', language: 'en', votes: 36000)],
        'Tiny Orbit': [_seerrMovie(900001, 'Tiny Orbit', '2021', language: 'en', votes: 12)],
        'Le Voyage': [_seerrMovie(900002, 'Le Voyage', '2018', language: 'fr', votes: 4000)],
        'Ruimteschip Holland': [_seerrMovie(900003, 'Ruimteschip Holland', '2020', language: 'nl', votes: 40)],
        'Amélie': [_seerrMovie(194, 'Amélie', '2001', language: 'fr', votes: 11000)],
      };
    final ctx = findCtx([server], libraries: [fakeLib('zolder', 'films')], seerr: seerr);
    final data = await runFind(ctx, {
      'candidates': [
        for (final t in ['Interstellar', 'Tiny Orbit', 'Le Voyage', 'Ruimteschip Holland', 'Amélie']) {'title': t},
      ],
      'variants': ['space', 'ruimte'],
      'subject': true,
    });

    final titles = [for (final m in matchesOf(data)) m['title']];
    expect(titles, unorderedEquals(['Interstellar', 'Ruimteschip Holland', 'Amélie']));
    expect(matchesOf(data).singleWhere((m) => m['title'] == 'Amélie')['in_library'], isTrue);
  });

  test('one foreign film the user identifies keeps its Seerr card, whatever its language or votes', () async {
    final seerr = FakeSeerr()
      ..search = {
        'Parasite': [_seerrMovie(496243, 'Parasite', '2019', language: 'ko', votes: 18000)],
        'Le Voyage': [_seerrMovie(900002, 'Le Voyage', '2018', language: 'fr', votes: 4)],
      };
    final ctx = findCtx(const [], seerr: seerr);
    for (final title in ['Parasite', 'Le Voyage']) {
      final data = await runFind(ctx, {
        'candidates': [
          {'title': title},
        ],
        'variants': ['poor family infiltrates rich household', 'arm gezin in rijk huis'],
      });
      final row = matchesOf(data).single;
      expect(row['title'], title);
      expect(row['seerr_id'], isNotNull);
    }
  });

  test('a person and a setting identify one film, not every film with that first name', () async {
    var n = 0;
    MediaItem film(String title, String actor, String plot) =>
        fakeItem('${++n}', title, summary: plot).copyWith(roles: [MediaRole(tag: actor)]);
    final server = FakeServer(
      'zolder',
      libraries: {
        'films': [
          film('Cast Away', 'Tom Hanks', 'A FedEx engineer is stranded on a deserted island after his plane crashes.'),
          film('Big', 'Tom Hanks', 'A boy wakes up in the body of a grown man.'),
          film('Forrest Gump', 'Tom Hanks', 'A slow-witted man witnesses decades of American history.'),
          film('Top Gun: Maverick', 'Tom Cruise', 'A veteran pilot trains a squad for a dangerous mission.'),
          film('Mad Max: Fury Road', 'Tom Hardy', 'A drifter joins a rebel fleeing a desert tyrant.'),
          film('Venom', 'Tom Hardy', 'A journalist bonds with an alien symbiote.'),
          film('Inception', 'Tom Hardy', 'A thief steals secrets through dream-sharing technology.'),
          film('Tenet', 'Tom Hardy', 'An agent manipulates the flow of time.'),
        ],
      },
    );
    final ctx = findCtx([server], libraries: [fakeLib('zolder', 'films')]);
    final data = await runFind(ctx, {
      'kind': 'movie',
      'variants': ['tom hanks island', 'tom hanks eiland', 'man stranded on a deserted island'],
    });

    final titles = [for (final m in matchesOf(data)) m['title']];
    expect(titles.first, 'Cast Away');
    expect(titles, isNot(contains('Venom')));
    expect(titles.length, lessThanOrEqualTo(5));
  });
}
