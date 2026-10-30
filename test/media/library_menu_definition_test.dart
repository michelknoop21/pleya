/// The fixed definition of the Sort and Filter menus (Michel, 30 October 2026).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/library_menu_definition.dart';
import 'package:pleya/media/media_sort.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query.dart';

MediaSort _sort(String key) => MediaSort(key: key, title: key);

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await LocaleSettings.setLocale(AppLocale.nl);
  });
  tearDown(() => LocaleSettings.setLocale(AppLocale.en));

  test('Sorteren op reads as the definition, in Dutch', () {
    expect(librarySortMenu.map(librarySortFieldLabel), [
      'Titel',
      'Jaar',
      'Releasedatum',
      'Critici',
      'Publiek',
      'Waardering',
      'Leeftijd',
      'Duur',
      'Voortgang',
      'Afgespeeld',
      'Toegevoegd',
      'Bekeken',
      'Resolutie',
    ]);
  });

  test('no sort field is missing from the menu', () {
    expect(librarySortMenu.toSet(), UnifiedCatalogSortField.values.toSet());
  });

  test('Filteren op reads as the definition, with Bekeken at the bottom', () {
    expect(libraryQuickFilterMenu.map(libraryQuickFilterLabel), [
      'Alles',
      'HDR',
      'Dolby Vision',
      'HDR10+',
      'Atmos',
      'Ongekeken',
      'Bezig',
      'Niet gekoppeld',
      'Dubbel',
      'Bekeken',
    ]);
  });

  test('the categories start with Genre, Jaar, Decennium and Leeftijd', () {
    expect(libraryFilterCategoryMenu.take(4), [
      LibraryFilterCategory.genre,
      LibraryFilterCategory.year,
      LibraryFilterCategory.decade,
      LibraryFilterCategory.contentRating,
    ]);
  });

  test('options without a place stay, at the bottom, in the order they came', () {
    final ordered = libraryMenuOrderedSorts([
      _sort('random'),
      _sort('addedAt'),
      _sort('studio'),
      _sort('rating'),
      _sort('titleSort'),
      _sort('startDate'),
    ]);
    expect(ordered.map((s) => s.key), ['titleSort', 'rating', 'addedAt', 'random', 'studio', 'startDate']);
  });

  test('Plex names the critic score rating, and no option has a key it cannot prove', () {
    expect(plexSortKeyFor(UnifiedCatalogSortField.criticRating), 'rating');
    expect(plexSortKeyFor(UnifiedCatalogSortField.title), 'titleSort');
    expect(plexSortKeyFor(UnifiedCatalogSortField.resolution), 'mediaHeight');
  });

  test('server keys are recognised case-insensitively on a small alias list', () {
    expect(libraryQuickFilterForServerKey('hdr10Plus'), LibraryQuickFilter.hdr10Plus);
    expect(libraryQuickFilterForServerKey('HDR10+'), LibraryQuickFilter.hdr10Plus);
    expect(libraryQuickFilterForServerKey('dolbyVision'), LibraryQuickFilter.dolbyVision);
    expect(libraryQuickFilterForServerKey('DoVi'), LibraryQuickFilter.dolbyVision);
    expect(libraryQuickFilterForServerKey('Duplicate'), LibraryQuickFilter.duplicates);
    expect(libraryQuickFilterForServerKey('hasSubtitles'), isNull);
  });
}
