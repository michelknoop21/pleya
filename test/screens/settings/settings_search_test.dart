import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/screens/settings/settings_screen.dart';

void main() {
  group('settingsSearchMatches', () {
    test('empty query never matches (empty query = unchanged full list)', () {
      expect(settingsSearchMatches(title: 'Appearance', lowerQuery: ''), isFalse);
    });

    test('matches on title substring, case-insensitive', () {
      expect(settingsSearchMatches(title: 'Appearance', lowerQuery: 'pear'), isTrue);
    });

    test('matches on subtitle', () {
      expect(settingsSearchMatches(title: 'Playback', subtitle: 'Subtitles and audio', lowerQuery: 'audio'), isTrue);
    });

    test('matches on keyword (e.g. trakt under Trackers)', () {
      expect(settingsSearchMatches(title: 'Trackers', keywords: const ['trakt', 'mal'], lowerQuery: 'trakt'), isTrue);
    });

    test('no match when query is absent from title, subtitle and keywords', () {
      expect(
        settingsSearchMatches(title: 'About', subtitle: 'App info', keywords: const ['version'], lowerQuery: 'zzz'),
        isFalse,
      );
    });
  });
}
