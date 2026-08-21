import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_source_info.dart';
import 'package:pleya/mpv/models.dart';
import 'package:pleya/utils/subtitle_track_resolver.dart';

import '../test_helpers/subtitle_fixtures.dart';

SubtitleTrackResolution resolve(List<SubtitleTrack> player, List<MediaSubtitleTrack> server) =>
    SubtitleTrackResolver.resolve(playerTracks: player, serverTracks: server);

void main() {
  group('external URI', () {
    test('a Plex sidecar URL matches its own stream key', () {
      final track = SubtitleTrack.uri('https://plex.example/library/streams/200.srt?encoding=utf-8&X-Plex-Token=abc');
      final result = resolve(
        [track],
        [
          serverSubtitle(id: 200, key: '/library/streams/200', languageCode: 'nld', codec: 'srt'),
          serverSubtitle(id: 201, key: '/library/streams/201', languageCode: 'eng', codec: 'srt'),
        ],
      );

      final entry = result.forTrack(track.id)!;
      expect(entry.strategy, SubtitleMatchStrategy.externalUri);
      expect(entry.server!.id, 200);
      expect(entry.resolvedLanguageCode, 'nl');
      expect(entry.languageFromServer, isTrue);
      expect(entry.isStorable, isTrue);
    });

    test('a shorter stream key does not match inside a longer one', () {
      final track = SubtitleTrack.uri('https://plex.example/library/streams/200.srt');
      final result = resolve(
        [track],
        [
          serverSubtitle(id: 20, key: '/library/streams/20', languageCode: 'fra'),
          serverSubtitle(id: 200, key: '/library/streams/200', languageCode: 'nld'),
        ],
      );

      expect(result.forTrack(track.id)!.server!.id, 200);
    });

    test('a Jellyfin fallback path matches by its stream index segment', () {
      final track = SubtitleTrack.uri('https://jf.example/Videos/item-1/source-1/Subtitles/3/Stream.srt');
      final result = resolve(
        [track],
        [serverSubtitle(id: 2, index: 2, languageCode: 'eng'), serverSubtitle(id: 3, index: 3, languageCode: 'nld')],
      );

      final entry = result.forTrack(track.id)!;
      expect(entry.strategy, SubtitleMatchStrategy.externalUri);
      expect(entry.resolvedLanguageCode, 'nl');
    });
  });

  group('sidecar filename', () {
    test('resolves by the exact stream id our downloader used as the filename', () {
      final track = SubtitleTrack.uri('file:///movies/Sintel_subs/200.srt');
      final result = resolve(
        [track],
        [serverSubtitle(id: 200, languageCode: 'nld'), serverSubtitle(id: 201, languageCode: 'eng')],
      );

      final entry = result.forTrack(track.id)!;
      expect(entry.strategy, SubtitleMatchStrategy.sidecarFileId);
      expect(entry.resolvedLanguageCode, 'nl');
    });

    test('a release-name filename never resolves by a digit inside it', () {
      final track = SubtitleTrack.uri('file:///tv/Show.S01E02.720p.srt');
      final result = resolve([track], [serverSubtitle(id: 2, languageCode: 'fra')]);

      expect(result.forTrack(track.id)!.server, isNull);
      expect(result.forTrack(track.id)!.resolvedLanguageCode, isNull);
    });
  });

  group('container stream index', () {
    test('an untagged Jellyfin stream resolves through ff-index', () {
      const track = SubtitleTrack(id: '2', ffIndex: 3);
      final result = resolve(
        [const SubtitleTrack(id: '1', ffIndex: 2, language: 'eng'), track],
        [serverSubtitle(id: 2, index: 2, languageCode: 'eng'), serverSubtitle(id: 3, index: 3, languageCode: 'nld')],
      );

      final entry = result.forTrack('2')!;
      expect(entry.strategy, SubtitleMatchStrategy.serverStreamIndex);
      expect(entry.resolvedLanguageCode, 'nl');
    });

    // A Plex stream id is a database key. Comparing it to an mpv ordinal would
    // match by coincidence, so mpv tracks without ff-index never reach rule 3.
    test('a Plex stream id is never compared against an mpv track id', () {
      const track = SubtitleTrack(id: '2');
      final result = resolve([track], [serverSubtitle(id: 2, languageCode: 'fra')]);

      expect(result.forTrack('2')!.strategy, isNot(SubtitleMatchStrategy.serverStreamIndex));
    });
  });

  group('unique attributes', () {
    test('a unique language and forced combination resolves without positions', () {
      const dutch = SubtitleTrack(id: '1', language: 'nld');
      const english = SubtitleTrack(id: '2', language: 'eng');
      final result = resolve(
        [dutch, english],
        [
          serverSubtitle(id: 10, languageCode: 'eng', title: 'Full'),
          serverSubtitle(id: 11, languageCode: 'nld', title: 'Volledig'),
        ],
      );

      expect(result.forTrack('1')!.server!.id, 11);
      expect(result.forTrack('2')!.server!.id, 10);
      expect(result.forTrack('1')!.strategy, SubtitleMatchStrategy.uniqueAttributes);
    });

    test('a forced and a full track of the same language stay apart', () {
      const full = SubtitleTrack(id: '1', language: 'nld');
      const forced = SubtitleTrack(id: '2', language: 'nld', isForced: true);
      final result = resolve(
        [full, forced],
        [serverSubtitle(id: 10, languageCode: 'nld', forced: true), serverSubtitle(id: 11, languageCode: 'nld')],
      );

      expect(result.forTrack('1')!.server!.id, 11);
      expect(result.forTrack('2')!.server!.id, 10);
    });
  });

  // The headline requirement: one odd list length used to reject every match
  // in the list, including the ones backed by a shared identifier.
  test('a difference in track count no longer blocks an exact match', () {
    final sidecar = SubtitleTrack.uri('https://plex.example/library/streams/200.srt');
    final result = resolve(
      [sidecar, const SubtitleTrack(id: '1'), const SubtitleTrack(id: '2')],
      [
        serverSubtitle(id: 200, key: '/library/streams/200', languageCode: 'nld'),
        serverSubtitle(id: 1, languageCode: 'eng'),
        serverSubtitle(id: 2, languageCode: 'fra'),
        serverSubtitle(id: 3, languageCode: 'deu'),
        serverSubtitle(id: 4, languageCode: 'spa'),
      ],
    );

    expect(result.alignment, isNot(SubtitleAlignmentOutcome.aligned));
    final entry = result.forTrack(sidecar.id)!;
    expect(entry.confidence, SubtitleMatchConfidence.exact);
    expect(entry.resolvedLanguageCode, 'nl');
  });

  // Genuinely ambiguous: no tags on the player side, no shared identifier, no
  // anchor to interpolate from, and the lists are different lengths so
  // position proves nothing either. Guessing here would be a coin flip
  // between three languages.
  test('two genuinely ambiguous tracks resolve to nothing at all', () {
    final result = resolve(
      [const SubtitleTrack(id: '1'), const SubtitleTrack(id: '2')],
      [
        serverSubtitle(id: 10, languageCode: 'nld'),
        serverSubtitle(id: 11, languageCode: 'eng'),
        serverSubtitle(id: 12, languageCode: 'fra'),
      ],
    );

    expect(result.alignment, SubtitleAlignmentOutcome.countMismatch);
    for (final id in ['1', '2']) {
      final entry = result.forTrack(id)!;
      expect(entry.resolvedLanguageCode, isNull, reason: id);
      expect(entry.strategy, SubtitleMatchStrategy.none, reason: id);
    }
  });

  // Equal lengths and nothing contradicting is still evidence, so an untagged
  // pair does get coupled by position. That is not a guess about language: it
  // is the same ordering assumption the container itself uses.
  test('equal-length lists still couple untagged tracks by position', () {
    final result = resolve(
      [const SubtitleTrack(id: '1'), const SubtitleTrack(id: '2')],
      [serverSubtitle(id: 10, languageCode: 'nld'), serverSubtitle(id: 11, languageCode: 'eng')],
    );

    expect(result.forTrack('1')!.resolvedLanguageCode, 'nl');
    expect(result.forTrack('2')!.resolvedLanguageCode, 'en');
    expect(result.forTrack('1')!.strategy, SubtitleMatchStrategy.positional);
  });

  test('anchors on both sides pin the untagged track between them', () {
    final result = resolve(
      [
        const SubtitleTrack(id: '1', language: 'eng', ffIndex: 10),
        const SubtitleTrack(id: '2'),
        const SubtitleTrack(id: '3', language: 'fra', ffIndex: 12),
      ],
      [
        serverSubtitle(id: 10, index: 10, languageCode: 'eng'),
        serverSubtitle(id: 11, index: 11, languageCode: 'nld'),
        serverSubtitle(id: 12, index: 12, languageCode: 'fra'),
        serverSubtitle(id: 13, index: 13, languageCode: 'deu'),
      ],
    );

    final entry = result.forTrack('2')!;
    expect(entry.resolvedLanguageCode, 'nl');
    expect(entry.confidence, SubtitleMatchConfidence.strong);
  });

  group('language contradictions', () {
    test('fre and fra are the same language, not a contradiction', () {
      final result = resolve(
        [const SubtitleTrack(id: '1', language: 'fre')],
        [serverSubtitle(id: 10, languageCode: 'fra', key: null)],
      );
      expect(result.alignment, SubtitleAlignmentOutcome.aligned);
      expect(result.forTrack('1')!.server, isNotNull);
    });

    test('an English display name now counts as evidence, in both directions', () {
      expect(
        resolve([const SubtitleTrack(id: '1', language: 'nld')], [serverSubtitle(id: 10, language: 'Dutch')]).alignment,
        SubtitleAlignmentOutcome.aligned,
      );
      expect(
        resolve([const SubtitleTrack(id: '1', language: 'eng')], [serverSubtitle(id: 10, language: 'Dutch')]).alignment,
        SubtitleAlignmentOutcome.contradiction,
      );
    });

    test('a contradicting pair is never coupled', () {
      final result = resolve(
        [const SubtitleTrack(id: '1', language: 'eng', ffIndex: 3)],
        [serverSubtitle(id: 3, index: 3, languageCode: 'nld')],
      );
      expect(result.forTrack('1')!.server, isNull);
    });
  });

  group('sidecar filename language hint', () {
    test('reads a code beside the extension when nothing else is known', () {
      final track = SubtitleTrack.uri('file:///tv/Show.S01E02.nl.srt');
      final entry = resolve([track], const []).forTrack(track.id)!;
      expect(entry.resolvedLanguageCode, 'nl');
      expect(entry.strategy, SubtitleMatchStrategy.filenameToken);
      // Inferred never reaches the preference store.
      expect(entry.isStorable, isFalse);
    });

    test('never overrides a container tag', () {
      final track = SubtitleTrack.uri('file:///tv/Show.S01E02.nl.srt', language: 'eng');
      final entry = resolve([track], const []).forTrack(track.id)!;
      expect(entry.resolvedLanguageCode, 'en');
      expect(entry.strategy, isNot(SubtitleMatchStrategy.filenameToken));
    });

    // The false positive worth naming: the show is called Dutch.
    test('a title that happens to name a language is not a language', () {
      final track = SubtitleTrack.uri('file:///movies/Dutch (2023)/Dutch.2023.srt');
      final entry = resolve([track], const []).forTrack(track.id)!;
      expect(entry.resolvedLanguageCode, isNull);
      expect(entry.strategy, SubtitleMatchStrategy.none);
    });

    test('a two-letter token only counts directly before the extension', () {
      final noise = SubtitleTrack.uri('file:///tv/Show.S01E02.it.1080p.srt');
      expect(resolve([noise], const []).forTrack(noise.id)!.resolvedLanguageCode, isNull);

      final real = SubtitleTrack.uri('file:///tv/Show.S01E02.it.srt');
      expect(resolve([real], const []).forTrack(real.id)!.resolvedLanguageCode, 'it');
    });

    test('never reads a delivery URL, whose path carries the library and title', () {
      final track = SubtitleTrack.uri('https://plex.example/library/Dutch%20Movies/nl/stream.srt');
      expect(resolve([track], const []).forTrack(track.id)!.resolvedLanguageCode, isNull);
    });
  });
}
