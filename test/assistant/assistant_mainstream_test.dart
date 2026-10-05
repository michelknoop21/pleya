import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_mainstream.dart';
import 'package:pleya/assistant/assistant_recommend_constraints.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/models/seerr/seerr_media.dart';

SeerrMedia _m(
  int id,
  String title, {
  int? votes,
  double? popularity,
  String language = 'en',
  List<String>? countries,
}) => SeerrMedia(
  tmdbId: id,
  mediaType: 'movie',
  title: title,
  voteCount: votes,
  popularity: popularity,
  originalLanguage: language,
  originCountry: countries,
);

List<String> _titles(List<SeerrMedia> l) => [for (final m in l) m.title];

void main() {
  group('rankSuggestions', () {
    test('a famous title beats an obscure one that the source listed first', () {
      // The source put the obscure film first (a sort on rating does that).
      final ranked = rankSuggestions([
        _m(1, 'Obscure Gem', votes: 12, popularity: 2),
        _m(2, 'Big Blockbuster', votes: 22000, popularity: 480),
        _m(3, 'Known Drama', votes: 3400, popularity: 90),
        _m(4, 'Another Hit', votes: 8000, popularity: 150),
        _m(5, 'Mid Film', votes: 900, popularity: 30),
        _m(6, 'Third Hit', votes: 15000, popularity: 300),
      ]);
      expect(_titles(ranked).first, isNot('Obscure Gem'));
      expect(_titles(ranked), isNot(contains('Obscure Gem')), reason: 'five known ones are enough');
      // The four big titles come first, the mid-sized one after them.
      expect(_titles(ranked).take(4), unorderedEquals(['Big Blockbuster', 'Known Drama', 'Another Hit', 'Third Hit']));
      expect(_titles(ranked).last, 'Mid Film');
    });

    test('a worldwide hit in another language counts as mainstream', () {
      final ranked = rankSuggestions([
        _m(1, 'Small Local', votes: 150, popularity: 8, language: 'fr'),
        _m(2, 'Squid Game', votes: 14000, popularity: 700, language: 'ko'),
      ]);
      expect(_titles(ranked).first, 'Squid Game');
    });

    test('a Dutch title sits under a big American one and above a small one', () {
      final ranked = rankSuggestions([
        _m(1, 'Kleine Indie', votes: 40, popularity: 4, language: 'en'),
        _m(2, 'Dutch Hit', votes: 450, popularity: 25, language: 'nl', countries: ['NL']),
        _m(3, 'American Blockbuster', votes: 12000, popularity: 400),
      ]);
      expect(_titles(ranked), ['American Blockbuster', 'Dutch Hit', 'Kleine Indie']);
    });

    test('a strong personal match (the source order) still lifts a less famous title over a weak famous one', () {
      final ranked = rankSuggestions([
        _m(1, 'Close Match', votes: 600, popularity: 20),
        _m(2, 'Famous But Far', votes: 700, popularity: 25),
        _m(3, 'Filler A', votes: 650, popularity: 22),
        _m(4, 'Filler B', votes: 640, popularity: 21),
        _m(5, 'Filler C', votes: 630, popularity: 20),
      ]);
      expect(_titles(ranked).first, 'Close Match');
    });

    test('obscure titles only fill up when fewer than five known ones are left', () {
      final ranked = rankSuggestions([
        _m(1, 'Hit A', votes: 9000, popularity: 200),
        _m(2, 'Hit B', votes: 8000, popularity: 180),
        _m(3, 'Obscure One', votes: 5, popularity: 1),
        _m(4, 'Obscure Two', votes: 8, popularity: 1),
        _m(5, 'Obscure Three', votes: 9, popularity: 1),
        _m(6, 'Obscure Four', votes: 7, popularity: 1),
      ]);
      expect(_titles(ranked), ['Hit A', 'Hit B', 'Obscure One', 'Obscure Two', 'Obscure Three']);
    });

    test('a niche question keeps the source order', () {
      final found = [_m(1, 'Obscure Gem', votes: 12, popularity: 2), _m(2, 'Big Blockbuster', votes: 22000)];
      expect(_titles(rankSuggestions(found, niche: true)), ['Obscure Gem', 'Big Blockbuster']);
    });

    test('a title in Han characters is skipped and the next one is taken, niche or not', () {
      final found = [_m(1, '流浪地球', votes: 9000, popularity: 100, language: 'zh'), _m(2, 'Dune', votes: 12000)];
      expect(_titles(rankSuggestions(found)), ['Dune']);
      expect(_titles(rankSuggestions(found, niche: true)), ['Dune']);
    });

    test('titles without votes or popularity keep the source order', () {
      final found = [_m(1, 'Toy Story'), _m(2, 'Dune')];
      expect(_titles(rankSuggestions(found)), ['Toy Story', 'Dune']);
    });
  });

  group('displayTitle', () {
    test('Dutch first, then English, then the original', () {
      expect(displayTitle(nl: 'De Wolf van Wall Street', en: 'The Wolf of Wall Street'), 'De Wolf van Wall Street');
      expect(displayTitle(nl: '流浪地球', en: 'The Wandering Earth', original: '流浪地球'), 'The Wandering Earth');
      expect(displayTitle(nl: '', en: null, original: 'Amélie'), 'Amélie');
    });

    test('no title without Han characters is null, so the candidate is skipped', () {
      expect(displayTitle(nl: '流浪地球', en: '流浪地球', original: '流浪地球'), isNull);
      expect(displayTitle(nl: '', en: '', original: ''), isNull);
    });

    test('hasHan sees Chinese characters in Chinese and Japanese titles, not kana or Latin', () {
      expect(hasHan('千と千尋の神隠し'), isTrue);
      expect(hasHan('Spirited Away'), isFalse);
      expect(hasHan('ありがとう'), isFalse);
    });
  });

  group('constraints', () {
    test('an explicit ask for the unknown switches the ranking to niche', () {
      for (final p in [
        'Geef me een hidden gem',
        'Ik zoek obscure films',
        'Wat arthouse voor vanavond?',
        'Een Aziatische film graag',
        'Iets van een festival',
      ]) {
        expect(AssistantRecommendConstraints.fromPrompt(p).niche, isTrue, reason: p);
      }
      expect(AssistantRecommendConstraints.fromPrompt('Wat is een goede film voor vanavond?').niche, isFalse);
      expect(AssistantRecommendConstraints.fromPrompt('Geef 5 tips voor een serie').niche, isFalse);
    });

    test('a library pick with a Han title is not admitted', () {
      MediaItem item(String title) =>
          MediaItem(id: title, backend: MediaBackend.plex, kind: MediaKind.movie, title: title);
      const c = AssistantRecommendConstraints();
      expect(c.admitsItem(item('Dune')), isTrue);
      expect(c.admitsItem(item('流浪地球')), isFalse);
    });
  });
}
