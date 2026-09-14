import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../pleya_fake_server.dart';
import '../seerr_fake_server.dart';
import 'deterministic_png.dart';

/// The named fixtures Pleya Verify scenarios seed by name (`seed {fixture}`
/// in the control plane — see `FixtureHttpServer`). Unknown names are the
/// caller's problem, not this function's: it returns `false` rather than
/// throwing, so the control-plane route can answer 400.
///
/// A `catalog.*` branch replaces the *catalog* only
/// ([PleyaFakeServer.resetCatalog]), never the whole server: seeding after
/// `sign_in` is a legal scenario order and must not invalidate the session
/// that step just created. A `seerr.*` branch seeds [seerr] instead, and
/// never touches [server] — a scenario that needs both issues two `seed:`
/// steps, one per fixture name, and [seerr] is `null` for a run that never
/// needs it.
bool applyNamedFixture(PleyaFakeServer server, String name, {SeerrFakeServer? seerr}) {
  switch (name) {
    case 'catalog.shows.v1':
      _applyCatalogShowsV1(server);
      return true;
    case 'catalog.mixed.v1':
      _applyCatalogMixedV1(server);
      return true;
    case 'catalog.hero-artwork.v1':
      _applyCatalogHeroArtworkV1(server);
      return true;
    case 'catalog.long-rails.v1':
      _applyCatalogLongRailsV1(server);
      return true;
    case 'catalog.empty.v1':
      server.resetCatalog();
      return true;
    case 'seerr.requests.v1':
      if (seerr == null) return false;
      _applySeerrRequestsV1(seerr);
      return true;
    default:
      return false;
  }
}

/// A deterministic id for one fixture's content: same `(fixture, kind,
/// slug)` in, same id out, every run. Not meant to be human-readable —
/// that's what `title` is for — only stable and collision-resistant across
/// the fixtures' own (fixture, kind, slug) namespace.
String fixtureItemId(String fixture, String kind, String slug) =>
    sha256.convert(utf8.encode('$fixture/$kind/$slug')).toString().substring(0, 16);

/// [fixtureItemId], plus a note in [PleyaFakeServer.seededIds] under
/// `"<kind>/<slug>"`.
///
/// Every id a fixture mints goes through here, so a scenario can name the
/// season it wants to add an episode to by its readable slug instead of a
/// hash it has no way to know. `/__verify/state` publishes the map.
String _mintId(PleyaFakeServer server, String fixture, String kind, String slug) {
  final id = fixtureItemId(fixture, kind, slug);
  server.seededIds['$kind/$slug'] = id;
  return id;
}

/// Registers a small, deterministic-but-distinguishable poster for [itemId]
/// (color derived from `sha256(itemId)`) and returns the poster id to pass
/// as `addItem`'s `posterId` — the item's own id doubles as its artwork id,
/// there is no reason for the fixture to invent a second one.
String _registerArtwork(PleyaFakeServer server, String itemId) {
  final digest = sha256.convert(utf8.encode(itemId)).bytes;
  server.artworkById[itemId] = solidColorPng(width: 32, height: 32, r: digest[0], g: digest[1], b: digest[2]);
  return itemId;
}

/// "Testserie" — one library, one show, one season, ten episodes
/// (S01E01..S01E10). The base fixture for `media-detail.episode-refresh`
/// (see the Pleya Verify plan's [C4]): opens with `child_count: 10`, and
/// `POST /__verify/add_episode` grows it to 11 without needing a second
/// fixture.
void _applyCatalogShowsV1(PleyaFakeServer server) {
  const fixture = 'catalog.shows.v1';
  server.resetCatalog();

  final libraryId = _mintId(server, fixture, 'library', 'shows');
  server.addLibrary(id: libraryId, title: 'Shows', kind: 'shows', itemCount: 1);

  final showId = _mintId(server, fixture, 'show', 'testserie');
  server.addItem(
    id: showId,
    kind: 'show',
    title: 'Testserie',
    libraryId: libraryId,
    year: 2026,
    childCount: 1,
    episodeCount: 10,
    posterId: _registerArtwork(server, showId),
  );

  final seasonId = _mintId(server, fixture, 'season', 'testserie-s01');
  server.addItem(
    id: seasonId,
    kind: 'season',
    title: 'Season 1',
    parentId: showId,
    index: 1,
    childCount: 10,
    episodeCount: 10,
    posterId: _registerArtwork(server, seasonId),
  );

  final episodeSlugs = List.generate(10, (i) => 'testserie-s01e${(i + 1).toString().padLeft(2, '0')}')..sort();
  for (final slug in episodeSlugs) {
    final match = RegExp(r'e(\d+)$').firstMatch(slug)!;
    final episodeIndex = int.parse(match.group(1)!);
    final episodeId = _mintId(server, fixture, 'episode', slug);
    server.addItem(
      id: episodeId,
      kind: 'episode',
      title: 'S01E${episodeIndex.toString().padLeft(2, '0')}',
      parentId: seasonId,
      index: episodeIndex,
      durationMs: 1500000 + episodeIndex * 1000,
      posterId: _registerArtwork(server, episodeId),
    );
  }
}

/// A mix of both library kinds — three movies, one show with one season and
/// three episodes — plus non-empty `recently_added`/`continue_watching`
/// hubs, for scenarios (`discover.layout`) that need more than one
/// content shape on screen at once.
void _applyCatalogMixedV1(PleyaFakeServer server) {
  const fixture = 'catalog.mixed.v1';
  server.resetCatalog();

  final moviesLibraryId = _mintId(server, fixture, 'library', 'movies');
  server.addLibrary(id: moviesLibraryId, title: 'Movies', kind: 'movies', itemCount: 3);

  final movieSlugs = ['aurora', 'basalt', 'cascade']..sort();
  final movieIds = <String>[];
  for (final slug in movieSlugs) {
    final movieId = _mintId(server, fixture, 'movie', slug);
    movieIds.add(movieId);
    server.addItem(
      id: movieId,
      kind: 'movie',
      title: slug[0].toUpperCase() + slug.substring(1),
      libraryId: moviesLibraryId,
      year: 2020 + movieIds.length,
      durationMs: 5400000 + movieIds.length * 60000,
      posterId: _registerArtwork(server, movieId),
    );
  }

  final showsLibraryId = _mintId(server, fixture, 'library', 'shows');
  server.addLibrary(id: showsLibraryId, title: 'Shows', kind: 'shows', itemCount: 1);

  final showId = _mintId(server, fixture, 'show', 'driftwood');
  server.addItem(
    id: showId,
    kind: 'show',
    title: 'Driftwood',
    libraryId: showsLibraryId,
    year: 2024,
    childCount: 1,
    episodeCount: 3,
    posterId: _registerArtwork(server, showId),
  );
  final seasonId = _mintId(server, fixture, 'season', 'driftwood-s01');
  server.addItem(
    id: seasonId,
    kind: 'season',
    title: 'Season 1',
    parentId: showId,
    index: 1,
    childCount: 3,
    episodeCount: 3,
    posterId: _registerArtwork(server, seasonId),
  );
  final episodeIds = <String>[];
  final episodeSlugs = List.generate(3, (i) => 'driftwood-s01e${i + 1}')..sort();
  for (final slug in episodeSlugs) {
    final match = RegExp(r'e(\d+)$').firstMatch(slug)!;
    final episodeIndex = int.parse(match.group(1)!);
    final episodeId = _mintId(server, fixture, 'episode', slug);
    episodeIds.add(episodeId);
    server.addItem(
      id: episodeId,
      kind: 'episode',
      title: 'S01E$episodeIndex',
      parentId: seasonId,
      index: episodeIndex,
      durationMs: 1400000 + episodeIndex * 1000,
      posterId: _registerArtwork(server, episodeId),
    );
  }

  server.hubs['recently_added']!.addAll([...movieIds, showId]);
  server.hubs['continue_watching']!.add(movieIds.first);
}

/// Five films whose backdrops differ only in the two things the Home hero has
/// to cope with: the source aspect ratio, and where the subject sits inside it.
///
/// Built for the hero artwork audit. `catalog.mixed.v1` cannot do this job at
/// all: every artwork it registers is a 32x32 flat square, which renders the
/// same however hard the hero crops it, so no crop is visible and none is
/// measurable. These use [calibrationPng] instead, so each screenshot carries
/// its own ruler.
///
/// The five cases, in carousel order:
///
/// | slug      | source | AR   | subject   |
/// |-----------|--------|------|-----------|
/// | wide      | 3840x1600 | 2.40 | centre |
/// | standard  | 1920x1080 | 1.78 | centre |
/// | narrow    | 1600x1080 | 1.48 | centre |
/// | left      | 1920x1080 | 1.78 | left, low |
/// | right     | 1920x1080 | 1.78 | right, high |
///
/// `standard` is the common Plex case and `wide` the cinematic one; `narrow`
/// stands in for artwork that is closer to 3:2 than to 16:9. The last two hold
/// the aspect ratio still and move only the subject, so a framing verdict
/// cannot be confused with a ratio verdict.
void _applyCatalogHeroArtworkV1(PleyaFakeServer server) {
  const fixture = 'catalog.hero-artwork.v1';
  server.resetCatalog();

  final libraryId = _mintId(server, fixture, 'library', 'movies');
  server.addLibrary(id: libraryId, title: 'Movies', kind: 'movies', itemCount: 5);

  const cases = <({String slug, String title, int w, int h, double sx, double sy, int r, int g, int b})>[
    (slug: 'wide', title: 'Wide 2.40', w: 3840, h: 1600, sx: 0.5, sy: 0.5, r: 40, g: 60, b: 90),
    (slug: 'standard', title: 'Standard 1.78', w: 1920, h: 1080, sx: 0.5, sy: 0.5, r: 90, g: 50, b: 40),
    (slug: 'narrow', title: 'Narrow 1.48', w: 1600, h: 1080, sx: 0.5, sy: 0.5, r: 40, g: 80, b: 50),
    (slug: 'subject-left', title: 'Subject Left Low', w: 1920, h: 1080, sx: 0.22, sy: 0.72, r: 80, g: 70, b: 30),
    (slug: 'subject-right', title: 'Subject Right High', w: 1920, h: 1080, sx: 0.78, sy: 0.28, r: 70, g: 40, b: 80),
  ];

  final ids = <String>[];
  for (final c in cases) {
    final id = _mintId(server, fixture, 'movie', c.slug);
    ids.add(id);
    // Poster and backdrop are separate artworks on a real item, and the hero
    // only draws the backdrop sharp, so the fixture has to carry both or the
    // audit measures the poster-fill fallback instead of the thing it is for.
    final backdropId = '$id-backdrop';
    // Registered as resizable as well, so the served pixels follow the
    // requested width and an upscale factor becomes a measurement rather than
    // an inference from the URL.
    server.resizableArtwork[backdropId] = (width) => calibrationPng(
      width: width,
      height: (width * c.h / c.w).round().clamp(16, 4096),
      r: c.r,
      g: c.g,
      b: c.b,
      subjectX: c.sx,
      subjectY: c.sy,
    );
    server.artworkById[backdropId] = calibrationPng(
      width: c.w,
      height: c.h,
      r: c.r,
      g: c.g,
      b: c.b,
      subjectX: c.sx,
      subjectY: c.sy,
    );
    // A plain 2:3 poster, so the rails stay honest and the hero's choice
    // between backdrop and poster stays a real choice.
    server.artworkById[id] = calibrationPng(width: 600, height: 900, r: c.r, g: c.g, b: c.b);
    server.addItem(
      id: id,
      kind: 'movie',
      title: c.title,
      libraryId: libraryId,
      year: 2020 + ids.length,
      durationMs: 5400000 + ids.length * 60000,
      posterId: id,
      backdropId: backdropId,
    );
  }

  server.hubs['recently_added']!.addAll(ids);
  server.hubs['continue_watching']!.add(ids.first);
}

/// Twelve movies in `recently_added`, the hub the movies landing's first rail
/// (`discover.rail[0]`) draws on (`PleyaFakeServer.hubs`'s insertion order
/// puts it first, and it is the only hub every one of these fixtures fills).
/// Every other named fixture tops out at three or four items per hub, which
/// is enough tiles to fill a row but not enough for a row to ever need to
/// scroll — see VER4 in `docs/tvos-fysieke-correctieronde.md`.
void _applyCatalogLongRailsV1(PleyaFakeServer server) {
  const fixture = 'catalog.long-rails.v1';
  server.resetCatalog();

  final libraryId = _mintId(server, fixture, 'library', 'movies');
  server.addLibrary(id: libraryId, title: 'Movies', kind: 'movies', itemCount: 12);

  final movieSlugs = List.generate(12, (i) => 'longrail-${(i + 1).toString().padLeft(2, '0')}')..sort();
  final ids = <String>[];
  for (final slug in movieSlugs) {
    final movieId = _mintId(server, fixture, 'movie', slug);
    ids.add(movieId);
    server.addItem(
      id: movieId,
      kind: 'movie',
      title: slug,
      libraryId: libraryId,
      year: 2010 + ids.length,
      durationMs: 5400000 + ids.length * 60000,
      posterId: _registerArtwork(server, movieId),
    );
  }

  server.hubs['recently_added']!.addAll(ids);
}

/// Five requests across four Overseerr statuses (pending, approved,
/// processing, available) for "Alle aanvragen", plus a handful of titles in
/// each of the five discover buckets `SeerrDiscoverScreen` fetches (trending,
/// movies, tv, upcoming movies, upcoming tv) for "Ontdekken". Every request's
/// `media` object carries its own title/year/poster, so the client's
/// best-effort hydration round-trip never has to fire for this fixture to
/// display correctly.
void _applySeerrRequestsV1(SeerrFakeServer seerr) {
  seerr.reset();

  const requests = <({int id, String type, int tmdbId, String title, int year, int status})>[
    (id: 1, type: 'movie', tmdbId: 101, title: 'Aurora Drift', year: 2024, status: 1),
    (id: 2, type: 'tv', tmdbId: 102, title: 'Basalt Coast', year: 2023, status: 2),
    (id: 3, type: 'movie', tmdbId: 103, title: 'Cascade Point', year: 2022, status: 4),
    (id: 4, type: 'tv', tmdbId: 104, title: 'Driftwood Bay', year: 2021, status: 5),
    (id: 5, type: 'movie', tmdbId: 105, title: 'Ember Field', year: 2025, status: 1),
  ];
  for (final r in requests) {
    seerr.addRequest(id: r.id, mediaType: r.type, tmdbId: r.tmdbId, title: r.title, year: r.year, status: r.status);
  }

  const buckets = <(String bucket, String type)>[
    ('trending', 'movie'),
    ('movies', 'movie'),
    ('tv', 'tv'),
    ('movies-upcoming', 'movie'),
    ('tv-upcoming', 'tv'),
  ];
  var tmdbId = 2000;
  for (final (bucket, type) in buckets) {
    for (var i = 1; i <= 6; i++) {
      tmdbId++;
      seerr.addDiscoverItem(
        bucket,
        tmdbId: tmdbId,
        mediaType: type,
        title: '${bucket[0].toUpperCase()}${bucket.substring(1)} title $i',
        year: 2020 + i,
      );
    }
  }
}
