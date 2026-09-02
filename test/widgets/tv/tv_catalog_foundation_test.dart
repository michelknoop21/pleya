import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/focus/dpad_navigator.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_filter.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/library_filter_result.dart';
import 'package:pleya/services/unified_catalog/source_cursor.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/overlay_sheet_geometry.dart';
import 'package:pleya/widgets/tv/tv_catalog_filter_panel.dart';
import 'package:pleya/widgets/tv/tv_catalog_sort_panel.dart';

/// Fase 5A: the shared TV panel, focus and geometry foundation the Films and
/// Series surfaces sit on (docs/tvos-unified-experience.md hoofdstuk 8, 10.6,
/// 14.1 and 14.4).
///
/// The geometry *numbers* are already locked by
/// `test/widgets/overlay_sheet_geometry_test.dart`, which fase 4 wrote. What
/// was never asserted anywhere is the panel's cast shadow — the one piece of
/// the TV panel contract that says it floats rather than being a hole cut in
/// the page — and the focus lifecycle fase 5A generalised out of the source
/// picker. Both are here.

Widget _shell(WidgetBuilder body) => TranslationProvider(
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: monoTheme(dark: true),
    home: InputModeTracker(
      child: OverlaySheetHost(child: Builder(builder: body)),
    ),
  ),
);

OverlaySheetGeometry _resolve({
  required OverlaySheetPresentation presentation,
  required bool isTV,
  Size size = const Size(1038, 584),
}) => resolveOverlaySheetGeometry(
  presentation: presentation,
  viewport: size,
  alignment: Alignment.bottomCenter,
  isTV: isTV,
);

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.pumpAndSettle();
}

/// Focuses the control showing [label] and presses Select on it.
///
/// `FocusableWrapper` is a D-pad widget and carries no tap handler at all, so a
/// `tester.tap` on one of these silently does nothing — which is also the
/// honest way to drive a 10-foot surface in a test. Same helper the fase-4
/// picker tests use, for the same reason.
Future<void> _activateByLabel(WidgetTester tester, String label, {int index = 0}) async {
  final finder = find.text(label);
  final focus = Focus.maybeOf(tester.element(index == 0 ? finder.first : finder.at(index)), scopeOk: true)!;
  focus.requestFocus();
  await tester.pumpAndSettle();
  expect(focus.hasPrimaryFocus, isTrue, reason: 'the control under test must actually hold the focus');
  SelectKeyUpSuppressor.clearSuppression();
  await _press(tester, LogicalKeyboardKey.select);
}

void main() {
  // `SelectKeyUpSuppressor` is process-global: a test that activates something
  // leaves it armed, and the next test's first Select press would be eaten.
  setUp(SelectKeyUpSuppressor.clearSuppression);

  // These are 10-foot surfaces, and the overlay host only autofocuses on TV or
  // in keyboard mode (`_autoFocus`) — without the override the panel opens with
  // nothing focused and every focus assertion below would pass or fail for the
  // wrong reason.
  setUpAll(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));

  group('panel shadow is TV-panel-only', () {
    // Hoofdstuk 14.1's centred 10-foot modal has to read as standing in front
    // of a wall of posters. `monoTheme` sets `ColorScheme.shadow` to
    // transparent on purpose — Material elevation paints nothing in this app —
    // so a surface that should cast one says so explicitly through the
    // geometry, and nothing else in the app may inherit it.
    test('TV + panel casts a two-layer shadow', () {
      final shadows = _resolve(presentation: OverlaySheetPresentation.panel, isTV: true).shadows;
      expect(shadows, hasLength(2), reason: 'an ambient layer to separate, a contact layer to seat it');
      expect(shadows.every((s) => s.blurRadius > 0), isTrue);
      expect(shadows.every((s) => s.offset.dy > 0), isTrue, reason: 'lit from above, like the panel surface itself');
      expect(
        shadows.first.blurRadius,
        greaterThan(shadows.last.blurRadius),
        reason: 'the ambient layer is the wide one; a tight-only shadow reads as a border',
      );
    });

    test('TV + sheet keeps the existing compact geometry and casts nothing', () {
      final sheet = _resolve(presentation: OverlaySheetPresentation.sheet, isTV: true);
      expect(sheet.shadows, isEmpty, reason: 'a sheet flush against the bottom edge has no gap to cast into');
      expect(sheet.constraints.maxWidth, 400);
      expect(sheet.constraints.maxHeight, 400);
      expect(sheet.alignment, Alignment.bottomCenter);
    });

    // The iOS/macOS regression lock. `panel` off TV is the desktop/phone path
    // fase 4 did not touch and fase 5 must not either.
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      test('${size.width.toInt()}x${size.height.toInt()} off TV casts nothing', () {
        final panel = _resolve(presentation: OverlaySheetPresentation.panel, isTV: false, size: size);
        expect(panel.shadows, isEmpty);
      });
    }

    test('off TV a panel keeps its 560-wide centred box, unchanged by the TV branch', () {
      final panel = _resolve(presentation: OverlaySheetPresentation.panel, isTV: false, size: const Size(1440, 900));
      expect(panel.constraints.maxWidth, 560);
      expect(panel.alignment, Alignment.center);
      expect(panel.allowPointerAnchor, isFalse);
    });
  });

  group('launcher focus restore is one shared mechanism', () {
    late FocusNode launcher;

    setUp(() => launcher = FocusNode(debugLabel: 'launcher'));
    tearDown(() => launcher.dispose());

    /// The launcher is the control's *own* focus node, which is the shape
    /// production has: a header action or a card is what holds focus when it
    /// opens a panel. Wrapping the button in a separate `Focus` instead would
    /// test a node the app never restores to.
    Future<void> pumpLauncher(WidgetTester tester, {required Future<void> Function(BuildContext) open}) async {
      await tester.pumpWidget(
        _shell(
          (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                autofocus: true,
                focusNode: launcher,
                onPressed: () => open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(launcher.hasPrimaryFocus, isTrue);
    }

    testWidgets('closing the sort panel hands focus back to the launcher', (tester) async {
      await pumpLauncher(
        tester,
        open: (context) => showTvCatalogSortPanel(context, selected: UnifiedCatalogSort.titleAsc),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(launcher.hasPrimaryFocus, isFalse, reason: 'the panel took focus');

      await _activateByLabel(tester, t.common.close);
      expect(
        launcher.hasPrimaryFocus,
        isTrue,
        reason: 'hoofdstuk 14.4: closing restores the exact control that opened it',
      );
    });

    testWidgets('choosing an option also restores the launcher', (tester) async {
      UnifiedCatalogSort? chosen;
      await pumpLauncher(
        tester,
        open: (context) async => chosen = await showTvCatalogSortPanel(context, selected: UnifiedCatalogSort.titleAsc),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await _activateByLabel(tester, t.unifiedCatalog.sort.recentlyAdded);

      expect(chosen, UnifiedCatalogSort.recentlyAdded);
      expect(launcher.hasPrimaryFocus, isTrue);
    });

    // A picker or panel that ended in a route replacement has no control left
    // to go back to. The restore must notice, not throw.
    testWidgets('a launcher that left the tree is skipped rather than crashing', (tester) async {
      var showLauncher = true;
      late StateSetter setOuterState;

      await tester.pumpWidget(
        _shell(
          (context) => StatefulBuilder(
            builder: (context, setState) {
              setOuterState = setState;
              return Scaffold(
                body: Center(
                  child: showLauncher
                      ? ElevatedButton(
                          autofocus: true,
                          focusNode: launcher,
                          onPressed: () => showTvCatalogSortPanel(context, selected: UnifiedCatalogSort.titleAsc),
                          child: const Text('open'),
                        )
                      : const Text('gone'),
                ),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      setOuterState(() => showLauncher = false);
      await tester.pump();
      await _activateByLabel(tester, t.common.close);

      expect(tester.takeException(), isNull);
      expect(find.text('gone'), findsOneWidget);
    });
  });

  group('filter panel batches behind Apply', () {
    final libraries = <CatalogLibrary>[
      (
        serverId: ServerId('nas'),
        serverName: 'NAS',
        libraryId: '1',
        libraryTitle: 'Films 4K',
        backend: MediaBackend.plex,
      ),
      (
        serverId: ServerId('attic'),
        serverName: 'Zolder',
        libraryId: '2',
        libraryTitle: 'Movies',
        backend: MediaBackend.jellyfin,
      ),
    ];

    Future<UnifiedCatalogFilterSelection?> openPanel(
      WidgetTester tester, {
      UnifiedCatalogFilterSelection selection = UnifiedCatalogFilterSelection.empty,
      List<CatalogLibrary>? withLibraries,
      TvCatalogFilterSection section = TvCatalogFilterSection.status,
    }) async {
      UnifiedCatalogFilterSelection? result;
      var completed = false;
      await tester.pumpWidget(
        _shell(
          (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showTvCatalogFilterPanel(
                    context,
                    selection: selection,
                    capabilities: unifiedFilterCapabilitiesFor((withLibraries ?? libraries).map((l) => l.backend)),
                    libraries: withLibraries ?? libraries,
                    initialSection: section,
                    clientFor: (_) => null,
                  );
                  completed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      addTearDown(() => expect(completed || result == null, isTrue));
      return result;
    }

    testWidgets('a tick alone changes nothing until Apply', (tester) async {
      await openPanel(tester);
      await _activateByLabel(tester, t.unifiedCatalog.filters.unwatched);
      // Still open, still nothing returned: hoofdstuk 10.6's whole reason for
      // the Apply button is that the grid must not reload per remote click.
      expect(find.text(t.unifiedCatalog.filters.apply), findsOneWidget);
    });

    // The panel has no Close capsule: Menu, Back and Escape already close it,
    // and a third footer button of the same weight as Apply was what made the
    // first render read as a settings dialog. This asserts the surviving
    // contract — backing out does not apply the draft — through the gesture a
    // remote actually uses.
    testWidgets('backing out discards the draft', (tester) async {
      await tester.pumpWidget(_shell((context) => const SizedBox()));
      UnifiedCatalogFilterSelection? result;
      await tester.pumpWidget(
        _shell(
          (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => result = await showTvCatalogFilterPanel(
                  context,
                  selection: UnifiedCatalogFilterSelection.empty,
                  capabilities: unifiedFilterCapabilitiesFor(libraries.map((l) => l.backend)),
                  libraries: libraries,
                  initialSection: TvCatalogFilterSection.status,
                  clientFor: (_) => null,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await _activateByLabel(tester, t.unifiedCatalog.filters.unwatched);
      await _press(tester, LogicalKeyboardKey.escape);
      expect(find.text(t.unifiedCatalog.filters.apply), findsNothing, reason: 'the panel is gone');
      expect(result, isNull, reason: 'Menu/Back/Escape closes without applying');
    });

    testWidgets('Apply returns exactly what was ticked', (tester) async {
      UnifiedCatalogFilterSelection? result;
      await tester.pumpWidget(
        _shell(
          (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => result = await showTvCatalogFilterPanel(
                  context,
                  selection: UnifiedCatalogFilterSelection.empty,
                  capabilities: unifiedFilterCapabilitiesFor(libraries.map((l) => l.backend)),
                  libraries: libraries,
                  initialSection: TvCatalogFilterSection.servers,
                  clientFor: (_) => null,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Two rows carry this text: the Servers row's label, and the Libraries
      // row's secondary line naming the server its library lives on. The first
      // is the Servers section, which is the one this activates.
      await _activateByLabel(tester, 'NAS');
      await _activateByLabel(tester, t.unifiedCatalog.filters.apply);

      expect(result?.serverIds, {'nas'});
      expect(result?.watchState, UnifiedWatchFilter.all);
    });

    // Hoofdstuk 10.4's capability rule, seen from the panel: a backend that
    // cannot execute a refinement takes that category out of the rail
    // altogether, and one quiet line says something was left out. Greying the
    // category and apologising under it was the first build, and it is what put
    // three dead headings in front of the two categories that still worked.
    testWidgets('a backend that cannot filter omits genre, year and status, not servers', (tester) async {
      await openPanel(
        tester,
        withLibraries: [
          ...libraries,
          (
            serverId: ServerId('shed'),
            serverName: 'Schuur',
            libraryId: '3',
            libraryTitle: 'Archief',
            backend: MediaBackend.pleyaServer,
          ),
        ],
        section: TvCatalogFilterSection.servers,
      );

      for (final omitted in [
        t.unifiedCatalog.filters.genre,
        t.unifiedCatalog.filters.year,
        t.unifiedCatalog.filters.status,
      ]) {
        expect(find.text(omitted), findsNothing, reason: '$omitted cannot be executed, so it is not offered');
      }
      expect(find.text(t.unifiedCatalog.filters.someUnavailable), findsOneWidget);
      // The source categories are backend-independent — they are executed by
      // leaving a cursor out of the merge — so they stay live.
      expect(find.text(t.unifiedCatalog.filters.servers), findsOneWidget);
      expect(find.text(t.unifiedCatalog.filters.libraries), findsOneWidget);
      expect(find.text('Schuur'), findsWidgets);
      expect(find.text(t.unifiedCatalog.filters.apply), findsOneWidget);
    });

    // The other half of hoofdstuk 10.4's rule, and the reason omitting is safe:
    // a suppressed refinement is not applied, but the user's stored choice
    // survives the round trip, so excluding the server that suppressed it
    // brings both the category and the old selection back.
    testWidgets('an omitted category keeps its stored selection through Apply', (tester) async {
      UnifiedCatalogFilterSelection? result;
      final withPleyaServer = <CatalogLibrary>[
        ...libraries,
        (
          serverId: ServerId('shed'),
          serverName: 'Schuur',
          libraryId: '3',
          libraryTitle: 'Archief',
          backend: MediaBackend.pleyaServer,
        ),
      ];
      await tester.pumpWidget(
        _shell(
          (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => result = await showTvCatalogFilterPanel(
                  context,
                  selection: const UnifiedCatalogFilterSelection(
                    genres: {'Comedy'},
                    watchState: UnifiedWatchFilter.unwatched,
                  ),
                  capabilities: unifiedFilterCapabilitiesFor(withPleyaServer.map((l) => l.backend)),
                  libraries: withPleyaServer,
                  initialSection: TvCatalogFilterSection.servers,
                  clientFor: (_) => null,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await _activateByLabel(tester, t.unifiedCatalog.filters.apply);
      await tester.pumpAndSettle();

      expect(result?.genres, {'Comedy'}, reason: 'a suppressed refinement is not applied, but it is not thrown away');
      expect(result?.watchState, UnifiedWatchFilter.unwatched);
    });

    // The two-zone panel's whole traversal contract, on a remote that has no
    // pointer: RIGHT and Select go into the list, LEFT comes back out of it.
    //
    // Worth its own test because the first build deferred the entry to a
    // post-frame callback, and `addPostFrameCallback` does not schedule a
    // frame — on a settled panel, which is exactly what a panel is when the
    // user presses RIGHT, the callback never ran and the press did nothing.
    group('two-zone traversal', () {
      Future<void> open(WidgetTester tester) => openPanel(tester, section: TvCatalogFilterSection.servers);

      String? focusedLabel() => FocusManager.instance.primaryFocus?.debugLabel;

      testWidgets('RIGHT enters the options column', (tester) async {
        await open(tester);
        await _press(tester, LogicalKeyboardKey.arrowRight);
        expect(focusedLabel(), 'TvCatalogFilterOption0');
      });

      testWidgets('Select enters the options column too', (tester) async {
        await open(tester);
        await _press(tester, LogicalKeyboardKey.select);
        expect(focusedLabel(), 'TvCatalogFilterOption0');
      });

      testWidgets('LEFT out of the options returns to the category it belongs to', (tester) async {
        await open(tester);
        await _press(tester, LogicalKeyboardKey.arrowRight);
        await _press(tester, LogicalKeyboardKey.arrowLeft);
        expect(
          focusedLabel(),
          anyOf('TvCatalogFilterRail.servers', 'TvCatalogFilterInitialFocus'),
          reason: 'the active category is Servers, whichever node is carrying it',
        );
      });
    });

    // Opening on a category this source set cannot execute must not leave the
    // initial focus on nothing: the rail falls back to its first entry, which
    // is always one of the two unconditional source categories.
    testWidgets('opening on a suppressed category falls back to the first available one', (tester) async {
      await openPanel(
        tester,
        withLibraries: [
          ...libraries,
          (
            serverId: ServerId('shed'),
            serverName: 'Schuur',
            libraryId: '3',
            libraryTitle: 'Archief',
            backend: MediaBackend.pleyaServer,
          ),
        ],
        section: TvCatalogFilterSection.genre,
      );

      expect(find.text(t.unifiedCatalog.filters.genre), findsNothing);
      // Servers is first in the rail, so its rows are the ones on the right.
      expect(find.text('Schuur'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('sort labels', () {
    test('every sort has its own translated label', () {
      final labels = {for (final sort in UnifiedCatalogSort.values) sortLabel(sort)};
      expect(labels, hasLength(UnifiedCatalogSort.values.length), reason: 'no two sorts may read the same');
      expect(labels.any((l) => l.trim().isEmpty), isFalse);
    });
  });

  group('J15: selected versus focused on a sort/filter option row', () {
    // TvCatalogOptionRow's own doc: "selected and focused are independent:
    // the base says whether this is the answer, the sheen says whether this is
    // where the remote is, and a row carrying both has to read as both." The
    // checkmark is the part of that signal a widget test can see without
    // reading pixels — it must survive a focus change, in both directions.
    bool hasCheckmark(WidgetTester tester, String label) => tester
        .widgetList(
          find.descendant(
            of: find.ancestor(of: find.text(label), matching: find.byType(TvCatalogOptionRow)),
            matching: find.byIcon(Symbols.check_rounded),
          ),
        )
        .isNotEmpty;

    // The row's own `Focus` node (FocusableWrapper wraps one per row) —
    // needed so the arrow-down press below is proven to have actually moved
    // focus, not just left both rows' checkmarks unchanged because nothing
    // happened at all.
    bool rowHasFocus(WidgetTester tester, String label) => tester
        .widget<Focus>(find.ancestor(of: find.text(label), matching: find.byType(Focus)).first)
        .focusNode!
        .hasPrimaryFocus;

    testWidgets('the selected row keeps its checkmark after focus moves away from it', (tester) async {
      await tester.pumpWidget(
        _shell(
          (context) => ElevatedButton(
            autofocus: true,
            onPressed: () => showTvCatalogSortPanel(context, selected: UnifiedCatalogSort.titleAsc),
            child: const Text('open'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        hasCheckmark(tester, sortLabel(UnifiedCatalogSort.titleAsc)),
        isTrue,
        reason: 'the selected row starts focused too — both signals present at once',
      );
      expect(hasCheckmark(tester, sortLabel(UnifiedCatalogSort.titleDesc)), isFalse);

      // Move the remote off the selected row, onto a plain, unselected one.
      await _press(tester, LogicalKeyboardKey.arrowDown);

      expect(
        rowHasFocus(tester, sortLabel(UnifiedCatalogSort.titleDesc)),
        isTrue,
        reason: 'the press has to have actually moved focus, or the checkmark assertions below prove nothing',
      );

      expect(
        hasCheckmark(tester, sortLabel(UnifiedCatalogSort.titleAsc)),
        isTrue,
        reason: 'losing focus must not read as losing the selection',
      );
      expect(
        hasCheckmark(tester, sortLabel(UnifiedCatalogSort.titleDesc)),
        isFalse,
        reason: 'gaining focus must not read as gaining a selection nobody chose',
      );
    });
  });

  // J14, reclassified from "unresolved product contract" to "proof gap": the
  // panel's own doc comments (`_buildOptions`, `_zoneHeight`) already spell out
  // both rules below, and hoofdstuk 10.6 names Status/Genre/Jaar/Servers/
  // Bibliotheken as the panel's sections — what was missing was a regression
  // test for the two rules that were never exercised, not a missing decision.
  group('J14: empty panel sections', () {
    final library = (
      serverId: ServerId('nas'),
      serverName: 'NAS',
      libraryId: '1',
      libraryTitle: 'Films 4K',
      backend: MediaBackend.plex,
    );

    Future<void> openOnGenre(WidgetTester tester, {MediaServerClient? Function(String serverId)? clientFor}) async {
      await tester.pumpWidget(
        _shell(
          (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showTvCatalogFilterPanel(
                  context,
                  selection: UnifiedCatalogFilterSelection.empty,
                  capabilities: unifiedFilterCapabilitiesFor([library.backend]),
                  libraries: [library],
                  initialSection: TvCatalogFilterSection.genre,
                  clientFor: clientFor ?? (_) => null,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('a supported category with zero values shows noValues, not an unsupported state or a blank pane', (
      tester,
    ) async {
      await openOnGenre(tester);

      expect(
        find.text(t.unifiedCatalog.filters.genre),
        findsOneWidget,
        reason: 'Genre is capability-supported here — a zero-value result must not drop it from the rail',
      );
      expect(find.text(t.unifiedCatalog.filters.noValues), findsOneWidget);
      expect(
        find.text(t.unifiedCatalog.filters.someUnavailable),
        findsNothing,
        reason: 'that note is for a category the backend cannot execute at all — this one can, it just has nothing',
      );
      // The rest of the panel is intact: this is an explained empty section,
      // not a broken screen.
      expect(find.text(t.unifiedCatalog.filters.status), findsOneWidget);
      expect(find.text(t.unifiedCatalog.filters.servers), findsOneWidget);
      expect(find.text(t.unifiedCatalog.filters.apply), findsOneWidget);
    });

    testWidgets('the zone stays the same height with values as without them', (tester) async {
      await openOnGenre(tester);
      final emptyApplyY = tester.getTopLeft(find.text(t.unifiedCatalog.filters.apply)).dy;
      await _press(tester, LogicalKeyboardKey.escape);

      await openOnGenre(tester, clientFor: (_) => _GenreValuesClient());
      final filledApplyY = tester.getTopLeft(find.text(t.unifiedCatalog.filters.apply)).dy;

      expect(find.text('Comedy'), findsOneWidget, reason: 'the fake client did feed real values through');
      expect(
        filledApplyY,
        emptyApplyY,
        reason:
            'hoofdstuk 10.6/_zoneHeight: the zone is a fixed box, so filling it must not move the footer '
            'below it — a collapsing/expanding zone is exactly the layout jump this row guards against',
      );
    });
  });
}

/// Feeds one cached genre pair straight through `loadUnifiedFilterOptions`,
/// bypassing the Plex-only "categories without values" follow-up call this
/// panel doesn't need to prove J14.
class _GenreValuesClient implements MediaServerClient {
  @override
  Future<LibraryFilterResult> fetchLibraryFiltersWithValues(String libraryId) async => LibraryFilterResult(
    filters: const [],
    cachedValues: {
      'genre': [MediaFilterValue(key: 'g1', title: 'Comedy'), MediaFilterValue(key: 'g2', title: 'Drama')],
    },
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
