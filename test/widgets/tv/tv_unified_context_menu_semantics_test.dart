/// J8, the software half: the hoofdstuk-23 context menu announces each action's
/// **position and count**, not only its name.
///
/// `tvContextMenu.menuSemantics` — "Action 3 of 7: Mark as watched" — has been
/// translated into sixteen locales since fase 9 and was called from nowhere.
/// The panel contained no `Semantics(` at all, and `TvCatalogOptionRow`'s only
/// accessibility output was `semanticLabel: label`: the bare action name. A
/// VoiceOver listener therefore had no way to know whether "Markeer als
/// bekeken" was the first of two actions or the third of seven, on a panel with
/// no visible list affordance to fall back on.
///
/// The row is shared with the sort and filter panels, so the composition lives
/// at the menu's call site — where `index` and `actions.length` already are —
/// behind an optional parameter that defaults to today's behaviour. Both halves
/// are asserted here: the menu says more, and the sort panel says exactly what
/// it said before.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/media/unified/source_availability.dart';
import 'package:pleya/screens/tv/tv_unified_context_menu.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/tv/tv_catalog_sort_panel.dart';

UnifiedMediaGroup _group() {
  final source = UnifiedMediaSource.fromItem(
    MediaItem(
      id: 'i1',
      backend: MediaBackend.plex,
      kind: MediaKind.movie,
      title: 'Dune',
      year: 2021,
      serverId: 'nas',
      serverName: 'NAS',
    ),
  );
  return UnifiedMediaGroup(
    groupId: 'g1',
    identity: CanonicalMediaIdentity.movie(title: 'Dune', year: 2021),
    sources: [source],
    representativeSourceKey: source.sourceKey,
    watchState: UnifiedWatchState(representativeSourceKey: source.sourceKey),
  );
}

void main() {
  Future<List<TvCatalogOptionRow>> openMenu(WidgetTester tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: InputModeTracker(
            child: OverlaySheetHost(
              child: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () => showTvUnifiedContextMenu(
                        context,
                        group: _group(),
                        availabilityFor: (_) => SourceAvailability.online,
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final rows = tester.widgetList<TvCatalogOptionRow>(find.byType(TvCatalogOptionRow)).toList();
    expect(rows, isNotEmpty, reason: 'the menu has to have opened at all');
    return rows;
  }

  testWidgets('every action row announces its label, its position and the count', (tester) async {
    final rows = await openMenu(tester);

    for (var i = 0; i < rows.length; i++) {
      expect(
        rows[i].semanticLabel,
        t.tvContextMenu.menuSemantics(index: i + 1, count: rows.length, label: rows[i].label),
        reason: 'row ${i + 1} has to name where it is, not only what it is',
      );
    }
  });

  testWidgets('the position is one-based, the way it is read aloud', (tester) async {
    final rows = await openMenu(tester);

    expect(rows.first.semanticLabel, contains('1'));
    expect(
      rows.first.semanticLabel,
      isNot(equals(rows.first.label)),
      reason: 'the bare label is exactly what J8 found insufficient',
    );
  });

  testWidgets('the announcement is the real, translated string, not a hand-built one', (tester) async {
    // Reading it back through the same `t.tvContextMenu.menuSemantics` the code
    // calls would pass on any wiring, including none. This checks the shape the
    // English source actually declares.
    final rows = await openMenu(tester);
    expect(rows.first.semanticLabel, 'Action 1 of ${rows.length}: ${rows.first.label}');
  });

  testWidgets('the shared row keeps its old behaviour where nothing passed a label', (tester) async {
    // The sort and filter panels use the same `TvCatalogOptionRow`, and a
    // position among sort options is not information — its label is. So the
    // parameter is optional and falls back to `label`.
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: InputModeTracker(
            child: Scaffold(
              body: TvCatalogOptionRow(label: 'Title A-Z', isSelected: true, scale: 1, onPressed: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = tester.widget<TvCatalogOptionRow>(find.byType(TvCatalogOptionRow));
    expect(row.semanticLabel, isNull, reason: 'the sort panel passes nothing, exactly as before');
    // And the row falls back to its own label rather than to nothing — read off
    // the `FocusableWrapper` it hands the label to, which is what actually
    // reaches the semantics tree.
    final wrapper = tester.widget<FocusableWrapper>(find.byType(FocusableWrapper).first);
    expect(wrapper.semanticLabel, 'Title A-Z');
  });
}
