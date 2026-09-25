import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_filter_result.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_filter.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/services/unified_catalog/source_cursor.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/mobile/mobile_catalog_filters_sheet.dart';

/// The phone half of fase 1 of the search-and-filters plan: the same new rows
/// as the TV panel, in the existing two-zone sheet, at iPhone width.
class _ValuesClient implements MediaServerClient {
  _ValuesClient({this.audioLanguages = const [], this.contentRatings = const []});

  final List<String> audioLanguages;
  final List<String> contentRatings;

  @override
  Future<LibraryFilterResult> fetchLibraryFiltersWithValues(String libraryId) async => LibraryFilterResult(
    filters: const [],
    cachedValues: {
      'genre': [MediaFilterValue(key: 'Drama', title: 'Drama')],
      'audioLanguage': [for (final code in audioLanguages) MediaFilterValue(key: code, title: code)],
      'contentRating': [for (final rating in contentRatings) MediaFilterValue(key: rating, title: rating)],
    },
  );

  @override
  MediaBackend get backend => MediaBackend.jellyfin;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.jellyfin;

  @override
  ServerId get serverId => ServerId('attic');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  CatalogLibrary library(String server, MediaBackend backend) =>
      (serverId: ServerId(server), serverName: server, libraryId: '1', libraryTitle: 'Films', backend: backend);
  final mixed = [library('nas', MediaBackend.plex), library('attic', MediaBackend.jellyfin)];
  final jellyfinOnly = [library('attic', MediaBackend.jellyfin)];

  Future<List<UnifiedCatalogFilterSelection>> render(
    WidgetTester tester, {
    required List<CatalogLibrary> libraries,
    List<String> audioLanguages = const [],
    List<String> contentRatings = const [],
  }) async {
    // iPhone 15 logical size.
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final applied = <UnifiedCatalogFilterSelection>[];
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: MobileCatalogFiltersSheet(
                selection: UnifiedCatalogFilterSelection.empty,
                capabilities: unifiedFilterCapabilitiesFor(libraries.map((l) => l.backend)),
                libraries: libraries,
                clientFor: (_) => _ValuesClient(audioLanguages: audioLanguages, contentRatings: contentRatings),
                initialSection: MobileCatalogFilterSection.status,
                onApply: applied.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return applied;
  }

  testWidgets('Status lists Actief bezig, and Bekeken only without a Plex library', (tester) async {
    await render(tester, libraries: mixed);
    expect(find.text(t.unifiedCatalog.filters.inProgress), findsOneWidget);
    expect(find.text(t.unifiedCatalog.filters.watched), findsNothing);

    final applied = await render(tester, libraries: jellyfinOnly);
    expect(find.text(t.unifiedCatalog.filters.watched), findsOneWidget);
    await tester.tap(find.text(t.unifiedCatalog.filters.watched));
    await tester.pump();
    await tester.tap(find.text(t.unifiedCatalog.filters.apply));
    await tester.pump();
    expect(applied.single.watchState, UnifiedWatchFilter.watched);
  });

  testWidgets('Audiotaal and Leeftijd stay out of the rail without values', (tester) async {
    await render(tester, libraries: jellyfinOnly);
    expect(find.text(t.libraries.filterCategories.audioLanguage), findsNothing);
    expect(find.text(t.unifiedCatalog.filters.contentRating), findsNothing);
    expect(find.text(t.unifiedCatalog.filters.genre), findsOneWidget, reason: 'genre keeps its row');
  });

  testWidgets('the full rail fits an iPhone and Leeftijd applies its values', (tester) async {
    final applied = await render(
      tester,
      libraries: mixed,
      audioLanguages: const ['eng'],
      contentRatings: const ['12', 'PG-13'],
    );
    expect(tester.takeException(), isNull);
    for (final label in [
      t.unifiedCatalog.filters.status,
      t.unifiedCatalog.filters.genre,
      t.libraries.filterCategories.audioLanguage,
      t.unifiedCatalog.filters.year,
      t.unifiedCatalog.filters.contentRating,
      t.unifiedCatalog.filters.servers,
      t.unifiedCatalog.filters.libraries,
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await tester.tap(find.text(t.unifiedCatalog.filters.contentRating));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PG-13'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.unifiedCatalog.filters.apply));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(applied.single.officialRatings, {'PG-13'});
  });
}
