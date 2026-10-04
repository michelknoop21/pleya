import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A local `shape:` on `FilledButton.styleFrom`/`ElevatedButton.styleFrom`/
/// `OutlinedButton.styleFrom`/`TextButton.styleFrom` silently forks a text-CTA
/// away from `MonoShapes.cta`, and away from the focus ring that is now built
/// to follow that same shape (see `test/theme/cta_shape_contract_test.dart`).
/// That is exactly how the ring ended up boxing a pill button in four
/// different screens before this contract existed.
///
/// Genuinely bespoke controls can be listed in [_allowed] with a reason.
void main() {
  const allowed = <String, String>{
    // A round D-pad-style key on the companion remote layout, not a text CTA.
    'lib/screens/companion_remote/mobile_remote_screen.dart': 'deliberately round D-pad control',
  };

  test('no local shape: override on FilledButton/ElevatedButton/OutlinedButton/TextButton.styleFrom', () {
    final callPattern = RegExp(r'(FilledButton|ElevatedButton|OutlinedButton|TextButton)\.styleFrom\s*\(');
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart') || entity.path.endsWith('.freezed.dart')) continue;
      final relative = entity.path.replaceAll(r'\', '/');
      if (relative == 'lib/theme/mono_theme.dart') continue; // the contract's own definition
      if (allowed.containsKey(relative)) continue;

      final content = entity.readAsStringSync();
      for (final match in callPattern.allMatches(content)) {
        // Walk parens from just after `styleFrom(` (depth already 1) to find
        // the matching close, and check the call's own arguments for `shape:`.
        var depth = 1;
        var i = match.end;
        while (i < content.length && depth > 0) {
          if (content[i] == '(') depth++;
          if (content[i] == ')') depth--;
          i++;
        }
        final callBody = content.substring(match.end, i - 1);
        if (callBody.contains('shape:')) {
          final line = '\n'.allMatches(content.substring(0, match.start)).length + 1;
          offenders.add('$relative:$line: ${match.group(0)}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Text CTAs get their shape from MonoShapes.cta (lib/theme/mono_theme.dart) so the focus ring '
          'matches the button. Remove the local shape: override, or add the file to the allowlist in this '
          'test with a reason.\n${offenders.join('\n')}',
    );
  });
}
