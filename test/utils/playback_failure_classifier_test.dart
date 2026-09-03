import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/utils/playback_failure_classifier.dart';

void main() {
  group('classifyPlaybackFailure file availability', () {
    // The line ffmpeg logs when a Plex part points at a file the server can
    // no longer read — the unmounted-external-drive case.
    test('a 404 on the media file itself reads as a missing file', () {
      expect(
        classifyPlaybackFailure('https://server/library/parts/9815/file.mkv: HTTP error 404 Not Found'),
        PlaybackFailureKind.fileUnavailable,
      );
    });

    test('an OS-level missing file reads as a missing file', () {
      expect(
        classifyPlaybackFailure('Failed to open /mnt/media/movie.mkv: No such file or directory'),
        PlaybackFailureKind.fileUnavailable,
      );
    });

    test('a 404 on an HLS segment stays a segment problem, not a missing file', () {
      expect(
        classifyPlaybackFailure('https://server/video/:/transcode/segment-00012.ts: HTTP error 404 Not Found'),
        PlaybackFailureKind.segmentUnavailable,
      );
    });

    test('a 404 on the playlist stays a segment problem', () {
      expect(classifyPlaybackFailure('index.m3u8: HTTP error 404 Not Found'), PlaybackFailureKind.segmentUnavailable);
    });

    test('server errors still outrank a missing file', () {
      expect(classifyPlaybackFailure('HTTP error 500 Internal Server Error'), PlaybackFailureKind.serverError);
    });

    test('an unreadable codec is not mistaken for a missing file', () {
      expect(classifyPlaybackFailure('Could not open codec: unsupported'), PlaybackFailureKind.codecUnsupported);
    });

    test('connection failures keep their own bucket', () {
      expect(classifyPlaybackFailure('Connection refused'), PlaybackFailureKind.connectionLost);
    });

    test('an unrecognised line stays unknown', () {
      expect(classifyPlaybackFailure('Something else entirely'), PlaybackFailureKind.unknown);
    });

    // The player joins its last few error lines before classifying, because
    // ffmpeg logs the 404 and mpv then logs a generic failure over it.
    test('a joined multi-line log still finds the 404 under the generic line', () {
      const joined =
          'https://server/library/parts/1/file.mkv: HTTP error 404 Not Found\n'
          'Failed to open https://server/library/parts/1/file.mkv.';
      expect(classifyPlaybackFailure(joined), PlaybackFailureKind.fileUnavailable);
    });
  });

  test('a missing .ts library file is the file, not an HLS segment', () {
    // `.ts` is both an HLS segment extension and an ordinary container for a
    // recorded broadcast. Treating it as HLS on its own made an unmounted
    // disk read as "the transcoder is behind" — the exact case DEC-078 added
    // the file-unavailable wording for.
    expect(
      classifyPlaybackFailure('Failed to open /Volumes/NAS/Nieuws 20-00.ts: No such file or directory'),
      PlaybackFailureKind.fileUnavailable,
    );
    // A real segment failure still reads as one: it names the playlist or the
    // segment it came from.
    expect(
      classifyPlaybackFailure('HTTP 404 loading segment 42.ts from stream.m3u8'),
      PlaybackFailureKind.segmentUnavailable,
    );
  });
}
