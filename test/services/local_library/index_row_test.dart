import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/external_rating.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_role.dart';
import 'package:pleya/media/media_version.dart';
import 'package:pleya/services/local_library/index_row.dart';
import 'local_library_store_test.dart' show film;

void main() {
  final episodeWithRolesAndVersions = film('ep').copyWith(
    kind: MediaKind.episode,
    title: 'Pilot',
    viewOffsetMs: 4200,
    thumbPath: '/still/ep',
    parentThumbPath: '/poster/season',
    grandparentThumbPath: '/poster/show',
    roles: const [MediaRole(tag: 'Actor')],
    mediaVersions: const [MediaVersion(id: 'v1')],
    externalRatings: const [ExternalRating(source: ExternalRatingSource.imdb, value: 8.1)],
  );

  test('an episode row keeps what a list needs and drops cast and versions', () {
    final row = indexRow(episodeWithRolesAndVersions);
    expect(row.roles, isNull);
    expect(row.mediaVersions, isNull);
    expect(row.title, episodeWithRolesAndVersions.title);
    expect(row.viewOffsetMs, episodeWithRolesAndVersions.viewOffsetMs);
    expect(row.thumbPath, '/still/ep', reason: 'online lists still draw the still from the server');
    expect(row.externalRatings, episodeWithRolesAndVersions.externalRatings, reason: 'only cast and versions go');
  });

  test('a season row drops cast and versions too', () {
    final season = episodeWithRolesAndVersions.copyWith(kind: MediaKind.season);
    expect(indexRow(season).roles, isNull);
    expect(indexRow(season).mediaVersions, isNull);
  });

  test('a movie row is unchanged', () {
    final movie = film('m').copyWith(
      roles: const [MediaRole(tag: 'Actor')],
      mediaVersions: const [MediaVersion(id: 'v1')],
    );
    expect(indexRow(movie), movie);
  });

  test('a show row is unchanged', () {
    final show = film('s').copyWith(
      kind: MediaKind.show,
      roles: const [MediaRole(tag: 'Actor')],
    );
    expect(indexRow(show), show);
  });

  test('an episode keeps the season and show posters, not its own still', () {
    expect(indexedPosterPaths(episodeWithRolesAndVersions), ['/poster/season', '/poster/show']);
  });

  test('a season keeps its own poster and the show poster', () {
    final season = film('season').copyWith(kind: MediaKind.season, thumbPath: '/poster/season', parentThumbPath: '/p');
    expect(indexedPosterPaths(season), ['/poster/season', '/p']);
  });
}
