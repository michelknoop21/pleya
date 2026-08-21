import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/models/tautulli/tautulli_models.dart';

List<Map<String, dynamic>> _rows(String fixture) {
  final raw = jsonDecode(File('test/fixtures/tautulli/$fixture').readAsStringSync());
  return (raw['data'] as List).cast<Map<String, dynamic>>();
}

void main() {
  group('playSeconds', () {
    test('reads play_duration', () {
      final e = TautulliHistoryEntry.fromJson({'play_duration': 545, 'duration': 999, 'watched_status': 1});
      expect(e.playSeconds, 545);
      expect(e.duration, 999, reason: 'the existing field keeps its old meaning for existing callers');
    });

    test('falls back to duration when play_duration is absent', () {
      final e = TautulliHistoryEntry.fromJson({'duration': 432, 'watched_status': 0});
      expect(e.playSeconds, 432);
    });

    test('is null when neither is present', () {
      expect(TautulliHistoryEntry.fromJson({'watched_status': 0}).playSeconds, isNull);
    });

    test('every measured history row carries seconds played, not a media length', () {
      for (final fixture in ['history_movie.json', 'history_show.json']) {
        for (final row in _rows(fixture)) {
          final e = TautulliHistoryEntry.fromJson(row);
          expect(e.playSeconds, row['play_duration'], reason: '$fixture row ${row['row_id']}');
          // Inside get_history these are the same value by construction
          // (datafactory.py writes play_duration into both). The media duration
          // is not in this response at all; that is get_activity, in ms.
          expect(e.playSeconds, e.duration);
          expect(e.playSeconds, lessThan(100000), reason: 'seconds, not milliseconds');
        }
      }
    });

    test('rows with paused time are covered and still read as seconds played', () {
      // Tautulli computes this as SUM(stopped - started) - SUM(paused_counter).
      // The fixture's own started/stopped are sanitised, so the arithmetic is
      // not reproducible from it; what the capture does prove is that the value
      // is not the wall-clock span and that both keys carry it.
      final paused = _rows('history_movie.json').where((r) => (r['paused_counter'] as int? ?? 0) > 0).toList();
      expect(paused, isNotEmpty, reason: 'the fixture must still cover this case');
      for (final row in paused) {
        final e = TautulliHistoryEntry.fromJson(row);
        expect(e.playSeconds, row['play_duration']);
        expect(e.playSeconds, e.duration);
        expect(e.playSeconds, isNot((row['stopped'] as int) - (row['started'] as int)));
      }
    });
  });

  group('machineId', () {
    test('is read from machine_id', () {
      expect(TautulliHistoryEntry.fromJson({'machine_id': 'pms-1', 'watched_status': 0}).machineId, 'pms-1');
    });

    test('is null when the build does not send it', () {
      expect(TautulliHistoryEntry.fromJson({'watched_status': 0}).machineId, isNull);
    });

    test('every measured row reports the server it played on', () {
      for (final row in _rows('history_movie.json')) {
        expect(TautulliHistoryEntry.fromJson(row).machineId, isNotEmpty);
      }
    });
  });

  test('watched_status is not binary', () {
    // datafactory.py emits 0, 0.25, 0.5, 0.75 and 1 against the admin's own
    // threshold, so a completed row can sit below 85 percent.
    final belowThreshold = _rows(
      'history_movie.json',
    ).map(TautulliHistoryEntry.fromJson).where((e) => e.isWatched && e.percentComplete < 85);
    expect(belowThreshold, isNotEmpty, reason: 'the OR rule in the importer exists for these rows');
  });
}
