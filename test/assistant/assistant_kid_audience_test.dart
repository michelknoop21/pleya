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
  ];
  for (final q in negatives) {
    test('not about the children: $q', () => expect(kidAudienceOf(q, const [], const [_sam]).on, isFalse));
  }

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
