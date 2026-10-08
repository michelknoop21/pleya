import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/models/seerr/seerr_request.dart';

void main() {
  group('R4 stored-field evidence', () {
    Map<String, dynamic> complete() => {
      'id': 42,
      'status': 1,
      'type': 'tv',
      'is4k': false,
      'requestedBy': {'id': 7},
      'seasons': [1],
      'serverId': null,
      'profileId': null,
      'rootFolder': null,
      'tags': null,
      'languageProfileId': null,
    };
    test('explicit nullable values remain known and survive hydration', () {
      final row = SeerrRequest.tryFromJson(complete())!;
      expect(row.targetKnown, isTrue);
      expect(row.advancedKnown, isTrue);
      expect(row.withDisplayData(title: 'x').advancedKnown, isTrue);
    });
    for (final field in ['serverId', 'profileId', 'rootFolder', 'tags', 'languageProfileId']) {
      test('R4 missing $field is not evidence of null', () {
        final row = SeerrRequest.tryFromJson(complete()..remove(field))!;
        expect(field == 'tags' || field == 'languageProfileId' ? row.advancedKnown : row.targetKnown, isFalse);
      });
    }
    test('integer strings are valid but fractions and objects are not', () {
      final valid = SeerrRequest.tryFromJson({
        ...complete(),
        'serverId': '2',
        'profileId': 6.0,
        'tags': ['9'],
      })!;
      expect(valid.targetKnown, isTrue);
      expect(valid.advancedKnown, isTrue);
      expect(valid.tags, [9]);
      final bad = SeerrRequest.tryFromJson({
        ...complete(),
        'profileId': 6.5,
        'tags': [9, {}],
      })!;
      expect(bad.targetKnown, isFalse);
      expect(bad.advancedKnown, isFalse);
    });
  });

  group('SeerrRequest', () {
    test('parses embedded media display fields', () {
      final request = SeerrRequest.tryFromJson({
        'id': 42,
        'status': 1,
        'type': 'movie',
        'is4k': true,
        'media': {
          'tmdbId': 550,
          'status': 2,
          'title': 'Fight Club',
          'releaseDate': '1999-10-15',
          'posterPath': '/poster.jpg',
          'backdropPath': '/backdrop.jpg',
        },
        'requestedBy': {'id': 7, 'displayName': 'Michel'},
      });

      expect(request, isNotNull);
      expect(request!.mediaTitle, 'Fight Club');
      expect(request.mediaYear, '1999');
      expect(request.posterPath, '/poster.jpg');
      expect(request.backdropPath, '/backdrop.jpg');
      expect(request.tmdbId, 550);
      expect(request.is4k, isTrue);
      expect(request.requestedByName, 'Michel');
    });

    test('falls back to nested movie or tv payload fields', () {
      final request = SeerrRequest.tryFromJson({
        'id': 43,
        'status': 1,
        'media': {
          'tmdbId': 1399,
          'mediaType': 'tv',
          'tv': {'name': 'Game of Thrones', 'firstAirDate': '2011-04-17', 'posterPath': '/got.jpg'},
        },
      });

      expect(request, isNotNull);
      expect(request!.mediaType, 'tv');
      expect(request.mediaTitle, 'Game of Thrones');
      expect(request.mediaYear, '2011');
      expect(request.posterPath, '/got.jpg');
    });
  });
}
