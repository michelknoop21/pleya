import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_intent.dart';
import 'package:pleya/media/media_kind.dart';

AssistantIntent _i(String p) => AssistantIntent.fromPrompt(p);

void main() {
  group('fromPrompt', () {
    test('others, me and everyone, in Dutch and English, each marked explicit', () {
      expect(_i('Wat kijken de anderen het meest?').audience.value, AssistantAudience.others);
      expect(_i('What do the others watch?').audience.value, AssistantAudience.others);
      expect(_i('Welke films heb ik gekeken?').audience.value, AssistantAudience.me);
      expect(_i('What did I watch last week?').audience.value, AssistantAudience.me);
      expect(_i('What is popular?').audience.known, isFalse);
      expect(_i('Wat kijkt iedereen deze week?').audience.value, AssistantAudience.everyone);
      expect(_i('Wat kijken de anderen?').audience.source, AssistantFieldSource.explicit);
    });

    test('others beats a first-person word: "ik" alone is not "me"', () {
      expect(_i('Ik wil weten wat de anderen kijken').audience.value, AssistantAudience.others);
      expect(_i('Ik wil weten wat Sam kijkt').audience.known, isFalse);
      expect(_i('Wat kijkt iedereen behalve ik?').audience.value, isNot(AssistantAudience.everyone));
    });

    test('a film question is films and a series question is series; both or none is open', () {
      expect(_i('Welke films keken de anderen?').kind.value, MediaKind.movie);
      expect(_i('Welke series keken de anderen?').kind.value, MediaKind.show);
      expect(_i('Een tip voor een serie of film?').kind.known, isFalse);
      expect(_i('Wat keken de anderen?').kind.known, isFalse);
    });

    test('a period: today, a week, a month, N days; out of range is open', () {
      expect(_i('Wat is er vandaag gekeken?').days.value, 1);
      expect(_i('Wat keken de anderen deze week?').days.value, 7);
      expect(_i('Top titels afgelopen maand').days.value, 30);
      expect(_i('de laatste 14 dagen').days.value, 14);
      expect(_i('de laatste 90 dagen').days.known, isFalse);
    });

    test('nothing stated is nothing fixed', () {
      expect(_i('Scan mijn bibliotheek').any, isFalse);
      expect(_i('Scan mijn bibliotheek').describe(), isNull);
    });
  });

  group('constrain', () {
    test('the user\'s audience overrules the model: others never becomes everyone', () {
      final fixed = _i(
        'Wat kijken de anderen deze week?',
      ).constrain('watch_stats', {'scope': 'period', 'audience': 'all'});
      expect(fixed.error, isNull);
      expect(fixed.args['audience'], 'others');
      expect(fixed.args['days'], 7);
    });

    test('everyone is stated as all, and an unstated audience stays the model\'s', () {
      expect(_i('Wat kijkt iedereen?').constrain('watch_stats', {'scope': 'period'}).args['audience'], 'all');
      expect(
        _i(
          'Wat wordt er gekeken?',
        ).constrain('watch_stats', {'scope': 'period', 'audience': 'others'}).args['audience'],
        'others',
      );
    });

    test('a film question never asks for series, and the reverse', () {
      expect(
        _i(
          'Welke films keken de anderen?',
        ).constrain('watch_stats', {'scope': 'period', 'media': 'show'}).args['media'],
        'movie',
      );
      expect(_i('Welke series heb ik gekeken?').constrain('my_watching', {'kind': 'movie'}).args['kind'], 'show');
      expect(
        _i('Welke films keken de anderen?').constrain('watch_stats', {'scope': 'now'}).args,
        isNot(contains('media')),
      );
    });

    test('the right tool for the right person', () {
      expect(_i('Wat heb ik gekeken?').constrain('watch_stats', {'scope': 'period'}).error, 'use_my_watching');
      expect(_i('Wat kijken de anderen?').constrain('my_watching', const {}).error, 'use_watch_stats');
      expect(_i('Wat heb ik gekeken?').constrain('my_watching', const {}).error, isNull);
      expect(_i('Wat kijken de anderen?').constrain('scan_library', {'a': 1}).args, {'a': 1});
    });
  });

  group('review findings (BP-04a)', () {
    test('"show me" is the verb: no series filter; "tv shows" and "shows" are series', () {
      expect(_i('Show me what the others watched this week').kind.known, isFalse);
      expect(_i('Show me a good thriller').kind.known, isFalse);
      expect(_i('Something like The Truman Show').kind.known, isFalse);
      expect(_i('Welke tv shows keken de anderen?').kind.value, MediaKind.show);
      expect(_i('Which shows did the others watch?').kind.value, MediaKind.show);
    });

    test('a kind cannot be enforced on current streams: refused, not a mixed list', () {
      final fixed = _i('Welke films kijkt iedereen nu?').constrain('watch_stats', {'scope': 'now'});
      expect(fixed.error, 'media_needs_period');
    });

    test('"everyone except <name>" is no audience; except me still is "others"', () {
      expect(_i('Wat kijkt iedereen behalve Sam?').audience.known, isFalse);
      expect(
        _i('Wat kijkt iedereen behalve Sam?').constrain('watch_stats', {'scope': 'period'}).args,
        isNot(contains('audience')),
      );
      expect(_i('Wat kijkt iedereen behalve ik?').audience.value, AssistantAudience.others);
      expect(_i('What does everyone except Sam watch?').audience.known, isFalse);
    });

    test('words that are not a watch question about others stay open', () {
      for (final p in [
        'Wat is de rest van de film?',
        'Wat kan ik met mijn gezin kijken?',
        'What can I watch with my friends?',
        'Is er iets dat anderen ook goed vonden?',
        'Wat moet ik kijken? Een film die iedereen leuk vindt',
        'Een film voor iedereen',
      ]) {
        expect(_i(p).audience.known, isFalse, reason: p);
      }
    });

    test('negation and mixed questions are not decided: nothing narrowed, nothing widened', () {
      expect(_i('Wat heb ik gekeken, niet wat de anderen keken').audience.value, AssistantAudience.me);
      expect(_i('Wat heb ik gekeken en wat keken de anderen?').audience.known, isFalse);
      expect(_i('What did I watch and what did the others watch?').audience.known, isFalse);
    });

    test('"last week" is not the past seven days; two periods fix none', () {
      expect(_i('Wat keken we vorige week?').days.known, isFalse);
      expect(_i('What did the others watch last week?').days.known, isFalse);
      expect(_i('Wat kijken anderen vandaag en deze week?').days.known, isFalse);
      expect(_i('Wat keken de anderen deze week?').days.value, 7);
    });

    test('a task split off a question keeps what that question fixed; its own words win', () {
      final parent = _i('Wat kijken de anderen deze week, en hoeveel films?');
      final child = _i('Toon de meest bekeken titels').inheriting(parent);
      expect(child.audience.value, AssistantAudience.others);
      expect(child.days.value, 7);
      expect(child.kind.known, isFalse);
      final own = _i('Toon wat ik gekeken heb').inheriting(parent);
      expect(own.audience.value, AssistantAudience.me, reason: 'the child states its own audience');
      expect(AssistantIntent.unknown.inheriting(AssistantIntent.unknown).any, isFalse);
    });

    test('English "everyone but/besides me" is the others, never everyone', () {
      for (final q in [
        'What did everyone but me watch?',
        'What did everybody besides me watch?',
        'What did everyone other than me watch?',
      ]) {
        expect(_i(q).audience.value, AssistantAudience.others, reason: q);
      }
    });

    test('a child never inherits the kind: it can belong to a tip in the parent question', () {
      final parent = _i('Wat heb ik gekeken en tip een serie');
      final child = _i('Toon mijn kijkgeschiedenis').inheriting(parent);
      expect(child.kind.known, isFalse);
      expect(child.constrain('my_watching', const {}).args, isNot(contains('kind')));
      expect(child.audience.value, AssistantAudience.me);
    });

    test('"bekeken" is a watch verb', () {
      expect(_i('Wat is er door anderen bekeken?').audience.value, AssistantAudience.others);
    });
  });

  group('BP-04b', () {
    test('"vorige week" is not the last 7 days: refused, not answered with days 7', () {
      final i = _i('Wat is er vorige week gekeken?');
      expect(i.previousWeek, isTrue);
      expect(i.constrain('watch_stats', {'scope': 'period', 'days': 7}).error, 'previous_week_not_supported');
      expect(_i('Wat is er deze week gekeken?').previousWeek, isFalse);
      expect(_i('What was watched last week?').previousWeek, isTrue);
    });

    test('a child task inherits the previous-week flag', () {
      final child = _i('Wat keken ze?').inheriting(_i('Wat is er vorige week gekeken?'));
      expect(child.constrain('watch_stats', {'scope': 'period'}).error, 'previous_week_not_supported');
    });

    test('me and the others in one question: no audience fixed, the model is told to answer both', () {
      final i = _i('Wat heb ik gekeken en wat keken de anderen?');
      expect(i.audience.known, isFalse);
      expect(i.mixedAudience, isTrue);
      expect(i.describe(), contains('more than one audience'));
      expect(_i('Wat keken de anderen?').mixedAudience, isFalse);
    });

    test('review: refused on every window, my_watching stays open; "in the last week" is the past 7 days', () {
      final i = _i('Wat is er vorige week gekeken?');
      expect(i.constrain('watch_stats', {'scope': 'now'}).error, 'previous_week_not_supported');
      // my_watching is also the tip tool: a history-plus-tip question must keep it.
      expect(i.constrain('my_watching', {}).error, isNull);
      expect(i.constrain('watch_stats', {'scope': 'period'}).error, 'previous_week_not_supported');
      expect(_i('What was watched within the last week?').previousWeek, isFalse);
      expect(i.describe(), contains('calendar week'));
      expect(_i('What was watched in the last week?').previousWeek, isFalse);
      expect(_i('Wat keek ik een week geleden?').previousWeek, isFalse);
    });

    test('review: the mixed note survives a fixed kind', () {
      final i = _i('Welke films heb ik gekeken en wat keken de anderen?');
      expect(i.describe(), allOf(contains('only films'), contains('more than one audience')));
    });

    test('"toegevoegd" routes to the catalog with the period; the wrong tools are refused', () {
      final i = _i('Wat is deze week aan mijn bibliotheken toegevoegd?');
      expect(i.addedToLibraries, isTrue);
      expect(i.constrain('search_catalog', {'sort': 'added', 'limit': 20}).args['added_within_days'], 7);
      expect(i.constrain('list_servers', {}).error, 'use_search_catalog');
      expect(i.constrain('watch_stats', {'scope': 'period'}).error, 'use_search_catalog');
      expect(i.describe(), contains('added_within_days'));
    });

    test('added-to-libraries: the model\'s own window is overruled, kind is enforced, last week refused', () {
      final i = _i('Welke films zijn de laatste 14 dagen toegevoegd?');
      final c = i.constrain('search_catalog', {'added_within_days': 3});
      expect(c.args['added_within_days'], 14);
      expect(c.args['kind'], 'movie');
      expect(
        _i('Wat is er vorige week toegevoegd?').constrain('search_catalog', {}).error,
        'previous_week_not_supported',
      );
    });

    test('added to a list, or a watch question beside it, is not an additions question', () {
      expect(_i('Wat heb ik aan mijn kijklijst toegevoegd?').addedToLibraries, isFalse);
      final mixed = _i('Wat is toegevoegd en wat keken de anderen?');
      expect(mixed.constrain('watch_stats', {'scope': 'period'}).error, isNull);
      expect(_i('Een tip').inheriting(_i('Wat is er toegevoegd en geef me een tip')).addedToLibraries, isFalse);
    });

    test('review: a period that may belong to another clause or that days cannot hold is not forced', () {
      final mixed = _i('Wat is er toegevoegd en wat keken de anderen afgelopen week?');
      expect(mixed.constrain('search_catalog', {}).args, isNot(contains('added_within_days')));
      expect(
        _i('Wat is er de laatste 3 maanden toegevoegd?').constrain('search_catalog', {}).error,
        'window_not_supported',
      );
      expect(_i('Wat is er toegevoegde films deze week?').addedToLibraries, isTrue);
      expect(_i('Zet het op mijn afspeellijst toegevoegd').addedToLibraries, isFalse);
    });

    test('review: kind is only enforced on search_catalog for an additions question', () {
      final i = _i('Zoek een film met Tom Hanks');
      expect(i.constrain('search_catalog', {}).args, isNot(contains('kind')));
    });

    test('review: requests, added value and a watch clause beside a long period are not additions-only', () {
      expect(_i('I added this movie to Radarr').addedToLibraries, isFalse);
      expect(_i('Dat is een toegevoegde waarde').addedToLibraries, isFalse);
      final mixed = _i('Wat is er toegevoegd en wat keken de anderen de laatste 2 weken?');
      expect(mixed.constrain('search_catalog', {}).error, isNull);
    });
  });

  group('splitMixedAudience (BP-04b)', () {
    test('me and the others in one sentence are two questions, each with its own audience', () {
      expect(AssistantIntent.splitMixedAudience('Wat heb ik gekeken en wat keken de anderen?'), [
        'Wat heb ik gekeken',
        'wat keken de anderen?',
      ]);
      expect(AssistantIntent.splitMixedAudience('What did the others watch, and what did I watch?'), [
        'What did the others watch,',
        'what did I watch?',
      ]);
    });

    test('anything not plainly two audiences is left to the model', () {
      expect(AssistantIntent.splitMixedAudience('Wat heb ik gekeken?'), isNull);
      expect(AssistantIntent.splitMixedAudience('Wat keken de anderen?'), isNull);
      expect(
        AssistantIntent.splitMixedAudience('Wat heb ik gekeken wat keken de anderen'),
        isNull,
        reason: 'no joiner',
      );
      expect(AssistantIntent.splitMixedAudience('Wat keek iedereen behalve Sam en wat heb ik gekeken?'), isNull);
      expect(AssistantIntent.splitMixedAudience('Wat heb ik gekeken, niet wat de anderen keken'), isNull);
    });
  });
}
