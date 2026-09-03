import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/utils/platform_detector.dart';

/// Hoofdstuk 32's release boundary — "de oude TV-shell en ontwikkelpoort zijn
/// vóór productie verwijderd" — and hoofdstuk 30's stop criterion for the
/// *permanent dubbele architectuur* risk: "releasebuild bevat nog een
/// eindgebruikersschakelaar tussen beide shells".
///
/// Fase 0 shipped `DevFlags.tvUnifiedExperience` as a debug-only gate so the
/// unified shell could be flipped on locally while it was being built
/// ([DEC-063](../../docs/DECISIONS.md#dec-063)). Fase 10A removes it. What is
/// worth guarding afterwards is not that one identifier — it is the shape the
/// gate had: *anything* that lets a build choose between the rail shell and
/// the TV shell.
///
/// Two halves, because either alone would pass while the risk was live:
///
///  * **source-level**, so a reintroduced gate fails here rather than in a
///    screenshot nobody takes on a release build;
///  * **behavioural**, so the branch order in `MainScreen` is proven to be
///    load-bearing rather than assumed. A TV is *also* a
///    `shouldUseSideNavigation` surface — it was one until fase 7 — so the two
///    branches genuinely overlap, and the only thing keeping a TV off the rail
///    is that `_isTvShell` is asked first.
String _source(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path moved; update this test rather than deleting it');
  return file.readAsStringSync();
}

/// Source lines that are not comments or blank. A gate hiding in a doc comment
/// is documentation; a gate in code is a gate.
Iterable<String> _codeLines(String source) sync* {
  var inBlockComment = false;
  for (final raw in source.split('\n')) {
    final line = raw.trim();
    if (inBlockComment) {
      if (line.contains('*/')) inBlockComment = false;
      continue;
    }
    if (line.startsWith('/*')) {
      if (!line.contains('*/')) inBlockComment = true;
      continue;
    }
    if (line.isEmpty || line.startsWith('//')) continue;
    yield line;
  }
}

List<File> _libDartFiles() => Directory(
  'lib',
).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')).toList(growable: false);

void main() {
  group('the development gate is gone', () {
    test('the fase-0 gate file no longer exists', () {
      // Deliberately a path assertion and not a symbol one: `lib/config/` held
      // nothing but this file, so a reappearing directory is the signal.
      expect(
        File('lib/config/dev_flags.dart').existsSync(),
        isFalse,
        reason: 'hoofdstuk 32: the development gate is removed before production',
      );
    });

    test('no production file names the gate or its flag', () {
      final offenders = <String>[];
      for (final file in _libDartFiles()) {
        for (final line in _codeLines(file.readAsStringSync())) {
          if (line.contains('DevFlags') || line.contains('tvUnifiedExperience')) {
            offenders.add('${file.path}: $line');
          }
        }
      }
      expect(offenders, isEmpty, reason: 'the unified-TV development gate is back in production code');
    });

    test('Settings offers no switch between the two shells', () {
      // The gate's only surface was a row in the Debug section. The section
      // itself stays — Test Sentry and Test ANR live there — so this asserts
      // the absence of the *shell* control, not of the section.
      final settings = _source('lib/screens/settings/settings_screen.dart');
      for (final line in _codeLines(settings)) {
        expect(line, isNot(contains('Unified TV')), reason: 'hoofdstuk 30: no end-user switch between both shells');
      }
    });
  });

  group('one root navigation authority', () {
    test('MainScreen resolves the TV shell before the side-navigation branch', () {
      // Hoofdstuk 6.2: "one root navigation authority, never a rail and a bar
      // at once". Order is the whole mechanism, so order is what is asserted.
      final source = _source('lib/screens/main_screen.dart');
      final tvBranch = source.indexOf('if (_isTvShell) return _buildTvShell(context);');
      final railBranch = source.indexOf('if (useSideNav) {');
      expect(
        tvBranch,
        greaterThanOrEqualTo(0),
        reason: 'the TV branch moved; update this test rather than deleting it',
      );
      expect(
        railBranch,
        greaterThanOrEqualTo(0),
        reason: 'the rail branch moved; update this test rather than deleting it',
      );
      expect(
        tvBranch,
        lessThan(railBranch),
        reason: 'a TV would fall into the rail shell: the TV branch must be asked first',
      );
    });

    testWidgets('negative control: a TV is still a side-navigation surface, so that order carries weight', (
      tester,
    ) async {
      // If this ever goes false the ordering assertion above becomes vacuous —
      // it would be passing because the branches no longer overlap, not
      // because the shell is chosen correctly. That is exactly the kind of
      // silently-toothless guard this pair exists to prevent.
      TvDetectionService.debugSetAppleTVOverride(true);
      addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

      late bool sideNav;
      late bool isTv;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              sideNav = PlatformDetector.shouldUseSideNavigation(context);
              isTv = PlatformDetector.isTV();
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(isTv, isTrue);
      expect(sideNav, isTrue, reason: 'the two MainScreen branches must still overlap for their order to matter');
    });
  });
}
