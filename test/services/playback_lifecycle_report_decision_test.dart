import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/playback_lifecycle_report_decision.dart';

PlaybackLifecycleReport _resolve({bool authorityHeld = true, bool wasPlaying = true, bool positionChanged = true}) {
  return PlaybackLifecycleReportDecision.resolve(
    authorityHeld: authorityHeld,
    wasPlaying: wasPlaying,
    positionChanged: positionChanged,
  );
}

void main() {
  group('a revoked authority writes nothing', () {
    test('not even after real progress', () {
      expect(_resolve(authorityHeld: false), PlaybackLifecycleReport.none);
    });

    test('not while playing', () {
      expect(_resolve(authorityHeld: false, wasPlaying: true, positionChanged: false), PlaybackLifecycleReport.none);
    });

    test('the revocation outranks every other reason to write', () {
      for (final wasPlaying in [true, false]) {
        for (final positionChanged in [true, false]) {
          expect(
            _resolve(authorityHeld: false, wasPlaying: wasPlaying, positionChanged: positionChanged),
            PlaybackLifecycleReport.none,
            reason: 'wasPlaying=$wasPlaying positionChanged=$positionChanged',
          );
        }
      }
    });
  });

  group('an idle player at an unchanged position writes nothing', () {
    test('the Mutiny shape: paused, nothing moved, app backgrounded', () {
      expect(_resolve(wasPlaying: false, positionChanged: false), PlaybackLifecycleReport.none);
    });
  });

  group('one final report, never more', () {
    test('was playing and the position moved', () {
      expect(_resolve(), PlaybackLifecycleReport.finalReport);
    });

    test('was paused but the user had seeked', () {
      expect(_resolve(wasPlaying: false, positionChanged: true), PlaybackLifecycleReport.finalReport);
    });

    test('was playing at an unchanged position, so the session is closed out', () {
      // Safe by construction: the report repeats a position the backend was
      // already given, so it cannot move anything backwards.
      expect(_resolve(wasPlaying: true, positionChanged: false), PlaybackLifecycleReport.finalReport);
    });
  });

  group('a background transition overtaken by the resume', () {
    // The device log that started this: 23:25:31 hidden, 23:33:27 the app comes
    // back and tvOS delivers hidden, inactive and resumed within 2 ms. The
    // queued hidden handler ran anyway and sent `stopped` to a session that was
    // playing, after which nothing was reported for the remaining 19 minutes.
    bool superseded({required int enqueued, required int latest, required bool foreground}) =>
        PlaybackLifecycleReportDecision.isTransitionSuperseded(
          enqueuedSequence: enqueued,
          latestSequence: latest,
          latestIsForeground: foreground,
        );

    test('nothing newer arrived, so the handler runs', () {
      expect(superseded(enqueued: 7, latest: 7, foreground: false), isFalse);
    });

    test('a foreground event arrived while it waited its turn, so it is skipped', () {
      expect(superseded(enqueued: 7, latest: 9, foreground: true), isTrue);
    });

    test('the app is on screen but no newer event exists, so the handler still runs', () {
      // A resume that has already been processed leaves the flag true. Only a
      // *newer* event may cancel a queued transition.
      expect(superseded(enqueued: 9, latest: 9, foreground: true), isFalse);
    });

    test('a newer event that is still background does not cancel it', () {
      // hidden followed by paused is the ordinary way out; the background work
      // must not be skipped there.
      expect(superseded(enqueued: 7, latest: 8, foreground: false), isFalse);
    });
  });

  test('the full truth table', () {
    final table = <(bool, bool, bool), PlaybackLifecycleReport>{
      (true, true, true): PlaybackLifecycleReport.finalReport,
      (true, true, false): PlaybackLifecycleReport.finalReport,
      (true, false, true): PlaybackLifecycleReport.finalReport,
      (true, false, false): PlaybackLifecycleReport.none,
      (false, true, true): PlaybackLifecycleReport.none,
      (false, true, false): PlaybackLifecycleReport.none,
      (false, false, true): PlaybackLifecycleReport.none,
      (false, false, false): PlaybackLifecycleReport.none,
    };

    table.forEach((input, expected) {
      final (authorityHeld, wasPlaying, positionChanged) = input;
      expect(
        _resolve(authorityHeld: authorityHeld, wasPlaying: wasPlaying, positionChanged: positionChanged),
        expected,
        reason: 'authorityHeld=$authorityHeld wasPlaying=$wasPlaying positionChanged=$positionChanged',
      );
    });
  });
}
