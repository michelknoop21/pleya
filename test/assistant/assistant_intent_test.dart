import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_intent.dart';
import 'package:pleya/media/media_kind.dart';

AssistantIntent _i(String p) => AssistantIntent.fromPrompt(p);

void main() {
  group('fromPrompt', () {
    test('others, me and everyone, in Dutch and English, each marked explicit', () {
      expect(_i('Wat kijken de anderen het meest?').audience.value, AssistantAudience.others);
      expect(_i('What do my friends watch?').audience.value, AssistantAudience.others);
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
}
