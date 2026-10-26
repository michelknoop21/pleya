import 'dart:io';

/// Real film art for the A-24b comparison screenshots: Blender open movies,
/// licensed CC BY, read from `assets/studio_art/` (see the README there for
/// source and licence per file).
///
/// Every other fixture draws flat 32x32 squares or calibration charts, which
/// is right for measuring a crop but makes a settings header or a poster rail
/// look empty next to its northstar. These bytes are read as they are, never
/// re-encoded, and `test/studio_art_test.dart` pins their sha256, so the
/// fixture stays deterministic: same files in, same bytes served.
///
/// The files are resolved against the working directory, which is the
/// package root both for `bin/serve.dart` (the runner starts it there) and
/// for `dart test`.
const String studioArtDir = 'assets/studio_art';

/// One film of `catalog.studio-art.v1`, in rail order. Sintel and Big Buck
/// Bunny come first: they are the two with a true wide still, and the first
/// items are what the Studio header and the Home hero read.
typedef StudioArtFilm = ({String slug, String title, int year, String poster, String backdrop});

const List<StudioArtFilm> studioArtFilms = [
  (slug: 'sintel', title: 'Sintel', year: 2010, poster: 'sintel-poster.jpg', backdrop: 'sintel-backdrop.jpg'),
  (slug: 'big-buck-bunny', title: 'Big Buck Bunny', year: 2008, poster: 'bbb-poster.jpg', backdrop: 'bbb-backdrop.jpg'),
  (
    slug: 'tears-of-steel',
    title: 'Tears of Steel',
    year: 2012,
    poster: 'tears-poster.jpg',
    backdrop: 'tears-backdrop.jpg',
  ),
  (slug: 'spring', title: 'Spring', year: 2019, poster: 'spring-poster.jpg', backdrop: 'spring-backdrop.jpg'),
  (slug: 'charge', title: 'Charge', year: 2022, poster: 'charge-poster.jpg', backdrop: 'charge-backdrop.jpg'),
  (
    slug: 'coffee-run',
    title: 'Coffee Run',
    year: 2020,
    poster: 'coffeerun-poster.jpg',
    backdrop: 'coffeerun-backdrop.jpg',
  ),
];

/// The bytes of one file in [studioArtDir]. Throws a [StateError] naming the
/// path when the file is missing, so a run started from the wrong directory
/// fails on the seed instead of serving blank artwork.
List<int> studioArtBytes(String fileName) {
  final file = File('$studioArtDir/$fileName');
  if (!file.existsSync()) {
    throw StateError('studio art not found: ${file.absolute.path} (run from the fixture_server package root)');
  }
  return file.readAsBytesSync();
}
