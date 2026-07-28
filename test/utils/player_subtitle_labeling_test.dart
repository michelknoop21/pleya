import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_source_info.dart';
import 'package:pleya/mpv/mpv.dart';
import 'package:pleya/utils/player_subtitle_labeling.dart';

MediaSubtitleTrack _server({
  int id = 1,
  String? language,
  String? languageCode,
  String? title,
  String? displayTitle,
  bool external = false,
}) => MediaSubtitleTrack(
  id: id,
  language: language,
  languageCode: languageCode,
  title: title,
  displayTitle: displayTitle,
  external: external,
  selected: false,
  forced: false,
);

void main() {
  test('untagged player track borrows the language from the server', () {
    const track = SubtitleTrack(id: '1');
    final label = labelForPlayerSubtitle(
      track: track,
      visibleIndex: 0,
      playerTracks: const [track],
      serverTracks: [_server(languageCode: 'nld')],
    );

    expect(label.primary, 'Dutch');
  });

  test('placeholder titles do not win over the language', () {
    const track = SubtitleTrack(id: '1', title: 'Unknown');
    final label = labelForPlayerSubtitle(
      track: track,
      visibleIndex: 0,
      playerTracks: const [track],
      serverTracks: [_server(languageCode: 'nld', displayTitle: 'Onbekend')],
    );

    expect(label.primary, 'Dutch');
  });

  test('mismatched track counts fall back to the numbered label', () {
    const track = SubtitleTrack(id: '1');
    const other = SubtitleTrack(id: '2');
    final label = labelForPlayerSubtitle(
      track: track,
      visibleIndex: 0,
      playerTracks: const [track, other],
      serverTracks: [_server(languageCode: 'nld')],
    );

    expect(label.primary, 'Track 1');
  });

  test('position decides the match, not the order of ids', () {
    const first = SubtitleTrack(id: '1');
    const second = SubtitleTrack(id: '2');
    final servers = [_server(id: 10, languageCode: 'eng'), _server(id: 11, languageCode: 'nld')];

    expect(
      labelForPlayerSubtitle(
        track: second,
        visibleIndex: 1,
        playerTracks: const [first, second],
        serverTracks: servers,
      ).primary,
      'Dutch',
    );
  });

  test('external tracks keep their own metadata', () {
    const track = SubtitleTrack(id: '3', title: 'Mijn download', isExternal: true);
    expect(
      matchServerSubtitle(
        track: track,
        playerTracks: const [track],
        serverTracks: [_server(languageCode: 'nld')],
      ),
      isNull,
    );
    final label = labelForPlayerSubtitle(
      track: track,
      visibleIndex: 0,
      playerTracks: const [track],
      serverTracks: [_server(languageCode: 'nld')],
    );
    expect(label.primary, 'Mijn download');
  });

  test('container language still wins over the server', () {
    const track = SubtitleTrack(id: '1', language: 'eng');
    final label = labelForPlayerSubtitle(
      track: track,
      visibleIndex: 0,
      playerTracks: const [track],
      serverTracks: [_server(language: 'Dutch', languageCode: 'nld')],
    );

    expect(label.primary, 'English');
  });

  test('a contradicting pair discredits the whole alignment', () {
    // Equal counts, but the server lists the streams the other way round.
    const first = SubtitleTrack(id: '1', language: 'eng');
    const second = SubtitleTrack(id: '2');
    final servers = [_server(id: 10, languageCode: 'nld'), _server(id: 11, languageCode: 'eng')];

    // The untagged second track gets nothing rather than a wrong 'English'.
    expect(matchServerSubtitle(track: second, playerTracks: const [first, second], serverTracks: servers), isNull);
  });

  test('an English language name does not count as a contradiction', () {
    // mpv says 'nld', the server only knows the display name 'Dutch' — not
    // comparable, so the alignment must survive and the title still merge.
    const first = SubtitleTrack(id: '1', language: 'nld');
    const second = SubtitleTrack(id: '2');
    final servers = [_server(id: 10, language: 'Dutch'), _server(id: 11, languageCode: 'eng')];

    expect(matchServerSubtitle(track: second, playerTracks: const [first, second], serverTracks: servers)?.id, 11);
  });

  test('two-letter and three-letter codes for one language agree', () {
    const track = SubtitleTrack(id: '1', language: 'nl');
    expect(
      matchServerSubtitle(
        track: track,
        playerTracks: const [track],
        serverTracks: [_server(languageCode: 'nld')],
      )?.id,
      1,
    );
  });
}
