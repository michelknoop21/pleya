import 'package:flutter_test/flutter_test.dart';

import 'big_p_eval_cases.dart';

// The shape of the set itself (BP-11a2): sixty cases, each with a source and
// at least one check of its own beyond the shared base.

void main() {
  test('the set holds sixty cases with unique ids and a source each', () {
    expect(bigPEvalCases, hasLength(60));
    expect({for (final c in bigPEvalCases) c.id}, hasLength(60));
    expect(bigPEvalCases.every((c) => c.source.isNotEmpty && c.turns.isNotEmpty), isTrue);
  });

  test('every area has cases', () {
    for (final prefix in ['disc-', 'rec-', 'ser-', 'fam-', 'mem-', 'trk-', 'sea-', 'adm-', 'con-']) {
      expect(bigPEvalCases.where((c) => c.id.startsWith(prefix)), isNotEmpty, reason: prefix);
    }
  });

  test('no case rests on the shared base alone, also when run live', () {
    // The live runner ignores `scripted`, so a case needs a hard check of its own.
    const shared = {'cards-from-fixture', 'no-mutation-without-yes', 'no-duplicates'};
    // The eleven core cases of the first PR keep their own rules; this holds the new areas.
    final areas = RegExp(r'^(disc|rec|ser|fam|mem|trk|sea|adm|con)-');
    final weak = [
      for (final c in bigPEvalCases.where((c) => areas.hasMatch(c.id)))
        if (c.hard.every((h) => shared.contains(h.id))) c.id,
    ];
    expect(weak, isEmpty, reason: 'these cases only check the base');
  });
}
