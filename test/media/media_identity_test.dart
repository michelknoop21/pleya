import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_identity.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/utils/external_ids.dart';

MediaItem item({
  String id = '1',
  String? guid,
  String? title = 'Sintel',
  int? year = 2010,
  MediaKind kind = MediaKind.movie,
}) => MediaItem(id: id, backend: MediaBackend.plex, kind: kind, guid: guid, title: title, year: year);

({MediaItem item, ExternalIds ids}) candidate(MediaItem i, [ExternalIds ids = const ExternalIds()]) =>
    MediaIdentity.candidate(i, ids);

void main() {
  group('pickMatch tiers', () {
    test('a guid beats everything else', () {
      const identity = MediaIdentity(guid: 'plex://movie/abc', title: 'Sintel', year: 2010);

      final picked = identity.pickMatch([
        candidate(item(id: 'wrong', guid: 'plex://movie/other')),
        candidate(item(id: 'right', guid: 'plex://movie/abc')),
      ]);

      expect(picked?.id, 'right');
    });

    test('an external id decides when no guid matches', () {
      const identity = MediaIdentity(
        externalIds: ExternalIds(imdb: 'tt1727587'),
        title: 'Sintel',
      );

      final picked = identity.pickMatch([
        candidate(item(id: 'a'), const ExternalIds(imdb: 'tt0000001')),
        candidate(item(id: 'b'), const ExternalIds(imdb: 'tt1727587')),
      ]);

      expect(picked?.id, 'b');
    });

    test('tmdb and tvdb count as external ids too', () {
      expect(
        const MediaIdentity(
          externalIds: ExternalIds(tmdb: 45745),
        ).pickMatch([candidate(item(), const ExternalIds(tmdb: 45745))])?.id,
        '1',
      );
      expect(
        const MediaIdentity(
          externalIds: ExternalIds(tvdb: 73141),
        ).pickMatch([candidate(item(), const ExternalIds(tvdb: 73141))])?.id,
        '1',
      );
    });

    test('title and year are the last resort', () {
      const identity = MediaIdentity(title: 'Sintel', year: 2010, kind: MediaKind.movie);

      expect(identity.pickMatch([candidate(item(id: 'only'))])?.id, 'only');
    });

    test('a title match with a disagreeing year is not a match', () {
      const identity = MediaIdentity(title: 'Sintel', year: 2010, kind: MediaKind.movie);

      expect(identity.pickMatch([candidate(item(year: 1999))]), isNull);
    });

    test('a missing year on either side is tolerated', () {
      const identity = MediaIdentity(title: 'Sintel', kind: MediaKind.movie);

      expect(identity.pickMatch([candidate(item(year: 2010))])?.id, '1');
      expect(
        const MediaIdentity(
          title: 'Sintel',
          year: 2010,
          kind: MediaKind.movie,
        ).pickMatch([candidate(item(year: null))])?.id,
        '1',
      );
    });

    test('normalization ignores punctuation, case and a trailing year', () {
      const identity = MediaIdentity(title: 'The Miniature Wife', kind: MediaKind.movie, year: 2024);

      expect(identity.pickMatch([candidate(item(title: 'the.miniature-wife (2024)', year: 2024))])?.id, '1');
    });

    test('a different kind never matches on title', () {
      const identity = MediaIdentity(title: 'Sintel', kind: MediaKind.movie);

      expect(identity.pickMatch([candidate(item(kind: MediaKind.show))]), isNull);
    });
  });

  group('ambiguity', () {
    test('two candidates with the same guid resolve to nothing', () {
      const identity = MediaIdentity(guid: 'plex://movie/abc', title: 'Sintel');

      final picked = identity.pickMatch([
        candidate(item(id: 'a', guid: 'plex://movie/abc')),
        candidate(item(id: 'b', guid: 'plex://movie/abc')),
      ]);

      expect(picked, isNull, reason: 'guessing would put the wrong item behind the poster');
    });

    test('two candidates with the same external id resolve to nothing', () {
      const identity = MediaIdentity(
        externalIds: ExternalIds(imdb: 'tt1'),
        title: 'Sintel',
      );

      expect(
        identity.pickMatch([
          candidate(item(id: 'a'), const ExternalIds(imdb: 'tt1')),
          candidate(item(id: 'b'), const ExternalIds(imdb: 'tt1')),
        ]),
        isNull,
      );
    });

    test('two candidates with the same title resolve to nothing', () {
      const identity = MediaIdentity(title: 'Sintel', year: 2010, kind: MediaKind.movie);

      expect(identity.pickMatch([candidate(item(id: 'a')), candidate(item(id: 'b'))]), isNull);
    });

    test('a guid that matches nothing does not fall through to a title guess', () {
      const identity = MediaIdentity(guid: 'plex://movie/abc', title: 'Sintel', year: 2010, kind: MediaKind.movie);

      expect(identity.pickMatch([candidate(item(id: 'title-only', guid: null))])?.id, 'title-only');
    });
  });

  group('isSearchable', () {
    test('is true when there is anything to go on', () {
      expect(const MediaIdentity(guid: 'plex://movie/abc').isSearchable, isTrue);
      expect(const MediaIdentity(externalIds: ExternalIds(imdb: 'tt1')).isSearchable, isTrue);
      expect(const MediaIdentity(title: 'Sintel').isSearchable, isTrue);
    });

    test('is false when a lookup could only guess', () {
      expect(const MediaIdentity().isSearchable, isFalse);
      expect(const MediaIdentity(guid: '', title: '').isSearchable, isFalse);
    });
  });
}
