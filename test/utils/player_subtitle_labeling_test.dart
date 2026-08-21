import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_source_info.dart';
import 'package:pleya/mpv/mpv.dart';
import 'package:pleya/utils/app_logger.dart';
import 'package:pleya/utils/player_subtitle_labeling.dart';
import 'package:pleya/utils/subtitle_track_resolver.dart';
import 'package:pleya/utils/track_label_builder.dart';

import '../test_helpers/subtitle_fixtures.dart';

TrackLabel label(SubtitleTrack track, int index, List<SubtitleTrack> player, List<MediaSubtitleTrack> server) =>
    labelForPlayerSubtitle(track: track, visibleIndex: index, playerTracks: player, serverTracks: server);

class _RecordingOutput extends LogOutput {
  final lines = <String>[];

  @override
  void output(OutputEvent event) => lines.addAll(event.lines);
}

void main() {
  setUp(() {
    SubtitleLabeling.resetCachesForTest();
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  group('enrichment', () {
    // The bug this whole resolver exists for: mpv reports the sidecar with no
    // language at all, so the label used to read "Track 1".
    test('an external Dutch SRT with no container language borrows the server language', () {
      final track = SubtitleTrack.uri('https://plex.example/library/streams/200.srt?encoding=utf-8');
      final server = [serverSubtitle(id: 200, key: '/library/streams/200', languageCode: 'nld', codec: 'srt')];

      expect(label(track, 0, [track], server).primary, 'Dutch');
    });

    test('an untagged embedded track borrows a uniquely indexed server language', () {
      const track = SubtitleTrack(id: '2', ffIndex: 3);
      final player = [const SubtitleTrack(id: '1', ffIndex: 2, language: 'eng'), track];
      final server = [
        serverSubtitle(id: 2, index: 2, languageCode: 'eng'),
        serverSubtitle(id: 3, index: 3, languageCode: 'nld'),
      ];

      expect(label(track, 1, player, server).primary, 'Dutch');
    });

    test('a container tag still wins over the server', () {
      const track = SubtitleTrack(id: '1', language: 'nld', ffIndex: 3);
      final server = [serverSubtitle(id: 3, index: 3, languageCode: 'nld', displayTitle: 'Dutch (SRT)')];

      expect(label(track, 0, [track], server).primary, 'Dutch');
    });

    test('a count mismatch no longer blocks an exact match', () {
      final track = SubtitleTrack.uri('https://plex.example/library/streams/200.srt');
      final server = [
        serverSubtitle(id: 200, key: '/library/streams/200', languageCode: 'nld'),
        serverSubtitle(id: 1, languageCode: 'eng'),
        serverSubtitle(id: 2, languageCode: 'fra'),
      ];

      expect(label(track, 0, [track], server).primary, 'Dutch');
    });

    test('external tracks keep their own metadata', () {
      final track = SubtitleTrack.uri('https://plex.example/library/streams/200.srt', title: 'Mijn download');
      final server = [serverSubtitle(id: 200, key: '/library/streams/200', languageCode: 'nld')];

      expect(label(track, 0, [track], server).primary, 'Dutch');
      expect(label(track, 0, [track], server).secondary, 'Mijn download');
    });
  });

  group('numbered fallback', () {
    final ambiguous = [const SubtitleTrack(id: '1'), const SubtitleTrack(id: '2')];
    final server = [
      serverSubtitle(id: 10, languageCode: 'nld'),
      serverSubtitle(id: 11, languageCode: 'eng'),
      serverSubtitle(id: 12, languageCode: 'fra'),
    ];

    test('two genuinely ambiguous tracks stay numbered, in English', () {
      expect(label(ambiguous[0], 0, ambiguous, server).primary, 'Subtitle 1');
      expect(label(ambiguous[1], 1, ambiguous, server).primary, 'Subtitle 2');
    });

    test('and in Dutch', () async {
      await LocaleSettings.setLocale(AppLocale.nl);
      addTearDown(() => LocaleSettings.setLocaleSync(AppLocale.en));
      SubtitleLabeling.resetCachesForTest();

      expect(label(ambiguous[0], 0, ambiguous, server).primary, 'Ondertiteling 1');
      expect(label(ambiguous[1], 1, ambiguous, server).primary, 'Ondertiteling 2');
    });

    test('a resolved Dutch track reads Nederlands in Dutch', () async {
      await LocaleSettings.setLocale(AppLocale.nl);
      addTearDown(() => LocaleSettings.setLocaleSync(AppLocale.en));
      SubtitleLabeling.resetCachesForTest();

      final track = SubtitleTrack.uri('https://plex.example/library/streams/200.srt');
      final srv = [serverSubtitle(id: 200, key: '/library/streams/200', languageCode: 'nld')];
      expect(label(track, 0, [track], srv).primary, 'Nederlands');
    });
  });

  group('diagnostics', () {
    late _RecordingOutput output;
    late Logger original;

    setUp(() {
      original = appLogger;
      output = _RecordingOutput();
      appLogger = Logger(printer: SimplePrinter(printTime: false), output: output, level: Level.info);
    });

    tearDown(() => appLogger = original);

    test('names the strategy that won for each track', () {
      final track = SubtitleTrack.uri('https://plex.example/library/streams/200.srt');
      logSubtitleLabelingDiagnostics(
        surface: 'test',
        playerTracks: [track],
        serverTracks: [serverSubtitle(id: 200, key: '/library/streams/200', languageCode: 'nld')],
      );

      final line = output.lines.join('\n');
      expect(line, contains('#uri:exact'));
      expect(line, contains('strategies=uri:1'));
      expect(line, contains('resolved=1/1'));
      expect(line, contains('enriched=1'));
    });

    test('never carries a path, a URL, a key or a filename token', () {
      const uri = 'https://plex.example/library/streams/200.srt?X-Plex-Token=secrettoken';
      const localUri = 'file:///Volumes/Media/Series/Show/Show.S01E02.nl.srt';
      logSubtitleLabelingDiagnostics(
        surface: 'test',
        playerTracks: [SubtitleTrack.uri(uri), SubtitleTrack.uri(localUri)],
        serverTracks: [serverSubtitle(id: 200, key: '/library/streams/200', languageCode: 'nld')],
      );

      final line = output.lines.join('\n');
      expect(line, isNotEmpty);
      for (final secret in [
        uri,
        localUri,
        'secrettoken',
        'plex.example',
        '/library/streams/200',
        '/Volumes/Media',
        'Show.S01E02',
      ]) {
        expect(line, isNot(contains(secret)), reason: secret);
      }
      // The key is still reported, but only as a flag.
      expect(line, contains('/key'));
    });

    test('a repeated identical picture is logged once', () {
      for (var i = 0; i < 3; i++) {
        logSubtitleLabelingDiagnostics(
          surface: 'test',
          playerTracks: [const SubtitleTrack(id: '1', language: 'nld')],
          serverTracks: [serverSubtitle(id: 1, languageCode: 'nld')],
        );
      }
      expect(output.lines.where((l) => l.contains('subtitle-labeling')), hasLength(1));
    });
  });

  group('alignment diagnosis', () {
    test('reports no server data when the server list is empty', () {
      expect(
        diagnoseSubtitleAlignment([const SubtitleTrack(id: '1')], const []),
        SubtitleAlignmentOutcome.noServerData,
      );
    });

    test('reports a count mismatch when the embedded lists differ in length', () {
      expect(
        diagnoseSubtitleAlignment([const SubtitleTrack(id: '1')], [serverSubtitle(id: 1), serverSubtitle(id: 2)]),
        SubtitleAlignmentOutcome.countMismatch,
      );
    });

    test('reports a contradiction when a tagged pair disagrees', () {
      expect(
        diagnoseSubtitleAlignment(
          [const SubtitleTrack(id: '1', language: 'fre')],
          [serverSubtitle(id: 1, languageCode: 'nld')],
        ),
        SubtitleAlignmentOutcome.contradiction,
      );
    });

    test('an English display name agrees with a matching code', () {
      expect(
        diagnoseSubtitleAlignment(
          [const SubtitleTrack(id: '1', language: 'nld')],
          [serverSubtitle(id: 1, language: 'Dutch')],
        ),
        SubtitleAlignmentOutcome.aligned,
      );
    });
  });
}
