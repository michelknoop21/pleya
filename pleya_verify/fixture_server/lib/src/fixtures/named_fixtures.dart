import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../pleya_fake_server.dart';
import 'deterministic_png.dart';

/// The three fixtures Pleya Verify scenarios seed by name (`seed
/// {fixture}` in the control plane — see `FixtureHttpServer`). Unknown
/// names are the caller's problem, not this function's: it returns `false`
/// rather than throwing, so the control-plane route can answer 400.
bool applyNamedFixture(PleyaFakeServer server, String name) {
  switch (name) {
    case 'catalog.shows.v1':
      _applyCatalogShowsV1(server);
      return true;
    case 'catalog.mixed.v1':
      _applyCatalogMixedV1(server);
      return true;
    case 'catalog.empty.v1':
      server.reset();
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
  server.reset();

  final libraryId = fixtureItemId(fixture, 'library', 'shows');
  server.addLibrary(id: libraryId, title: 'Shows', kind: 'shows', itemCount: 1);

  final showId = fixtureItemId(fixture, 'show', 'testserie');
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

  final seasonId = fixtureItemId(fixture, 'season', 'testserie-s01');
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
    final episodeId = fixtureItemId(fixture, 'episode', slug);
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
/// hubs, for scenarios (`discover.hero.layout`) that need more than one
/// content shape on screen at once.
void _applyCatalogMixedV1(PleyaFakeServer server) {
  const fixture = 'catalog.mixed.v1';
  server.reset();

  final moviesLibraryId = fixtureItemId(fixture, 'library', 'movies');
  server.addLibrary(id: moviesLibraryId, title: 'Movies', kind: 'movies', itemCount: 3);

  final movieSlugs = ['aurora', 'basalt', 'cascade']..sort();
  final movieIds = <String>[];
  for (final slug in movieSlugs) {
    final movieId = fixtureItemId(fixture, 'movie', slug);
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

  final showsLibraryId = fixtureItemId(fixture, 'library', 'shows');
  server.addLibrary(id: showsLibraryId, title: 'Shows', kind: 'shows', itemCount: 1);

  final showId = fixtureItemId(fixture, 'show', 'driftwood');
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
  final seasonId = fixtureItemId(fixture, 'season', 'driftwood-s01');
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
    final episodeId = fixtureItemId(fixture, 'episode', slug);
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
