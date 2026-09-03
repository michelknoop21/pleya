import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/mobile/mobile_sort_sheet.dart';

import '../../test_helpers/prefs.dart';

/// The catalogue's sort picker. iOS Unified 2026 fase 3.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  Future<UnifiedCatalogSort?> pumpSheet(WidgetTester tester, {required UnifiedCatalogSort current}) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    UnifiedCatalogSort? chosen;
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: MobileSortSheet(current: current, onChosen: (sort) => chosen = sort),
        ),
      ),
    );
    await tester.pump();
    return chosen;
  }

  testWidgets('offers every sort the contract has, and no more', (tester) async {
    await pumpSheet(tester, current: UnifiedCatalogSort.titleAsc);

    // Seven, matching `UnifiedCatalogSort`. Rating is deliberately absent
    // there until the two backends' scales are proven equivalent (10.5), and
    // this sheet must not invent an eighth row.
    for (final sort in UnifiedCatalogSort.values) {
      expect(find.text(mobileSortLabel(sort)), findsOneWidget);
    }
    expect(find.textContaining('Rating'), findsNothing);
  });

  testWidgets('every sort has its own label — no two rows read the same', (tester) async {
    final labels = UnifiedCatalogSort.values.map(mobileSortLabel).toSet();
    expect(labels.length, UnifiedCatalogSort.values.length);
  });

  testWidgets('picking a sort reports it once, on tap', (tester) async {
    UnifiedCatalogSort? chosen;
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: MobileSortSheet(current: UnifiedCatalogSort.titleAsc, onChosen: (sort) => chosen = sort),
        ),
      ),
    );
    await tester.pump();

    // One value, so there is nothing to assemble before committing: no Apply
    // button, unlike the filter panel.
    expect(find.text('Apply'), findsNothing);
    await tester.tap(find.text(mobileSortLabel(UnifiedCatalogSort.recentlyAdded)));
    await tester.pump();
    expect(chosen, UnifiedCatalogSort.recentlyAdded);
  });

  testWidgets('the current sort is the ticked one', (tester) async {
    await pumpSheet(tester, current: UnifiedCatalogSort.newestRelease);

    expect(find.byIcon(Icons.check_rounded), findsNothing, reason: 'the family draws Material Symbols, not Icons');
    // One tick, and it belongs to the current sort: the row is bold where the
    // others are muted.
    final current = tester.widget<Text>(find.text(mobileSortLabel(UnifiedCatalogSort.newestRelease)));
    final other = tester.widget<Text>(find.text(mobileSortLabel(UnifiedCatalogSort.titleAsc)));
    expect(current.style?.fontWeight, FontWeight.w600);
    expect(other.style?.fontWeight, FontWeight.w400);
  });
}
