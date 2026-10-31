/// A saved Nieuwste release runs on the year on Pleya Server. Both wizards have
/// to say so: what the row reads and what it asks for are the same sort.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/screens/home/customize/home_row_wizard_view.dart';
import 'package:pleya/services/unified_catalog/home_custom_row.dart';
import 'package:pleya/services/unified_catalog/home_custom_row_loader.dart';
import 'package:pleya/services/unified_catalog/home_row_editing.dart';
import 'package:pleya/services/unified_catalog/source_cursor.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/tv/tv_home_row_wizard.dart';
import 'package:pleya/widgets/tv/tv_panel_primitives.dart';

import '../../../test_helpers/home_rows_harness.dart';

CatalogLibrary _library(MediaBackend backend) =>
    (serverId: ServerId('s'), serverName: 's', libraryId: 'lib', libraryTitle: 'lib', backend: backend);

const _row = HomeCustomRow(
  id: 'r',
  kind: MediaKind.movie,
  name: 'Rij',
  preferences: UnifiedCatalogPreferences(sort: UnifiedCatalogSort.newestRelease),
);

Future<HomeCustomRowContent> _found(HomeCustomRow _) async =>
    HomeCustomRowContent(groups: [homeGroup('x1')], isExact: true);

Widget _shell(Widget child) => MaterialApp(
  theme: monoTheme(dark: true),
  home: OverlaySheetHost(child: Scaffold(body: child)),
);

Future<void> _phone(WidgetTester tester, MediaBackend backend) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _shell(
      HomeRowWizardView(
        editing: HomeRowEditing(librariesFor: (_) => [_library(backend)], preview: _found, clientFor: (_) => null),
        initial: _row,
        onSave: (_) {},
        onCancel: () {},
      ),
    ),
  );
  await tester.pump();
}

Future<void> _tv(WidgetTester tester, MediaBackend backend) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _shell(
      TvHomeRowWizard(
        initial: _row,
        librariesFor: (_) => [_library(backend)],
        preview: _found,
        onSave: (_) {},
        onCancel: () {},
      ),
    ),
  );
  await tester.pump();
}

Future<void> _next(WidgetTester tester) async {
  // The TV button answers the remote, not a pointer.
  final tvButton = find.widgetWithText(TvPanelButton, t.unifiedCatalog.homeRows.next);
  if (tvButton.evaluate().isNotEmpty) {
    tester.widget<TvPanelButton>(tvButton).onPressed();
  } else {
    await tester.tap(find.text(t.unifiedCatalog.homeRows.next).last);
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  Finder reads(String label) => find.textContaining(label);

  for (final (name, open) in [('phone', _phone), ('tvOS', _tv)]) {
    group('$name wizard', () {
      testWidgets('on Pleya Server the filter step and the preview read the year', (tester) async {
        await open(tester, MediaBackend.pleyaServer);
        await _next(tester);
        expect(reads(t.unifiedCatalog.sort.yearNewest), findsWidgets);
        expect(reads(t.unifiedCatalog.sort.newestRelease), findsNothing);
        await _next(tester);
        expect(reads(t.unifiedCatalog.sort.yearNewest), findsWidgets);
        expect(reads(t.unifiedCatalog.sort.newestRelease), findsNothing);
      });

      testWidgets('NEGATIVE CONTROL: a backend with the date keeps saying release', (tester) async {
        await open(tester, MediaBackend.jellyfin);
        await _next(tester);
        expect(reads(t.unifiedCatalog.sort.newestRelease), findsWidgets);
        expect(reads(t.unifiedCatalog.sort.yearNewest), findsNothing);
      });
    });
  }
}
