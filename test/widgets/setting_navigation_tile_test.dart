/// `SettingNavigationTile.needsAttention` (northstar 14, the Servers row's
/// amber dot): the same convention `TvTopNavigation`'s expired-session marker
/// uses, added to a plain settings row.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/setting_tile.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required bool needsAttention}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: SettingNavigationTile(icon: Icons.dns, title: 'Servers', needsAttention: needsAttention, onTap: () {}),
        ),
      ),
    );
  }

  Widget findDot(WidgetTester tester) => tester.widget<Container>(
    find.byWidgetPredicate((w) => w is Container && (w.decoration as BoxDecoration?)?.color == kAccentAlt),
  );

  testWidgets('draws no dot when nothing needs attention', (tester) async {
    await pump(tester, needsAttention: false);
    expect(
      find.byWidgetPredicate((w) => w is Container && (w.decoration as BoxDecoration?)?.color == kAccentAlt),
      findsNothing,
    );
  });

  testWidgets('draws the amber dot when it does', (tester) async {
    await pump(tester, needsAttention: true);
    final dot = findDot(tester);
    final decoration = (dot as Container).decoration as BoxDecoration;
    expect(decoration.color, kAccentAlt);
    expect(decoration.shape, BoxShape.circle);
  });

  testWidgets('announces attention-required to assistive tech, not just paint', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, needsAttention: true);
    expect(find.bySemanticsLabel(RegExp(t.tvNavigation.attentionRequired)), findsOneWidget);
    handle.dispose();
  });

  testWidgets('no attention-required semantics when nothing needs attention', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, needsAttention: false);
    expect(find.bySemanticsLabel(RegExp(t.tvNavigation.attentionRequired)), findsNothing);
    handle.dispose();
  });
}
