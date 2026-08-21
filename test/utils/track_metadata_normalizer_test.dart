import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/utils/track_metadata_normalizer.dart';

void main() {
  group('normalizeLanguageCode', () {
    test('collapses every ISO revision of the same language', () {
      for (final raw in ['nl', 'nld', 'dut', 'NL', ' nld ', 'nl-BE', 'nl_BE']) {
        expect(normalizeLanguageCode(raw), 'nl', reason: raw);
      }
      // 639-2/B and 639-2/T for French, which a prefix comparison misses.
      expect(normalizeLanguageCode('fre'), normalizeLanguageCode('fra'));
      expect(normalizeLanguageCode('fre'), 'fr');
    });

    test('accepts an English display name, which is all Plex sends', () {
      expect(normalizeLanguageCode('Dutch'), 'nl');
      expect(normalizeLanguageCode('english'), 'en');
    });

    test('strips the metadata-key prefixes some backends emit', () {
      expect(normalizeLanguageCode('lang=nld'), 'nl');
      expect(normalizeLanguageCode('language="Dutch"'), 'nl');
    });

    test('refuses to guess', () {
      for (final raw in [null, '', '   ', 'und', 'zxx', 'mul', 'mis', 'unknown', 'Signs & Songs']) {
        expect(normalizeLanguageCode(raw), isNull, reason: '$raw');
      }
    });
  });

  group('normalizeSubtitleCodec', () {
    test('folds the aliases that mean one format', () {
      expect(normalizeSubtitleCodec('subrip'), normalizeSubtitleCodec('SRT'));
      expect(normalizeSubtitleCodec('ssa'), normalizeSubtitleCodec('ass'));
      expect(normalizeSubtitleCodec('hdmv_pgs_subtitle'), normalizeSubtitleCodec('pgs'));
      expect(normalizeSubtitleCodec('dvd_subtitle'), normalizeSubtitleCodec('vobsub'));
    });

    test('passes an unknown codec through instead of dropping it', () {
      expect(normalizeSubtitleCodec('eia_608'), 'eia_608');
      expect(normalizeSubtitleCodec(null), isNull);
    });
  });

  group('normalizeTrackTitle', () {
    test('drops the codec suffix and the forced marker', () {
      expect(normalizeTrackTitle('Japanese Signs/Songs - ASS', codec: 'ass'), 'japanese signs songs');
      expect(normalizeTrackTitle('Dutch (Forced)', languageCode: 'nl'), isNull);
    });

    test('drops a title that only restates the language', () {
      expect(normalizeTrackTitle('Dutch', languageCode: 'nl'), isNull);
      expect(normalizeTrackTitle('Full', languageCode: 'nl'), 'full');
    });

    test('returns null for placeholders and empties', () {
      for (final raw in [null, '', 'unknown', 'No title']) {
        expect(normalizeTrackTitle(raw), isNull, reason: '$raw');
      }
    });
  });
}
