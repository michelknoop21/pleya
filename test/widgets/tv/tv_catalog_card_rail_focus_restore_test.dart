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

Widget _rail(GlobalKey<TvCatalogCardRailState> key, List<String> itemIds) {
  return MaterialApp(
    theme: monoTheme(dark: true),
    home: Scaffold(
      body: TvCatalogCardRail(
        key: key,
        itemIds: itemIds,
        cardHeight: (width) => 200,
        hasMore: false,
        isLoadingMore: false,
        onLoadMore: () {},
        itemBuilder: (context, cell) => Focus(
          key: ValueKey('focus_item${cell.index}'),
          focusNode: cell.focusNode,
          onFocusChange: cell.onFocusChange,
          child: SizedBox(width: cell.width, child: Text('item${cell.index}')),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    controller.jumpTo(controller.position.maxScrollExtent);
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
}
