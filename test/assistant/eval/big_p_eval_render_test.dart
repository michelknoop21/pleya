// BP-12 A6: the eval records as the user sees them. The always-on tests
// prove the display checks on hand-written records, with a negative control
// per check. With a JSONL of records the last turn of each is drawn on
// phone, iPad and TV, saved and checked:
//   BIG_P_EVAL_RENDER=build/big_p_eval/live-x.jsonl flutter test test/assistant/eval/big_p_eval_render_test.dart
// Narrow with BIG_P_EVAL_RENDER_LIMIT=<n> and BIG_P_EVAL_RENDER_CASE=<prefix>.
// Shots land in build/big_p_eval/shots/, the verdicts in build/big_p_eval/render.jsonl.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';

import '../../test_helpers/golden.dart';
import '../../test_helpers/tv_catalog_artwork.dart';
import 'big_p_eval_render.dart';

Map<String, Object?> _turn(String answer, List<(String, int)> grid, {String end = 'answered'}) => {
  'prompt': 'Een film voor vanavond?',
  'text': answer,
  'answer_shown': answer,
  'end': end,
  'displays': [
    if (grid.isNotEmpty)
      {
        'type': 'grid',
        'cards': [
          for (final (title, year) in grid) {'title': title, 'year': year, 'kind': 'movie'},
        ],
      },
  ],
  'actions': <Object?>[],
};

final _good = _turn('Kijk vanavond «Coco» (2017). Of kies een van de andere twee.', [
  ('Coco', 2017),
  ('Paddington', 2014),
  ('Shrek', 2001),
]);

final _badMarkup = _turn('Kijk **dit eens <tool_call>{"name": "search_catalog"}', []);

final _badCards = _turn('Kijk «Coco» of anders «Nachtwacht Express» vanavond.', [
  ('Coco', 2017),
  ('Coco', 2017),
  ('De ${'heel erg lange en nooit eindigende ' * 6}titel', 2020),
]);

String _safe(Object? s) => '$s'.replaceAll(RegExp(r'[:/\\\s]'), '-');

void main() {
  final path = Platform.environment['BIG_P_EVAL_RENDER'] ?? '';

  setUpAll(() async {
    await loadAppFontsForGoldens();
    await LocaleSettings.setLocale(AppLocale.nl);
    TvGoldenArtwork.install();
  });
  tearDownAll(TvGoldenArtwork.remove);

  testWidgets('a good record shows on phone, iPad and TV without a violation', (tester) async {
    expect(await evalRenderViolations(tester, _good), isEmpty);
  });

  testWidgets('markup in the answer is seen on every surface', (tester) async {
    final v = await evalRenderViolations(tester, _badMarkup);
    for (final s in EvalSurface.values) {
      expect(v.where((x) => x.startsWith('markup: ') && x.endsWith('@${s.name}')), isNotEmpty, reason: '$v');
    }
  });

  testWidgets('a cut title, a double card and a title without a card are seen', (tester) async {
    final v = await evalRenderViolations(tester, _badCards);
    expect(v.where((x) => x.startsWith('duplicate-card: Coco (2017)')), hasLength(1), reason: '$v');
    for (final s in EvalSurface.values) {
      expect(v, contains('text-names-uncarded: «Nachtwacht Express» @${s.name}'));
      expect(v.where((x) => x.startsWith('truncated-title: "De heel') && x.endsWith('@${s.name}')), isNotEmpty);
    }
    expect(v.where((x) => x.contains('«Coco»')), isEmpty, reason: 'Coco has a card');
  });

  testWidgets('a run that ended without an answer shows the error state', (tester) async {
    final r = await evalRenderTurn(tester, _turn('', [], end: 'stepLimit'), EvalSurface.phone);
    expect(r.violations, isEmpty);
    expect(r.headline, isNotNull, reason: "Pleya's own reason is the headline");
  });

  testWidgets('an unknown display type is reported, not drawn', (tester) async {
    final turn = _turn('Hoe oud zijn de kinderen?', [])
      ..['displays'] = [
        {'type': 'AssistantKidsAgesPrompt'},
      ];
    final r = await evalRenderTurn(tester, turn, EvalSurface.phone);
    expect(r.violations, ['unrendered: display type AssistantKidsAgesPrompt is not rebuilt']);
  });

  testWidgets(
    'renders the records of BIG_P_EVAL_RENDER and records what it sees',
    skip: path.isEmpty,
    timeout: Timeout.none,
    (tester) async {
      final only = Platform.environment['BIG_P_EVAL_RENDER_CASE'] ?? '';
      final limit = int.tryParse(Platform.environment['BIG_P_EVAL_RENDER_LIMIT'] ?? '');
      final records = [
        for (final line in File(path).readAsLinesSync())
          if (line.trim().isNotEmpty) (jsonDecode(line) as Map).cast<String, Object?>(),
      ].where((r) => r['infra_error'] != true && '${r['case']}'.startsWith(only) && (r['turns'] as List).isNotEmpty);
      final shots = Directory('build/big_p_eval/shots')..createSync(recursive: true);
      final manifest = <String>[];
      final verdicts = <String>[];
      for (final r in limit == null ? records : records.take(limit)) {
        final id = {'case': r['case'], 'model': r['model'], 'attempt': r['attempt']};
        final violations = await evalRenderViolations(
          tester,
          ((r['turns'] as List).last as Map).cast<String, Object?>(),
          png: (surface) {
            final file = File('${shots.path}/${id.values.map(_safe).join('__')}__${surface.name}.png');
            manifest.add(jsonEncode({...id, 'size': surface.name, 'file': file.path}));
            return file;
          },
        );
        verdicts.add(jsonEncode({...id, 'display_ok': violations.isEmpty, 'display_violations': violations}));
      }
      File('${shots.path}/manifest.jsonl').writeAsStringSync(manifest.map((l) => '$l\n').join());
      File('build/big_p_eval/render.jsonl').writeAsStringSync(verdicts.map((l) => '$l\n').join());
      // Violations are findings here, not a failed test.
      printOnFailure('${verdicts.length} records rendered');
    },
  );
}
