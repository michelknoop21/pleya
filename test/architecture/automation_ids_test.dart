import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';

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

  test('auth exposes one closed five-id domain and only choices are instanceable', () {
    final authCatalog = AutomationIds.catalog().where((entry) {
      final id = entry['id']! as String;
      return id == AutomationIds.screenAuth || id.startsWith('auth.');
    }).toList();

    expect(authCatalog, [
      {'id': AutomationIds.screenAuth, 'role': 'screen', 'instanceable': false},
      {'id': AutomationIds.authHeading, 'role': 'heading', 'instanceable': false},
      {'id': AutomationIds.authChoice, 'role': 'button', 'instanceable': true},
      {'id': AutomationIds.authPanel, 'role': 'region', 'instanceable': false},
      {'id': AutomationIds.authRetry, 'role': 'button', 'instanceable': false},
    ]);
    expect(AutomationIds.instanceableIds.where((id) => id.startsWith('auth.')), [AutomationIds.authChoice]);
  });
}
