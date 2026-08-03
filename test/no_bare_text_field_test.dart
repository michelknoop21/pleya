import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A bare [TextField]/[TextFormField] is invisible to the TV on-screen
/// keyboard machinery: on a TV there is no way to type into it at all. That is
/// how the Pleya Share host field and the local-folder name field shipped
/// unusable with a remote. Use `FocusableTextField` / `FocusableTextFormField`
/// from `lib/focus/focusable_text_field.dart` instead.
///
/// Genuinely TV-irrelevant fields can be listed in [_allowed] with a reason.
void main() {
  const allowed = <String, String>{
    // The focusable wrappers are implemented in terms of the raw widgets.
    'lib/focus/focusable_text_field.dart': 'defines the focusable wrappers',
    // Mobile-only invisible capture field behind a custom PIN pad; the TV
    // layout of this dialog is a separate, fully focusable widget tree.
    'lib/screens/profile/pin_entry_dialog.dart': 'mobile-only hidden PIN capture field',
  };

  test('no bare TextField/TextFormField outside the focusable wrappers', () {
    final pattern = RegExp(r'(?<![A-Za-z])(TextField|TextFormField)\s*\(');
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
          'Use FocusableTextField/FocusableTextFormField so the field works with a TV remote, '
          'or add the file to the allowlist in this test with a reason.\n${offenders.join('\n')}',
    );
  });
}
