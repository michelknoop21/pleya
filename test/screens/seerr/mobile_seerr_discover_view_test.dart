/// The iPhone Aanvragen page (northstar 19). Runs against the presentation widgets:
/// `SeerrDiscoverScreen` itself needs a live `SeerrProvider` session, which has no test
/// seam (see `seerr_discover_tv_test.dart`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/seerr/mobile_seerr_discover_view.dart';
import 'package:pleya/screens/seerr/seerr_discover_filter_bar.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/focusable_filter_chip.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        theme: monoTheme(dark: true),
        home: InputModeTracker(
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('catalog sort maps to the movie and series API fields', () {
    expect(mobileSeerrSortWire(MobileSeerrCatalogSort.newest, SeerrDiscoverType.movies), 'primary_release_date.desc');
    expect(mobileSeerrSortWire(MobileSeerrCatalogSort.newest, SeerrDiscoverType.tv), 'first_air_date.desc');
    expect(mobileSeerrSortWire(MobileSeerrCatalogSort.title, SeerrDiscoverType.tv), 'original_name.asc');
  });

  test('availability filters group requestable, processing and available titles', () {
    expect(mobileSeerrMatchesAvailability(SeerrMediaStatus.unknown, MobileSeerrAvailability.requestable), isTrue);
    expect(mobileSeerrMatchesAvailability(SeerrMediaStatus.processing, MobileSeerrAvailability.processing), isTrue);
    expect(
      mobileSeerrMatchesAvailability(SeerrMediaStatus.partiallyAvailable, MobileSeerrAvailability.available),
      isTrue,
    );
    expect(mobileSeerrMatchesAvailability(SeerrMediaStatus.available, MobileSeerrAvailability.requestable), isFalse);
  });

  testWidgets('catalog controls use the same three filled pills as Movies', (tester) async {
    await _pump(
      tester,
      MobileSeerrCatalogControls(
        type: SeerrDiscoverType.movies,
        activeFilterCount: 2,
        sortLabel: t.unifiedCatalog.sort.newestRelease,
        onTypePressed: () {},
        onFiltersPressed: () {},
        onSortPressed: () {},
      ),
    );

    final chips = tester.widgetList<FocusableFilterChip>(find.byType(FocusableFilterChip)).toList();
    expect(chips, hasLength(3));
    expect(chips.map((chip) => chip.variant), everyElement(FilterChipVariant.filled));
    expect(chips.map((chip) => chip.label), [
      t.seerr.filterMovies,
      t.unifiedCatalog.filters.title,
      t.unifiedCatalog.sort.newestRelease,
    ]);
    expect(chips[1].badgeCount, 2);
  });

  testWidgets('MobileSeerrSeeAllLink opens the row', (tester) async {
    var opened = 0;
    await _pump(tester, MobileSeerrSeeAllLink(onPressed: () => opened++));
    await tester.tap(find.text(t.watchlist.seeAll));
    expect(opened, 1);
  });
}
