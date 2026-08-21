import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/utils/track_label_builder.dart';

void main() {
  group('TrackLabel', () {
    test('joined concatenates primary and secondary with " · "', () {
      expect(const TrackLabel('Tamil', 'E-AC3 · 5.1').joined, 'Tamil · E-AC3 · 5.1');
    });

    test('joined is just primary when secondary is null', () {
      expect(const TrackLabel('Tamil').joined, 'Tamil');
    });

    test('equality compares both parts', () {
      expect(const TrackLabel('A', 'B'), const TrackLabel('A', 'B'));
      expect(const TrackLabel('A'), isNot(const TrackLabel('A', 'B')));
    });
  });

  group('resolveTrackLanguageDisplay', () {
    test('resolves 2-letter, 3-letter, and bibliographic codes', () {
      expect(resolveTrackLanguageDisplay(language: 'en'), 'English');
      expect(resolveTrackLanguageDisplay(language: 'eng'), 'English');
      expect(resolveTrackLanguageDisplay(language: 'ta'), 'Tamil');
      expect(resolveTrackLanguageDisplay(language: 'tam'), 'Tamil');
      expect(resolveTrackLanguageDisplay(language: 'ger'), 'German');
    });

    test('resolves region-qualified codes', () {
      expect(resolveTrackLanguageDisplay(language: 'en-AU'), 'English (Australia)');
      expect(resolveTrackLanguageDisplay(language: 'en-US'), 'English');
      expect(resolveTrackLanguageDisplay(language: 'pt_BR'), 'Portuguese (Brazil)');
    });

    test('prefers a mappable languageCode over the language field', () {
      expect(resolveTrackLanguageDisplay(language: 'Englisch', languageCode: 'eng'), 'English');
    });

    test('unknown bare codes keep the legacy uppercase rendering', () {
      expect(resolveTrackLanguageDisplay(language: 'und'), 'UND');
      expect(resolveTrackLanguageDisplay(languageCode: 'zxx'), 'ZXX');
    });

    test('server display names pass through unchanged', () {
      expect(resolveTrackLanguageDisplay(language: 'English'), 'English');
      // 'fil' has no ISO 639-1 entry; the server-provided name must win.
      expect(resolveTrackLanguageDisplay(language: 'Filipino', languageCode: 'fil'), 'Filipino');
    });

    test('cleans lang= metadata prefixes before resolving', () {
      expect(resolveTrackLanguageDisplay(language: 'LANG=DEU'), 'German');
    });

    test('returns null when nothing usable is provided', () {
      expect(resolveTrackLanguageDisplay(), null);
      expect(resolveTrackLanguageDisplay(language: '', languageCode: ' '), null);
    });
  });

  group('TrackLabelBuilder.audioLabel', () {
    test('language leads, title and tech detail go to the secondary line', () {
      expect(
        TrackLabelBuilder.audioLabel(
          title: 'Dolby Digital Plus 5.1 with Atmos',
          language: 'ta',
          codec: 'eac3',
          channels: 6,
          index: 0,
        ),
        const TrackLabel('Tamil', 'Dolby Digital Plus 5.1 with Atmos · E-AC3 · 5.1'),
      );
    });

    test('language with tech detail only', () {
      expect(
        TrackLabelBuilder.audioLabel(language: 'fr', codec: 'ac3', channels: 6, index: 0),
        const TrackLabel('French', 'AC3 · 5.1'),
      );
    });

    test('drops a title that restates the language', () {
      expect(
        TrackLabelBuilder.audioLabel(title: 'English', language: 'en', codec: 'aac', channels: 2, index: 0),
        const TrackLabel('English', 'AAC · Stereo'),
      );
      expect(
        TrackLabelBuilder.audioLabel(title: 'eng', language: 'eng', codec: 'aac', index: 0),
        const TrackLabel('English', 'AAC'),
      );
    });

    test('title becomes primary when there is no language', () {
      expect(
        TrackLabelBuilder.audioLabel(title: 'Commentary', codec: 'aac', channels: 2, index: 0),
        const TrackLabel('Commentary', 'AAC · Stereo'),
      );
    });

    test('displayTitle is the last-resort primary before the index fallback', () {
      expect(
        TrackLabelBuilder.audioLabel(displayTitle: 'English (EAC3 5.1)', codec: 'eac3', index: 0),
        const TrackLabel('English (EAC3 5.1)', 'E-AC3'),
      );
    });

    test('falls back to a numbered label', () {
      expect(TrackLabelBuilder.audioLabel(index: 0), const TrackLabel('Audio track 1'));
      expect(TrackLabelBuilder.audioLabel(index: 3), const TrackLabel('Audio track 4'));
      expect(TrackLabelBuilder.audioLabel(codec: 'eac3', index: 0), const TrackLabel('Audio track 1', 'E-AC3'));
    });

    test('channel counts render as layout names and invalid counts are dropped', () {
      expect(TrackLabelBuilder.audioLabel(language: 'en', channels: 1, index: 0).secondary, 'Mono');
      expect(TrackLabelBuilder.audioLabel(language: 'en', channels: 2, index: 0).secondary, 'Stereo');
      expect(TrackLabelBuilder.audioLabel(language: 'en', channels: 6, index: 0).secondary, '5.1');
      expect(TrackLabelBuilder.audioLabel(language: 'en', channels: 10, index: 0).secondary, '10ch');
      expect(TrackLabelBuilder.audioLabel(language: 'en', channels: 0, index: 0).secondary, null);
    });

    test('omits codec when null or empty', () {
      expect(TrackLabelBuilder.audioLabel(language: 'en', codec: null, index: 0), const TrackLabel('English'));
      expect(TrackLabelBuilder.audioLabel(language: 'en', codec: '', index: 0), const TrackLabel('English'));
    });
  });

  group('TrackLabelBuilder numbered fallback injection', () {
    test('a caller-supplied formatter replaces the English default', () {
      expect(
        TrackLabelBuilder.subtitleLabel(index: 1, numberLabel: (n) => 'Ondertiteling $n'),
        const TrackLabel('Ondertiteling 2'),
      );
      expect(
        TrackLabelBuilder.audioLabel(index: 0, numberLabel: (n) => 'Audiospoor $n'),
        const TrackLabel('Audiospoor 1'),
      );
    });
  });

  group('TrackLabelBuilder.subtitleLabel', () {
    test('language leads with the codec on the secondary line', () {
      expect(
        TrackLabelBuilder.subtitleLabel(language: 'en', codec: 'subrip', index: 0),
        const TrackLabel('English', 'SRT'),
      );
      expect(
        TrackLabelBuilder.subtitleLabel(language: 'de', codec: 'hdmv_pgs_subtitle', index: 0),
        const TrackLabel('German', 'PGS'),
      );
    });

    test('forced flag renders as a primary suffix', () {
      expect(
        TrackLabelBuilder.subtitleLabel(language: 'en', codec: 'subrip', forced: true, index: 0),
        const TrackLabel('English (Forced)', 'SRT'),
      );
    });

    test('a bare "Forced" title is folded into the suffix instead of repeating', () {
      expect(
        TrackLabelBuilder.subtitleLabel(title: 'Forced', language: 'en', codec: 'subrip', forced: true, index: 0),
        const TrackLabel('English (Forced)', 'SRT'),
      );
      expect(
        TrackLabelBuilder.subtitleLabel(title: 'Forced', language: 'en', codec: 'subrip', index: 0),
        const TrackLabel('English (Forced)', 'SRT'),
      );
    });

    test('no duplicate suffix when the title-primary already says forced', () {
      expect(
        TrackLabelBuilder.subtitleLabel(title: 'Signs Forced', codec: 'ass', forced: true, index: 0),
        const TrackLabel('Signs Forced', 'ASS'),
      );
    });

    test('descriptive titles stay on the secondary line, even when language-prefixed', () {
      expect(
        TrackLabelBuilder.subtitleLabel(title: 'English (SDH)', language: 'en', codec: 'subrip', index: 0),
        const TrackLabel('English', 'English (SDH) · SRT'),
      );
    });

    test('drops a title that restates the language', () {
      expect(
        TrackLabelBuilder.subtitleLabel(title: 'English', language: 'en', codec: 'subrip', index: 0),
        const TrackLabel('English', 'SRT'),
      );
    });

    test('falls back to a numbered label, keeping the forced suffix', () {
      expect(TrackLabelBuilder.subtitleLabel(index: 0), const TrackLabel('Subtitle 1'));
      expect(TrackLabelBuilder.subtitleLabel(forced: true, index: 1), const TrackLabel('Subtitle 2 (Forced)'));
    });

    test('displayTitle fallback is codec-stripped like a title', () {
      expect(
        TrackLabelBuilder.subtitleLabel(displayTitle: 'Japanese Signs/Songs - ASS', codec: 'ass', index: 0),
        const TrackLabel('Japanese Signs/Songs', 'ASS'),
      );
    });

    test('cleans raw Jellyfin/ExoPlayer subtitle metadata prefixes', () {
      expect(
        TrackLabelBuilder.subtitleLabel(title: 'title=German - SUBRIP', language: 'LANG=DEU', codec: 'srt', index: 0),
        const TrackLabel('German', 'SRT'),
      );
      expect(
        TrackLabelBuilder.subtitleLabel(
          title: 'title=English - Default - SUBRIP',
          language: 'LANG=ENG',
          codec: 'subrip',
          index: 1,
        ),
        const TrackLabel('English', 'English - Default · SRT'),
      );
    });
  });
}
