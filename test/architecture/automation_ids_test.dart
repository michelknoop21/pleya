import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every automation ID is either a literal `static const`/method on
/// [AutomationIds] (`lib/automation/automation_ids.dart`), or its output —
/// never a raw string literal built at the call site. A hand-typed literal
/// can drift from the enum/registry it should be deriving from (see
/// `AutomationIds.navTab`) and is invisible to a refactor that renames the
/// thing it identifies.
///
/// Genuinely one-off ids can be listed in [_allowed] with a reason.
void main() {
  const allowed = <String, String>{
    // Defines AutomationIds itself.
    'lib/automation/automation_ids.dart': 'defines the automation-id namespace',
  };

  test('no raw automationId string literals outside automation_ids.dart', () {
    final pattern = RegExp(r'automationId:\s*[\x27"]');
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart') || entity.path.endsWith('.freezed.dart')) continue;
      final relative = entity.path.replaceAll(r'\', '/');
      if (allowed.containsKey(relative)) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) {
          offenders.add('$relative:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Use a static member on AutomationIds (lib/automation/automation_ids.dart) instead of a raw '
          'string literal, or add the file to the allowlist in this test with a reason.\n${offenders.join('\n')}',
    );
  });
}
