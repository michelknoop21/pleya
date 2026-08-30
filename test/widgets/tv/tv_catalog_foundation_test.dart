import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/dpad_navigator.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
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

    testWidgets('Close discards the draft', (tester) async {
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
      await _activateByLabel(tester, t.common.close);
      expect(result, isNull, reason: 'Menu/Close closes without applying');
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
    // cannot execute genre and year makes those sections say so rather than
    // offering choices that would silently not apply.
    testWidgets('a backend that cannot filter suppresses genre and year, not servers', (tester) async {
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

      expect(find.text(t.unifiedCatalog.filters.unsupported), findsNWidgets(3));
      // The source sections are backend-independent — they are executed by
      // leaving a cursor out of the merge — so they stay live.
      expect(find.text('Schuur'), findsWidgets);
      expect(find.text(t.unifiedCatalog.filters.apply), findsOneWidget);
    });
  });

  group('sort labels', () {
    test('every sort has its own translated label', () {
      final labels = {for (final sort in UnifiedCatalogSort.values) sortLabel(sort)};
      expect(labels, hasLength(UnifiedCatalogSort.values.length), reason: 'no two sorts may read the same');
      expect(labels.any((l) => l.trim().isEmpty), isFalse);
    });
  });
}
