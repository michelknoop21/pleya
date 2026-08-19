import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// PS-3 acceptance criterion 2, as a check on the code rather than on a run.
///
/// The criterion says cross-server search must return Pleya Server results
/// alongside Plex and Jellyfin ones "without `data_aggregation_service` needing
/// a backend check". A runtime test cannot prove the absence of a branch, and a
/// branch is exactly what would be added under time pressure. So the assertion
/// is on the source: the fan-out layer does not mention a backend at all.
///
/// This is a boundary test, not a style rule. The moment that file has to know
/// which backend it is talking to, the neutral interface has stopped carrying
/// its weight, and that is worth a failing test rather than a code review.
void main() {
  const guarded = <String>['lib/services/data_aggregation_service.dart', 'lib/providers/multi_server_provider.dart'];

  for (final path in guarded) {
    test('$path branches on no backend', () {
      final source = File(path).readAsStringSync();
      final offenders = <String>[];
      for (final line in source.split('\n')) {
        final code = line.split('//').first;
        if (code.contains('MediaBackend.')) offenders.add(line.trim());
        if (code.contains('is PleyaServerClient') ||
            code.contains('is JellyfinClient') ||
            code.contains('is PlexClient')) {
          offenders.add(line.trim());
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'a backend check here means the neutral MediaServerClient surface stopped '
            'carrying its weight; fix it at the backend boundary instead',
      );
    });
  }
}
