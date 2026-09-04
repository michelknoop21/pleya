import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `tool/generate_automation_ids_yaml.dart` runs on the standalone Dart VM,
/// and that VM cannot compile the Flutter framework: its FFI use-site
/// transformer throws
///
/// ```
/// Crash when compiling:
/// type 'InvalidType' is not a subtype of type 'FunctionType' in type cast
/// #0 _FfiUseSiteTransformer._verifyAndReplaceNativeCallable
/// ```
///
/// on any program that reaches `package:flutter`, this package's own code or
/// not — a bare script whose only line is `import 'package:flutter/material.dart';`
/// crashes it too. Nothing in this repository can fix that, so the generator
/// stays out of its way instead: `automation_ids.dart` names a tab through
/// `navigation_tab_id.dart` rather than through the widget file that also
/// declares it.
///
/// That is a quiet property. One `import 'package:flutter/material.dart';`
/// added to any file on this path takes the generator away again, the failure
/// appears at the far end as a compiler crash with no mention of the import
/// that caused it, and the next person edits the generated yaml by hand and
/// gives the catalogue a second source of truth. This test names the property
/// so the failure arrives here instead.
void main() {
  test('the automation-id generator reaches Flutter through nothing', () {
    final visited = <String>{};
    final queue = <String>['tool/generate_automation_ids_yaml.dart'];
    final offenders = <String>[];

    while (queue.isNotEmpty) {
      final path = queue.removeLast();
      if (!visited.add(path)) continue;
      final file = File(path);
      if (!file.existsSync()) continue;

      for (final line in file.readAsLinesSync()) {
        final match = RegExp("^\\s*(?:import|export)\\s+'([^']+)'").firstMatch(line);
        final target = match?.group(1);
        if (target == null) continue;

        if (target.startsWith('package:flutter') || target == 'dart:ui') {
          offenders.add('$path imports $target');
          continue;
        }
        // Anything else outside this package is a pub dependency we do not
        // walk; a pure-Dart one is fine and a Flutter one would fail loudly
        // when the generator runs, which the next expectation covers.
        if (target.startsWith('dart:')) continue;
        if (target.startsWith('package:pleya/')) {
          queue.add('lib/${target.substring('package:pleya/'.length)}');
          continue;
        }
        if (target.startsWith('package:')) continue;
        queue.add(Uri.parse(path).resolve(target).path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'The generator compiles on the standalone Dart VM, which cannot compile Flutter. '
          'Move whatever is needed into a Flutter-free file, the way '
          'lib/navigation/navigation_tab_id.dart holds NavigationTabId apart from '
          'lib/navigation/navigation_tabs.dart.',
    );
    // A cheap sanity check on the walk itself: if the resolver silently found
    // nothing, an empty offender list would prove nothing at all.
    expect(visited, contains('lib/automation/automation_ids.dart'));
    expect(visited, contains('lib/navigation/navigation_tab_id.dart'));
  });
}
