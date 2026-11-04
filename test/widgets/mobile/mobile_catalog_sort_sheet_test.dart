/// The phone's sort sheet: what a source can run, every row readable, and on the
/// smallest phone every row reachable.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/mobile/mobile_catalog_sort_sheet.dart';
import 'package:pleya/widgets/overlay_sheet.dart';

Future<void> _openSheet(WidgetTester tester, List<MediaBackend> backends, Size size) async {
  LocaleSettings.setLocaleSync(AppLocale.en);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: monoTheme(dark: true),
      home: OverlaySheetHost(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showMobileCatalogSortSheet(
              context,
              current: UnifiedCatalogSort.titleAsc,
              capabilities: unifiedFilterCapabilitiesFor(backends),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Pleya Server offers the year, with two rows that read differently', (tester) async {
    await _openSheet(tester, [MediaBackend.pleyaServer], const Size(393, 852));
    expect(find.text(t.unifiedCatalog.sort.yearNewest), findsOneWidget);
    expect(find.text(t.unifiedCatalog.sort.yearOldest), findsOneWidget);
    expect(find.text(t.unifiedCatalog.sort.newestRelease), findsNothing);
  });

  testWidgets('Plex has the date and the year', (tester) async {
    await _openSheet(tester, [MediaBackend.plex], const Size(393, 852));
    expect(find.text(t.unifiedCatalog.sort.newestRelease), findsOneWidget);
    expect(find.text(t.unifiedCatalog.sort.yearNewest), findsOneWidget);
  });

  for (final size in const [Size(320, 568), Size(568, 320)]) {
    testWidgets('all nine rows fit on $size without an overflow', (tester) async {
      await _openSheet(tester, [MediaBackend.plex], size);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text(t.unifiedCatalog.sort.recentlyWatched),
        80,
        scrollable: find.descendant(of: find.byType(MobileCatalogSortSheet), matching: find.byType(Scrollable)),
      );
      expect(find.text(t.unifiedCatalog.sort.recentlyWatched).hitTestable(), findsOneWidget);
    });
  }
}
