import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_source_info.dart';
import 'package:pleya/media/track_language_choice.dart';
import 'package:pleya/services/source_stream_language.dart';

/// While Plex transcodes, picking a subtitle does not swap an mpv track: it
/// selects a different source stream and reloads. Resolving that stream id back
/// to a language is what stands between the pick and the language memory, and
/// it was missing entirely, so the memory worked on direct play and nowhere
/// else.
void main() {
  MediaSubtitleTrack sub({
    required int id,
    String? languageCode,
    String? language,
    String? title,
    bool forced = false,
  }) => MediaSubtitleTrack(
    id: id,
    languageCode: languageCode,
    language: language,
    title: title,
    forced: forced,
    selected: false,
  );

  MediaAudioTrack audio({required int id, String? languageCode, String? language, String? title}) =>
      MediaAudioTrack(id: id, languageCode: languageCode, language: language, title: title, selected: false);

  group('subtitleStreamLanguage', () {
    final tracks = [
      sub(id: 11, languageCode: 'nld', language: 'Dutch', title: 'Dutch (SRT)'),
      sub(id: 12, languageCode: 'eng', language: 'English'),
      sub(id: 13, languageCode: 'nld', language: 'Dutch', title: 'Dutch forced', forced: true),
    ];

    test('resolves the picked stream to its language, title and forced flag', () {
      final choice = subtitleStreamLanguage(tracks, 11);

      expect(choice, isNotNull);
      expect(choice!.language, 'nld');
      expect(choice.title, 'Dutch (SRT)');
      expect(choice.forced, isFalse);
    });

    test('keeps the forced variant apart from the ordinary one', () {
      expect(subtitleStreamLanguage(tracks, 13)!.forced, isTrue);
      expect(subtitleStreamLanguage(tracks, 13)!.language, 'nld');
    });

    test('prefers the ISO code over the display name', () {
      // "Dutch" would never match a track tagged nld, so the code has to win.
      final choice = subtitleStreamLanguage([sub(id: 1, languageCode: 'nld', language: 'Dutch')], 1);
      expect(choice!.language, 'nld');
    });

    test('falls back to the language field when no code is given', () {
      final choice = subtitleStreamLanguage([sub(id: 1, language: 'nl')], 1);
      expect(choice!.language, 'nl');
    });

    test('an untagged stream says nothing, so the previous choice is left alone', () {
      expect(subtitleStreamLanguage([sub(id: 1, title: 'Sidecar')], 1), isNull);
      expect(subtitleStreamLanguage([sub(id: 1, languageCode: '')], 1), isNull);
    });

    test('an unknown stream id resolves to nothing rather than the first track', () {
      expect(subtitleStreamLanguage(tracks, 99), isNull);
      expect(subtitleStreamLanguage(const [], 11), isNull);
    });
  });

  group('audioStreamLanguage', () {
    test('resolves the picked stream to its language and title', () {
      final choice = audioStreamLanguage([
        audio(id: 2, languageCode: 'eng', language: 'English', title: 'Surround 5.1'),
      ], 2);

      expect(choice!.language, 'eng');
      expect(choice.title, 'Surround 5.1');
      expect(choice.forced, isFalse);
    });

    test('an untagged or unknown stream resolves to nothing', () {
      expect(audioStreamLanguage([audio(id: 2)], 2), isNull);
      expect(audioStreamLanguage([audio(id: 2, languageCode: 'eng')], 5), isNull);
    });
  });

  group('Plex preferences for a remembered choice', () {
    TrackLanguageChoice choice({String? language, bool forced = false, bool off = false}) =>
        TrackLanguageChoice(subtitleLanguage: language, subtitleForced: forced, subtitlesOff: off, updatedAt: 0);

    test('a chosen language asks the show for all subtitles', () {
      final c = choice(language: 'nld');
      expect(c.plexSubtitleMode, 2);
      expect(c.plexSubtitleLanguage, 'nld');
    });

    test('a forced choice asks for forced only', () {
      expect(choice(language: 'nld', forced: true).plexSubtitleMode, 1);
    });

    test('an explicit off turns them off and clears the language', () {
      final c = choice(off: true);
      expect(c.plexSubtitleMode, 0);
      expect(c.plexSubtitleLanguage, '');
    });

    test('never having chosen leaves the show alone', () {
      final c = choice();
      expect(c.plexSubtitleMode, isNull);
    });
  });
}
