part of 'named_fixtures.dart';

/// The rows of a detail page the protocol has no field for, in the shape
/// `lib/services/pleya_server_client/parts/verify_detail.dart` reads.
const List<Map<String, dynamic>> _detailScores = [
  {'source': 'imdb', 'value': 7.4},
  {'source': 'rottenTomatoesCritic', 'value': 86},
  {'source': 'rottenTomatoesAudience', 'value': 79},
  {'source': 'tmdb', 'value': 74},
];

List<Map<String, dynamic>> _detailReviews(String title) => [
  for (final (source, author, text) in [
    ('FilmWeek', 'Amy Nicholson', '$title plays every scene with so much delight. I find it very funny and charming.'),
    (
      'Chicago Reader',
      'Andrea Thompson',
      'If things resolve a bit too quickly, the sheer charm of the journey hides it.',
    ),
    ('Tribune News Service', 'Katie Walsh', 'One gorgeous and dynamic fractured fairy tale.'),
    ('Star Tribune', 'Chris Hewitt', 'It is easy to recommend, and the craft on screen is not to be missed.'),
  ])
    {'author': author, 'text': text, 'source': source, 'imageUri': 'rottentomatoes://image.review.fresh'},
];

/// Eight people, seven with a portrait. The poster of a studio film stands in
/// for the photo; the last one has none, so the initials stay on the path.
List<Map<String, dynamic>> _detailCast(PleyaFakeServer server, List<(String, String)> people) {
  final films = [for (final film in studioArtFilms) server.seededIds['movie/${film.slug}']!];
  return [
    for (final (i, (name, character)) in people.indexed)
      {
        'id': 'person-$i',
        'tag': name,
        'role': character,
        if (i < people.length - 1) 'thumb_id': films[i % films.length],
      },
  ];
}

/// `catalog.studio-art.v1` with one film filled in the way a server fills a
/// detail page: Sintel, half watched, with a synopsis, a director and a cast on
/// the wire, and the rest of northstars 06 to 10 through
/// [PleyaFakeServer.verifyDetail].
///
/// The wire has no HDR or Dolby Vision verdict (`pleya_server_mappers.dart`
/// leaves that to PS-6), so the video label stops at resolution and codec.
void _applyCatalogDetailMovieV1(PleyaFakeServer server) {
  _applyCatalogStudioArtV1(server);
  final films = {for (final film in studioArtFilms) film.slug: server.seededIds['movie/${film.slug}']!};
  final id = films['sintel']!;
  server.items[id]!
    ..['summary'] =
        'A lone young woman searches a hostile world for the dragon she raised, '
        'and the search costs her more than the years she spends on it.'
    ..['genres'] = const ['Animation', 'Fantasy']
    ..['content_rating'] = '12'
    ..['duration_ms'] = 5400000
    ..['user_state'] = {'position_ms': 2700000, 'watched': false, 'play_count': 0, 'updated_at': '2026-08-21T20:00:00Z'}
    ..['people'] = const [
      {'name': 'Colin Levy', 'role': 'director'},
      {'name': 'Halina Reijn', 'role': 'actor', 'character': 'Sintel'},
      {'name': 'Thom Hoffman', 'role': 'actor', 'character': 'Shaman'},
      {'name': 'Ton Roosendaal', 'role': 'actor', 'character': 'Elder'},
      {'name': 'Ivo Janssen', 'role': 'actor', 'character': 'Guard'},
      {'name': 'Marieke Heebink', 'role': 'actor', 'character': 'Mother'},
      {'name': 'Pierre Bokma', 'role': 'actor', 'character': 'Trader'},
      {'name': 'Jeroen Krabbe', 'role': 'actor', 'character': 'Narrator'},
    ];
  (server.items[id]!['versions'] as List).first
    ..['video_streams'] = const [
      {'id': 'v0', 'index': 0, 'codec': 'hevc', 'profile': 'Main 10', 'width': 3840, 'height': 2160, 'bit_depth': 10},
    ]
    ..['audio_streams'] = const [
      {'id': 'a0', 'index': 1, 'codec': 'eac3', 'channels': 6, 'language': 'eng', 'is_default': true},
    ];

  server.verifyDetail[id] = {
    'external_ratings': _detailScores,
    'reviews': _detailReviews('Sintel'),
    'roles': _detailCast(server, const [
      ('Halina Reijn', 'Sintel'),
      ('Thom Hoffman', 'Shaman'),
      ('Ton Roosendaal', 'Elder'),
      ('Ivo Janssen', 'Guard'),
      ('Marieke Heebink', 'Mother'),
      ('Pierre Bokma', 'Trader'),
      ('Jeroen Krabbe', 'Narrator'),
      ('Colin Levy', 'Director'),
    ]),
    'extras': [
      {'id': '$id-trailer', 'title': 'Sintel', 'type': 'Trailer', 'thumb_id': '$id-backdrop'},
      {'id': '$id-making-of', 'title': 'Making of', 'type': 'Clip', 'thumb_id': '${films['spring']}-backdrop'},
    ],
    'rows': [
      {
        'id': 'collection',
        'identifier': 'collection.related',
        'title': 'Blender Open Movies Collection',
        'item_ids': [
          for (final slug in ['big-buck-bunny', 'tears-of-steel', 'spring', 'charge', 'coffee-run']) films[slug],
        ],
      },
    ],
    'file_info': {
      'video_resolution': '4k',
      'video_codec': 'hevc',
      'video_profile': 'Main 10',
      'audio': [
        {'id': 0, 'codec': 'eac3', 'language': 'English', 'language_code': 'eng', 'channels': 6, 'profile': 'Atmos'},
      ],
    },
  };
  server.verifyDetail['person-0'] = {
    'item_ids': [films['spring'], films['charge'], films['coffee-run'], films['big-buck-bunny']],
  };
  server.verifyDetail['person-1'] = {
    'item_ids': [films['tears-of-steel'], films['big-buck-bunny'], films['charge']],
  };
}

/// One series the way northstars 03, 04, 05 and 01 show it: two seasons, the
/// first watched and the second under way, cast, a trailer and a collection,
/// over the film catalog so the collection has titles to hold.
void _applyCatalogDetailSeriesV1(PleyaFakeServer server) {
  const fixture = 'catalog.detail-series.v1';
  _applyCatalogStudioArtV1(server);
  final films = {for (final film in studioArtFilms) film.slug: server.seededIds['movie/${film.slug}']!};

  final libraryId = _mintId(server, fixture, 'library', 'shows');
  server.addLibrary(id: libraryId, title: 'Series', kind: 'shows', itemCount: 1);

  final showId = _mintId(server, fixture, 'show', 'charge');
  final logoId = '$showId-logo';
  final backdropId = '$showId-backdrop';
  server.artworkById[showId] = studioArtBytes('charge-poster.jpg');
  server.artworkById[backdropId] = studioArtBytes('charge-backdrop.jpg');
  server.artworkById[logoId] = studioArtBytes('charge-logo.png');
  server.addItem(
    id: showId,
    kind: 'show',
    title: 'Charge',
    libraryId: libraryId,
    year: 2025,
    childCount: 2,
    episodeCount: 8,
    watchedEpisodeCount: 6,
    posterId: showId,
    backdropId: backdropId,
    genres: const ['Crime', 'Drama'],
    contentRating: '16',
  );
  server.items[showId]!
    ..['duration_ms'] = 3000000
    ..['versions'] = const <Map<String, dynamic>>[]
    ..['summary'] =
        'Power is up for grabs as two warring crews clash in a battle that threatens to topple everything they '
        'built. In the crossfire stands one street-smart fixer who knows too well where loyalties lie when '
        'opposing forces come to collect what they are owed, and who has to choose before they choose for him.'
    ..['people'] = const [
      {'name': 'Daisy Hart', 'role': 'actor', 'character': 'The Fixer'},
    ];
  server.verifyDetail[showId] = {
    'clear_logo_id': logoId,
    'external_ratings': _detailScores,
    'roles': _detailCast(server, const [
      ('Daisy Hart', 'The Fixer'),
      ('Pierre Brand', 'Conrad'),
      ('Paula Considine', 'Kevin'),
      ('Joanne Frost', 'Jan'),
      ('Lara Pullman', 'Isabella'),
      ('Anson Bower', 'Eddie'),
      ('Mandy Dhar', 'Seraphina'),
      ('Colin Reed', 'Stuntman'),
    ]),
    'extras': [
      {'id': '$showId-trailer', 'title': 'Charge', 'type': 'Trailer', 'thumb_id': backdropId},
    ],
    'rows': [
      {
        'id': 'collection',
        'identifier': 'collection.related',
        'title': 'Blender Open Movies Collection',
        'item_ids': [
          for (final slug in ['sintel', 'big-buck-bunny', 'tears-of-steel', 'spring', 'coffee-run']) films[slug],
        ],
      },
    ],
  };
  server.verifyDetail['person-0'] = {
    'item_ids': [films['spring'], films['sintel'], films['coffee-run']],
  };

  const seasons = [
    (number: 1, poster: 'spring', summary: 'A crew falls apart over the one job that was meant to be the last.'),
    (
      number: 2,
      poster: 'coffee-run',
      summary:
          'The family struggles to protect its empire under threat from rivals. As tensions within it escalate, '
          'the fixer finds himself caught in the middle of a growing power struggle that no one can walk away from.',
    ),
  ];
  const stills = ['tears-of-steel', 'sintel', 'big-buck-bunny', 'spring'];
  for (final season in seasons) {
    final seasonId = _mintId(server, fixture, 'season', 'charge-s0${season.number}');
    server.artworkById[seasonId] = server.artworkById[films[season.poster]]!;
    server.artworkById['$seasonId-backdrop'] = server.artworkById['${films[season.poster]}-backdrop']!;
    final watched = season.number == 1 ? 4 : 2;
    server.addItem(
      id: seasonId,
      kind: 'season',
      title: 'Season ${season.number}',
      parentId: showId,
      index: season.number,
      childCount: 4,
      episodeCount: 4,
      watchedEpisodeCount: watched,
      posterId: seasonId,
      backdropId: '$seasonId-backdrop',
    );
    server.items[seasonId]!['summary'] = season.summary;
    for (var episode = 1; episode <= 4; episode++) {
      final episodeId = _mintId(server, fixture, 'episode', 'charge-s0${season.number}e$episode');
      final seen = episode <= watched;
      final started = !seen && episode == watched + 1;
      server.artworkById[episodeId] = server.artworkById['${films[stills[episode - 1]]}-backdrop']!;
      server.addItem(
        id: episodeId,
        kind: 'episode',
        title: 'Episode $episode of ${season.number}',
        parentId: seasonId,
        index: episode,
        durationMs: 3000000,
        posterId: episodeId,
        userState: {
          'position_ms': started ? 1200000 : 0,
          'watched': seen,
          'play_count': seen ? 1 : 0,
          'updated_at': '2026-08-21T20:00:00Z',
        },
      );
      server.items[episodeId]!['summary'] =
          'Season ${season.number}, episode $episode: everything the crew planned comes apart in one long night.';
    }
  }

  server.hubs['continue_watching']!.clear();
  server.hubs['recently_added']!.insert(0, showId);
}
