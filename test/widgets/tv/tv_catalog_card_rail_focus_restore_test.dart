/// LAND5: returning to a [TvCatalogCardRail] whose remembered card had
/// scrolled far enough to be virtualized out (not merely off to one side, but
/// never rebuilt since) put the focus back on the first card instead of the
/// one the viewer left.
///
/// `focusRail()` only fell back to [TvCatalogCardRailState._nearestSurvivor]
/// scroll-and-focus behaviour — the one `focusColumn` already has, for
/// exactly this "not built yet" case — when the remembered id had never been
/// built at all. A remembered id that *had* been built and then scrolled away
/// stayed in `_nodes` as a detached entry, and the attachment guard correctly
/// refused it, but there was nothing after that refusal except the
/// first-card fallback: the remembered position was never brought back into
/// view.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/tv/tv_catalog_card_rail.dart';

List<String> _itemIds(int count) => [for (var i = 0; i < count; i++) 'item$i'];

Widget _rail(GlobalKey<TvCatalogCardRailState> key, List<String> itemIds, {double factor = 1}) {
  return MaterialApp(
    theme: monoTheme(dark: true),
    home: Scaffold(
      body: TvCatalogCardRail(
        key: key,
        itemIds: itemIds,
        cardWidthFactor: factor,
        cardHeight: (width) => 200,
        hasMore: false,
        isLoadingMore: false,
        onLoadMore: () {},
        itemBuilder: (context, cell) => Focus(
          key: ValueKey('focus_${itemIds[cell.index]}'),
          focusNode: cell.focusNode,
          onFocusChange: cell.onFocusChange,
          child: SizedBox(width: cell.width, child: Text(itemIds[cell.index])),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final count in [1, 3, 30]) {
    for (final factor in [1.0, 1.3]) {
      for (final reduced in [false, true]) {
        testWidgets('CAROUSEL-LEFT1 catalog $count factor=$factor reduced=$reduced', (tester) async {
          tester.view.physicalSize = const Size(1920, 1080);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          tester.platformDispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
            disableAnimations: reduced,
          );
          addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
          final key = GlobalKey<TvCatalogCardRailState>();
          await tester.pumpWidget(_rail(key, _itemIds(count), factor: factor));
          await tester.pumpAndSettle();
          key.currentState!.focusColumn(0);
          await tester.pumpAndSettle();
          double left(int index) => tester.getTopLeft(find.text('item$index')).dx;
          final anchor = left(0);
          for (final index in [count ~/ 2, count - 1, 0]) {
            key.currentState!.focusColumn(index);
            await tester.pumpAndSettle();
            expect(left(index), closeTo(anchor, 0.5));
          }
        });
      }
    }
  }

  testWidgets('restoring focus on a card that scrolled out of the built range brings it back, not the first card', (
    tester,
  ) async {
    const size = Size(1920, 1080);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey<TvCatalogCardRailState>();
    final itemIds = _itemIds(30);
    await tester.pumpWidget(_rail(key, itemIds));
    await tester.pumpAndSettle();

    final controller = tester.widget<ListView>(find.byType(ListView)).controller!;

    // Scroll far enough right to build item25, focus it (which is what sets
    // `_focusedId`), then scroll all the way back — virtualizing it out of
    // the ListView, as arriving fresh at this rail's start would leave it.
    key.currentState!.focusColumn(25);
    await tester.pumpAndSettle();
    expect(find.text('item25'), findsOneWidget);

    final farFocus = tester.widget<Focus>(find.byKey(const ValueKey('focus_item25')));
    farFocus.focusNode!.requestFocus();
    await tester.pumpAndSettle();

    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('item25'), findsNothing, reason: 'the card must actually be out of the built range for this test');

    final restored = key.currentState!.focusRail();
    await tester.pumpAndSettle();

    expect(restored, isTrue);
    expect(
      find.text('item25'),
      findsOneWidget,
      reason: 'LAND5: focusRail() must scroll the remembered card back into view, not fall back to the first one',
    );
    expect(find.text('item0').hitTestable(), findsNothing);
  });
  testWidgets('CAROUSEL-LEFT1 deferred focus follows identity across reorder', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey<TvCatalogCardRailState>();
    final items = _itemIds(30);
    await tester.pumpWidget(_rail(key, items));
    await tester.pumpAndSettle();
    key.currentState!.focusColumn(25);
    await tester.pumpWidget(_rail(key, ['item25', ...items.where((id) => id != 'item25')]));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvCatalogRailCard(item25)');
  });

  testWidgets('CAROUSEL-LEFT1 a newer focus request cancels a queued request', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey<TvCatalogCardRailState>();
    await tester.pumpWidget(_rail(key, _itemIds(30)));
    await tester.pumpAndSettle();
    key.currentState!.focusColumn(25);
    key.currentState!.focusColumn(1);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvCatalogRailCard(item1)');
  });
  testWidgets('CAROUSEL-LEFT1 whole-row replacement rescues focus to a real new card', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey<TvCatalogCardRailState>();
    await tester.pumpWidget(_rail(key, _itemIds(40)));
    await tester.pumpAndSettle();
    key.currentState!.focusColumn(35);
    await tester.pumpAndSettle();
    await tester.pumpWidget(_rail(key, [for (var i = 0; i < 40; i++) 'new$i']));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvCatalogRailCard(new0)');
  });
}
