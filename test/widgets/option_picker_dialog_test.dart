import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/utils/dialogs.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/app_icon.dart';
import 'package:pleya/widgets/focusable_list_tile.dart';

void main() {
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  testWidgets('toggle label stays on one line in narrow option picker dialog', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    bool includeSpecials = true;
    String? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showOptionPickerDialog<String>(
                    context,
                    title: 'Download',
                    toggle: (
                      label: 'Include Specials',
                      icon: Symbols.star_rounded,
                      value: includeSpecials,
                      onChanged: (value) => includeSpecials = value,
                    ),
                    options: [
                      (icon: Symbols.download_rounded, label: 'All Episodes', value: 'all'),
                      (icon: Symbols.visibility_off_rounded, label: 'Unwatched Only', value: 'unwatched'),
                    ],
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final includeSpecialsLabel = find.text('Include Specials');
    expect(includeSpecialsLabel, findsOneWidget);

    final paragraph = tester.renderObject<RenderParagraph>(includeSpecialsLabel);
    final lineBoxes = paragraph.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 'Include Specials'.length),
    );
    expect(lineBoxes, hasLength(1));

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(includeSpecials, isFalse);
    expect(selected, isNull);
    expect(find.byType(SimpleDialog), findsOneWidget);
    expect(includeSpecialsLabel, findsOneWidget);

    await tester.tap(find.text('All Episodes'));
    await tester.pumpAndSettle();

    expect(selected, 'all');
    expect(find.byType(SimpleDialog), findsNothing);
  });

  // F-TV1 (docs/density-audit-2026-09.md): on TV every row/panel dimension in
  // this dialog used to be a raw literal, so only the global 1.85x wrapper
  // touched it and it rendered ~18% roomier than the tokened TV panels
  // (TvCatalogSortPanel/TvCatalogFilterPanel) at the same nominal size.
  testWidgets('on TV, the panel and its rows scale with TvLayoutConstants.scaleOf', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    tester.view.devicePixelRatio = 1.0;
    // 1038x584 is the logical size Apple TV's own _AppleTvScale wrapper
    // hands the app (1920x1080 screen space / 1.85) — scaleOf clamps its
    // height-derived scale to 0.85 there, below the reference 1.0.
    tester.view.physicalSize = const Size(1038, 584);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () => showOptionPickerDialog<String>(
                  context,
                  title: 'Download',
                  toggle: (label: 'Include Specials', icon: Symbols.star_rounded, value: true, onChanged: (_) {}),
                  options: [(icon: Symbols.download_rounded, label: 'All Episodes', value: 'all')],
                ),
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    final scale = TvLayoutConstants.scaleForSize(const Size(1038, 584));
    expect(scale, 0.85);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final dialog = tester.widget<SimpleDialog>(find.byType(SimpleDialog));
    expect(dialog.insetPadding, EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 24 * scale));
    expect(dialog.constraints, BoxConstraints(minWidth: 304 * scale));
    // Finding 5 (docs/density-audit-2026-09.md): the panel's own contentPadding
    // was the one dimension in this dialog still on the raw 1.85x-only path.
    expect(dialog.contentPadding, EdgeInsets.symmetric(vertical: 8 * scale));

    // The toggle row is the first FocusableListTile (children[0], wrapped in
    // MergeSemantics); the option row is the last. Only the option row sets
    // horizontalTitleGap/minLeadingWidth, so pin it by position, not `.first`.
    final optionRow = tester.widget<FocusableListTile>(find.byType(FocusableListTile).last);
    expect(optionRow.contentPadding, EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 4 * scale));
    expect(optionRow.horizontalTitleGap, 8.0 * scale);
    expect(optionRow.minLeadingWidth, 24.0 * scale);

    // Finding 5: the toggle row's icon and the option row's icon were the
    // other raw-literal survivors — fixed size 24 while the padding around
    // them shrank, which changed the icon:padding proportion on TV.
    final icons = tester.widgetList<AppIcon>(
      find.descendant(of: find.byType(SimpleDialog), matching: find.byType(AppIcon)),
    );
    expect(icons, hasLength(2), reason: 'the toggle icon and the one option icon');
    for (final icon in icons) {
      expect(icon.size, 24.0 * scale, reason: 'every option-picker icon must follow the same TV scale as its row');
    }
  });
}
