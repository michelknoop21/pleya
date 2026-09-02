import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';

/// `pleya_verify/automation_ids.yaml` is a generated artefact
/// (`tool/generate_automation_ids_yaml.dart`), not a second source of truth.
/// This test fails the moment it drifts from `AutomationIds.catalog()` —
/// the id a scenario-author or the runner (Fase 6) would read — rather than
/// letting the two lists disagree silently.
void main() {
  test('pleya_verify/automation_ids.yaml matches AutomationIds.catalog()', () {
    final file = File('pleya_verify/automation_ids.yaml');
    expect(
      file.existsSync(),
      isTrue,
      reason:
          'pleya_verify/automation_ids.yaml is missing. Regenerate with '
          'dart run tool/generate_automation_ids_yaml.dart',
    );

    final parsed = <Map<String, Object?>>[];
    String? id;
    String? role;
    for (final rawLine in file.readAsLinesSync()) {
      final line = rawLine.trim();
      if (line.startsWith('#') || line.isEmpty || line == 'ids:') continue;
      if (line.startsWith('- id:')) {
        id = line.substring('- id:'.length).trim();
      } else if (line.startsWith('role:')) {
        role = line.substring('role:'.length).trim();
      } else if (line.startsWith('instanceable:')) {
        final instanceable = line.substring('instanceable:'.length).trim() == 'true';
        parsed.add({'id': id, 'role': role, 'instanceable': instanceable});
      } else {
        fail('Unrecognized line in pleya_verify/automation_ids.yaml: "$rawLine"');
      }
    }

    expect(
      parsed,
      equals(AutomationIds.catalog()),
      reason:
          'pleya_verify/automation_ids.yaml is out of sync with AutomationIds.catalog(). '
          'Regenerate with: dart run tool/generate_automation_ids_yaml.dart',
    );
  });
}
