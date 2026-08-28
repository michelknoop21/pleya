import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/settings_section.dart';

/// Documents two deliberate pixel shifts from moving the group border and the
/// row focus border into `foregroundDecoration`, so they read as a choice
/// made in this refactor rather than a surprise found later:
///
/// - the group's outer border no longer reserves implicit padding, so the
///   card's content area is 2px wider (1px each side) than the margin alone
///   would suggest under the old `decoration`-border;
/// - a row's own focus border is gone (a leading marker replaced it), so a
///   row is never inset by [FocusTheme.focusBorderWidth] regardless of focus.
void main() {
  const outerWidth = 300.0;
  const rowHeight = 40.0;

  testWidgets("the group's card content is not inset by the outer border", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: SizedBox(
            width: outerWidth,
            child: SettingsGroup(
              children: const [SizedBox(height: rowHeight, width: double.infinity)],
            ),
          ),
        ),
      ),
    );

    final material = tester.widget<Material>(
      find.descendant(of: find.byType(SettingsGroup), matching: find.byType(Material)).first,
    );
    final materialWidth = tester.getSize(find.byWidget(material)).width;

    // SettingsGroup's own card margin is fromLTRB(16, 0, 16, 8): that is the
    // only inset the border-as-foregroundDecoration leaves behind.
    expect(materialWidth, outerWidth - 32, reason: 'the border must not additionally narrow the card content');
  });
}
