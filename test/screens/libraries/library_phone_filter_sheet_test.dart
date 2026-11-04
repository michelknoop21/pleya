/// Filteren op in the iPhone library look (A-06, Michel 30 October 2026,
/// references e2b9c485 and 20e126cc): the shared menu definition drawn as quick
/// choices with a check, a rule, then the categories.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/library_menu_definition.dart';
import 'package:pleya/media/media_filter.dart';
import 'package:pleya/screens/libraries/filters_bottom_sheet.dart';
import 'package:pleya/screens/libraries/library_phone_filter_pages.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/widgets/app_icon.dart';
import 'package:pleya/widgets/mobile/library_phone_look.dart';
import 'package:pleya/widgets/mobile/library_phone_sheet.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/overlay_sheet_geometry.dart';

MediaFilter _boolean(String key, String title) =>
    MediaFilter(filter: key, filterType: 'boolean', key: '/$key', title: title, type: 'filter');

MediaFilter _category(String key, String title) =>
    MediaFilter(filter: key, filterType: 'string', key: '/library/$key', title: title, type: 'filter');

/// What a Plex section lists, deliberately not in the menu's order.
final _server = [
  _category('resolution', 'Resolution'),
  _boolean('duplicate', 'Duplicates'),
  _category('genre', 'Genre'),
  _boolean('hdr', 'HDR'),
  _boolean('unwatched', 'Unwatched'),
  _category('year', 'Year'),
  _boolean('dovi', 'Dolby Vision'),
  _boolean('someFlag', 'Some Flag'),
];

final _genres = {
  'genre': [
    MediaFilterValue(key: '/library/genre?genre=28', title: 'Action'),
    MediaFilterValue(key: '/library/genre?genre=18', title: 'Drama'),
  ],
};

void main() {
  late BuildContext screen;
  Map<String, String>? applied;

  setUp(() {
    applied = null;
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  Future<void> open(
    WidgetTester tester, {
    List<MediaFilter>? filters,
    Map<String, String> selected = const {},
    bool phoneStyle = true,
    double bottomInset = 0,
  }) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(bottom: bottomInset);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: OverlaySheetHost(
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  screen = context;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      ),
    );
    unawaited(
      OverlaySheetController.of(screen).show(
        presentation: OverlaySheetPresentation.floating,
        showDragHandle: true,
        backgroundColor: Colors.black,
        builder: (_) => FiltersBottomSheet(
          filters: filters ?? libraryMenuOrderedFilters(_server),
          selectedFilters: Map.of(selected),
          onFiltersChanged: (value) => applied = Map.of(value),
          serverId: 's1',
          libraryKey: 's1:1',
          cachedValues: _genres,
          phoneStyle: phoneStyle,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double y(WidgetTester tester, String text) => tester.getCenter(find.text(text)).dy;

  Finder rowOf(String title) => find.widgetWithText(LibraryPhoneSheetRow, title);

  bool ticked(WidgetTester tester, String title) =>
      tester.widget<LibraryPhoneSheetRow>(rowOf(title)).selected &&
      find.descendant(of: rowOf(title), matching: find.byType(AppIcon)).evaluate().isNotEmpty;

  group('order', () {
    testWidgets('quick choices in the definition\'s order, then the rule, then the categories', (tester) async {
      await open(tester);
      final labels = [
        t.unifiedCatalog.filters.quick.all,
        t.unifiedCatalog.filters.quick.hdr,
        t.unifiedCatalog.filters.quick.dolbyVision,
        t.unifiedCatalog.filters.quick.unwatched,
        t.unifiedCatalog.filters.quick.duplicates,
        'Some Flag',
        t.unifiedCatalog.filters.genre,
        t.unifiedCatalog.filters.year,
        'Resolution',
      ];
      final positions = [for (final label in labels) y(tester, label)];
      expect(positions, [...positions]..sort());

      final rule = tester.getCenter(find.byType(LibraryPhoneSheetDivider)).dy;
      expect(rule, greaterThan(y(tester, 'Some Flag')));
      expect(rule, lessThan(y(tester, t.unifiedCatalog.filters.genre)));
    });

    testWidgets('a row exists because the server lists it: no HDR10+, no Atmos here', (tester) async {
      await open(tester);
      expect(find.text(t.unifiedCatalog.filters.quick.hdr10Plus), findsNothing);
      expect(find.text(t.unifiedCatalog.filters.quick.atmos), findsNothing);
      expect(find.text(t.unifiedCatalog.filters.quick.unmatched), findsNothing);
    });

    testWidgets('no quick choices: no Alles and no rule, only the categories', (tester) async {
      await open(tester, filters: libraryMenuOrderedFilters([_category('genre', 'Genre')]));
      expect(find.text(t.unifiedCatalog.filters.quick.all), findsNothing);
      expect(find.byType(LibraryPhoneSheetDivider), findsNothing);
      expect(find.text(t.unifiedCatalog.filters.genre), findsOneWidget);
    });
  });

  group('look', () {
    testWidgets('heading, row distance and the sheet\'s height follow the reference', (tester) async {
      await open(tester);
      expect(find.text(t.libraries.filterBy), findsOneWidget);
      final all = t.unifiedCatalog.filters.quick.all;
      final hdr = t.unifiedCatalog.filters.quick.hdr;
      expect(y(tester, hdr) - y(tester, all), closeTo(LibraryPhoneMetrics.sheetRowHeight, 0.5));
      expect(y(tester, all) - y(tester, t.libraries.filterBy), closeTo(LibraryPhoneMetrics.sheetRowHeight, 1));
      final sheet = tester.getRect(find.byType(LibraryPhoneFilterMenu));
      expect(sheet.height, lessThan(874 * 0.85), reason: 'nine rows do not fill the sheet');
    });

    testWidgets('the tick is the accent colour, Alles carries it while no quick choice is on', (tester) async {
      await open(tester);
      final all = t.unifiedCatalog.filters.quick.all;
      expect(ticked(tester, all), isTrue);
      final check = tester.widget<AppIcon>(find.descendant(of: rowOf(all), matching: find.byType(AppIcon)));
      expect(check.color, tokens(tester.element(find.text(all))).accent);
    });
  });

  testWidgets('a 48 pt Android navigation bar leaves the last row clear', (tester) async {
    await open(
      tester,
      filters: libraryMenuOrderedFilters([_boolean('hdr', 'HDR'), _category('genre', 'Genre')]),
      bottomInset: 48,
    );
    final last = tester.getRect(find.widgetWithText(LibraryPhoneSheetRow, t.unifiedCatalog.filters.genre));
    expect(last.bottom, lessThanOrEqualTo(874 - 48));
  });

  group('choosing', () {
    testWidgets('a quick choice applies, closes, and comes back ticked with Alles off', (tester) async {
      await open(tester);
      await tester.tap(find.text(t.unifiedCatalog.filters.quick.hdr));
      await tester.pumpAndSettle();
      expect(applied, {'hdr': '1'});
      expect(find.byType(LibraryPhoneFilterMenu), findsNothing);

      await open(tester, selected: {'hdr': '1'});
      expect(ticked(tester, t.unifiedCatalog.filters.quick.hdr), isTrue);
      expect(ticked(tester, t.unifiedCatalog.filters.quick.all), isFalse);
    });

    testWidgets('two quick choices keep working together, the way the switches did', (tester) async {
      await open(tester, selected: {'hdr': '1'});
      await tester.tap(find.text(t.unifiedCatalog.filters.quick.unwatched));
      await tester.pumpAndSettle();
      expect(applied, {'hdr': '1', 'unwatched': '1'});
    });

    testWidgets('a ticked quick choice goes off again', (tester) async {
      await open(tester, selected: {'hdr': '1'});
      await tester.tap(find.text(t.unifiedCatalog.filters.quick.hdr));
      await tester.pumpAndSettle();
      expect(applied, isEmpty);
    });

    testWidgets('Alles clears the quick choices and leaves a category alone', (tester) async {
      await open(tester, selected: {'hdr': '1', 'unwatched': '1', 'genre': '28'});
      await tester.tap(find.text(t.unifiedCatalog.filters.quick.all));
      await tester.pumpAndSettle();
      expect(applied, {'genre': '28'});
    });

    testWidgets('Clear takes the categories too', (tester) async {
      await open(tester, selected: {'hdr': '1', 'genre': '28'});
      await tester.tap(find.text(t.common.clear));
      await tester.pumpAndSettle();
      expect(applied, isEmpty);
    });

    testWidgets('NEGATIVE CONTROL: nothing set, nothing to clear', (tester) async {
      await open(tester);
      expect(find.text(t.common.clear), findsNothing);
    });
  });

  group('a category', () {
    testWidgets('opens its values in the same sheet, with a way back', (tester) async {
      await open(tester);
      await tester.tap(find.text(t.unifiedCatalog.filters.genre));
      await tester.pumpAndSettle();

      expect(find.byType(LibraryPhoneFilterValues), findsOneWidget);
      expect(find.text('Action'), findsOneWidget);
      expect(ticked(tester, t.libraries.all), isTrue);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPhoneFilterMenu), findsOneWidget);
    });

    testWidgets('a value applies, and the category row then shows it in the accent colour', (tester) async {
      await open(tester);
      await tester.tap(find.text(t.unifiedCatalog.filters.genre));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Drama'));
      await tester.pumpAndSettle();
      expect(applied, {'genre': '18'});

      await open(tester, selected: {'genre': '18'});
      final value = tester.widget<Text>(find.text('Drama'));
      expect(value.style?.color, tokens(tester.element(find.text('Drama'))).accent);
    });

    testWidgets('its first row takes the category off again', (tester) async {
      await open(tester, selected: {'genre': '18'});
      await tester.tap(find.text(t.unifiedCatalog.filters.genre));
      await tester.pumpAndSettle();
      expect(ticked(tester, 'Drama'), isTrue);
      await tester.tap(find.text(t.libraries.all));
      await tester.pumpAndSettle();
      expect(applied, isEmpty);
    });
  });

  testWidgets('NEGATIVE CONTROL: iPad and desktop keep their switches', (tester) async {
    await open(tester, phoneStyle: false);
    expect(find.byType(LibraryPhoneFilterMenu), findsNothing);
    expect(find.byType(LibraryPhoneSheetRow), findsNothing);
    expect(find.text(t.libraries.filters), findsOneWidget);
  });
}
