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
