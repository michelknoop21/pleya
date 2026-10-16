import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_kid_audience.dart';
import 'package:pleya/profiles/household_kids_store.dart';

const _sam = HouseholdKid(id: 's', name: 'Sam', birthMonth: '2023-01');
const _noor = HouseholdKid(id: 'n', name: 'Noor', birthMonth: '2025-03');

void main() {
  const positives = [
    'geef suggesties voor mijn kinderen',
    'Is er een film voor de kinderen?',
    'iets voor onze kids vanavond',
    'een serie voor mijn zoon',
    'wat kan mijn dochter kijken',
    'iets voor de kleintjes',
    'een leuke kinderfilm',
    'kinderseries voor het weekend',
    'voor mijn jongste',
    'een kindvriendelijke film graag',
    'something for my kids',
    'a movie for the children tonight',
    'a kids movie please',
    'what can my daughter watch',
    'tips voor peuters',
    'iets voor mijn kleuter',
    'iets voor mijn kind',
    'een film voor mijn kind',
    'iets voor mijn jongens',
    'a movie for my 3 year old',
    'something for the little ones',
    'mijn kleinkinderen komen logeren, wat kijken we',
    'een film voor mijn 4-jarige',
    'my youngest wants a film',
    'voor mijn 5-jarige',
    'onze jongste kijkt mee',
  ];
  for (final q in positives) {
    test('about the children: $q', () => expect(kidAudienceOf(q, const [], const []).on, isTrue));
  }

  const negatives = [
    'een kindvriendelijk restaurant in de buurt',
    'toen ik een kind was keek ik dat altijd',
    'Children of Men zoeken',
    'wat heb ik vorige week gekeken',
    'een spannende film voor vanavond',
    'de oudste film in mijn bibliotheek',
    'vergeet de kinderfilms, ik deel mijn account met mijn kinderen',
    'geen kids movies alsjeblieft',
    'wat is de jongste film in mijn bibliotheek',
    'de jongste aflevering van Severance',
    'the youngest actor in this movie',
    'een film voor mijn 40-jarige vader',
    'iets voor een jarige',
    'films die 10 jaar oud zijn',
    'a 20 year old movie',
    'mijn kind account beheren',
    'my kid sister recommended a film',
    'kinderen van de zon',
    'mijn kind-account op Plex beheren',
  ];
  for (final q in negatives) {
    test('not about the children: $q', () => expect(kidAudienceOf(q, const [], const [_sam]).on, isFalse));
  }

  test('a name never narrows past a general word or an earlier all-kids state', () {
    const kids = [_sam, _noor];
    expect(kidAudienceOf('voor mijn kinderen, vooral Sam', const [], kids).ids, isEmpty);
    expect(kidAudienceOf('wat dacht je van Sam', ['iets voor mijn kinderen'], kids).ids, isEmpty);
    expect(kidAudienceOf('en iets voor Noor', ['iets voor Sam'], kids).ids, {'s', 'n'}, reason: 'a union, not a swap');
  });

  test('an inherited audience cannot be lost by the words of a split task', () {
    const kids = [_sam, _noor];
    const inherited = (on: true, ids: <String>{});
    expect(kidAudienceOf('iets voor mij', const [], kids, initial: inherited).on, isTrue);
    expect(kidAudienceOf('de serverstatus', const [], kids, initial: inherited).on, isTrue);
  });

  test('left out is not asked for, but "voor mij en mijn kinderen" counts', () {
    expect(kidAudienceOf('iets voor mij en mijn kinderen', const [], const []).on, isTrue);
  });

  test('gezin and familie count only once children are entered', () {
    expect(kidAudienceOf('een film voor het gezin', const [], const []).on, isFalse);
    expect(kidAudienceOf('een film voor het gezin', const [], const [_sam]).on, isTrue);
    expect(kidAudienceOf('een familiefilm', const [], const [_sam]).on, isTrue);
    expect(kidAudienceOf('a family movie', const [], const [_noor]).on, isTrue);
  });

  test('a household name on a word boundary narrows to that child', () {
    final a = kidAudienceOf('iets voor Sam', const [], const [_sam, _noor]);
    expect(a.on, isTrue);
    expect(a.ids, {'s'});
    expect(kidAudienceOf('iets over Samurai', const [], const [_sam]).on, isFalse);
    expect(kidAudienceOf('iets voor de kinderen', const [], const [_sam, _noor]).ids, isEmpty);
  });

  test('a follow-up inherits the audience until "voor mij" or a new conversation', () {
    const turns = ['geef suggesties voor mijn kinderen'];
    expect(kidAudienceOf('nog meer?', turns, const []).on, isTrue);
    expect(kidAudienceOf('en iets korters', turns, const []).on, isTrue);
    expect(kidAudienceOf('nu iets voor mij', turns, const []).on, isFalse);
    expect(kidAudienceOf('nog meer?', const ['iets voor mezelf', 'wat nu?'], const []).on, isFalse);
    expect(kidAudienceOf('nog meer?', const [], const []).on, isFalse, reason: 'Nieuw gesprek: no turns');
    expect(kidAudienceOf('nog meer?', ['geef suggesties voor mijn kinderen', 'nu voor mij'], const []).on, isFalse);
  });
}
