import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every English key has a Dutch counterpart, in every section.
///
/// slang's `fallback_strategy: base_locale` means a key that only exists in
/// `en.i18n.json` silently renders English text in a Dutch app. Nothing
/// crashes when that happens, so only a check like this catches it — the five
/// log-upload messages shipped English-only for two builds exactly this way.
/// The seerr-specific test predates this one and stays as documentation of
/// where the pattern was first caught.
///
/// Deliberately en→nl only. The other fourteen locales are community
/// translations that trail by design; Dutch is the maintainer's own locale
/// and has no excuse to trail.
void main() {
  Map<String, dynamic> load(String locale) {
    final file = File('lib/i18n/$locale.i18n.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  List<String> missingKeys(Map<String, dynamic> base, Map<String, dynamic> other, String prefix) {
    final missing = <String>[];
    for (final entry in base.entries) {
      final path = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
      final value = entry.value;
      final counterpart = other[entry.key];
      if (value is Map<String, dynamic>) {
        if (counterpart is Map<String, dynamic>) {
          missing.addAll(missingKeys(value, counterpart, path));
        } else {
          missing.add('$path (whole section)');
        }
      } else if (counterpart == null) {
        missing.add(path);
      }
    }
    return missing;
  }

  test('every English key has a Dutch counterpart', () {
    final missing = missingKeys(load('en'), load('nl'), '');

    expect(
      missing,
      isEmpty,
      reason:
          'These keys fall back to English in the Dutch UI. Add each one to '
          'lib/i18n/nl.i18n.json and run scripts/codegen.sh.\n${missing.join('\n')}',
    );
  });
}
