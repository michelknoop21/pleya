import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_media_key.dart';
import 'package:pleya/utils/external_ids.dart';

AssistantMediaKey _k(String bucket, {int? year, ExternalIds ids = const ExternalIds()}) =>
    AssistantMediaKey(bucket: bucket, year: year, ids: ids);

void main() {
  group('assistantMediaMatch', () {
    test('a shared id is proof, even under different titles', () {
      expect(
        assistantMediaMatch(
          _k('movie:dune', ids: const ExternalIds(tmdb: 1)),
          _k('movie:duneparttone', ids: const ExternalIds(tmdb: 1)),
        ),
        AssistantMediaProof.external,
      );
    });

    test('a differing id of one scheme is another title, whatever the name says', () {
      expect(
        assistantMediaMatch(
          _k('movie:dune', year: 2021, ids: const ExternalIds(tmdb: 1)),
          _k('movie:dune', year: 2021, ids: const ExternalIds(tmdb: 2)),
        ),
        isNull,
      );
    });

    test('a film never matches a series, not even on an id', () {
      expect(
        assistantMediaMatch(
          _k('movie:dune', ids: const ExternalIds(tmdb: 1)),
          _k('show:dune', ids: const ExternalIds(tmdb: 1)),
        ),
        isNull,
      );
    });

    test('title and year, year missing, and years that differ', () {
      expect(
        assistantMediaMatch(_k('movie:dune', year: 2021), _k('movie:dune', year: 2021)),
        AssistantMediaProof.titleYear,
      );
      expect(assistantMediaMatch(_k('movie:dune', year: 2021), _k('movie:dune')), AssistantMediaProof.titleOnly);
      expect(assistantMediaMatch(_k('movie:dune', year: 1984), _k('movie:dune', year: 2021)), isNull);
    });
  });

  group('clusterByMediaKey', () {
    List<AssistantMediaCluster<(String, AssistantMediaKey)>> run(List<(String, AssistantMediaKey)> rows) =>
        clusterByMediaKey(rows, keyOf: (r) => r.$2, serverOf: (r) => r.$1);

    test('the weakest proof that joins a server is kept', () {
      final c = run([
        ('a', _k('movie:dune', year: 2021, ids: const ExternalIds(tmdb: 1))),
        ('b', _k('movie:dune', year: 2021, ids: const ExternalIds(tmdb: 1))),
        ('c', _k('movie:dune')),
      ]).single;
      expect(c.servers, {'a', 'b', 'c'});
      expect(c.weakest, AssistantMediaProof.titleOnly);
    });

    test('repeat rows on one server stay one server and never mark a merge', () {
      final c = run([for (var i = 0; i < 5; i++) ('a', _k('movie:dune'))]).single;
      expect(c.members, hasLength(5));
      expect(c.crossServer, isFalse);
      expect(c.weakest, isNull);
    });
  });
}
