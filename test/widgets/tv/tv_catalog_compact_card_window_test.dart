import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/tv/tv_catalog_artwork_window.dart';
import 'package:pleya/widgets/tv/tv_catalog_compact_card.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

import '../../test_helpers/prefs.dart';

const _cardKey = ValueKey('window-card');
const _posterKey = ValueKey('window-poster');

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  Future<void> pumpCard(WidgetTester tester, FocusNode node, {required bool inWindow, VoidCallback? onSelect}) async {
    tester.view.physicalSize = const Size(1038, 584);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: TvCatalogArtworkScope(
              drawArtwork: inWindow,
              child: TvCatalogCompactCard(
                key: _cardKey,
                width: 145,
                title: 'Deferred title',
                meta: '2000',
                semanticLabel: 'Deferred title, 2000',
                focusNode: node,
                artwork: const ColoredBox(key: _posterKey, color: Colors.red),
                onSelect: onSelect ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('offscreen compact content is deferred while geometry and semantics stay attached', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    final semantics = tester.ensureSemantics();
    try {
      await pumpCard(tester, node, inWindow: false);
      expect(find.text('Deferred title'), findsNothing);
      expect(find.byKey(_posterKey), findsNothing);
      expect(node.context, isNotNull);
      expect(tester.getSize(find.byKey(_cardKey)), Size(145, TvCatalogFullBleedLayout.cardHeight(145, .85)));
      expect(find.bySemanticsLabel('Deferred title, 2000'), findsOneWidget);
      expect(tester.widget<FocusableWrapper>(find.byType(FocusableWrapper)).focusNode, same(node));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('offscreen compact focus reveals actual artwork and keeps the same box and action', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    var selected = 0;
    await pumpCard(tester, node, inWindow: false, onSelect: () => selected++);
    final before = tester.getSize(find.byKey(_cardKey));
    final state = tester.state(find.byKey(_cardKey));
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(
      find.byKey(_posterKey),
      findsOneWidget,
      reason: 'the focused poster must override an old outside-window scope',
    );
    expect(find.text('Deferred title'), findsOneWidget);
    expect(tester.getSize(find.byKey(_cardKey)), before);
    expect(tester.state(find.byKey(_cardKey)), same(state));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(selected, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('offscreen compact re-entry retains its shell and exact resting height', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await pumpCard(tester, node, inWindow: true);
    final state = tester.state(find.byKey(_cardKey));
    final size = tester.getSize(find.byKey(_cardKey));
    expect(find.text('Deferred title'), findsOneWidget);
    await pumpCard(tester, node, inWindow: false);
    expect(find.text('Deferred title'), findsNothing);
    expect(node.context, isNotNull);
    expect(tester.getSize(find.byKey(_cardKey)), size);
    await pumpCard(tester, node, inWindow: true);
    expect(find.text('Deferred title'), findsOneWidget);
    expect(tester.state(find.byKey(_cardKey)), same(state));
    expect(tester.getSize(find.byKey(_cardKey)), size);
  });
}
