import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/focus/dpad_navigator.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
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

/// A client that answers exactly one question: which filter values a library
/// has. That is the only method `loadUnifiedFilterOptions` calls on a non-Plex
/// client, so this is the whole seam and not a stand-in for a backend.
///
/// [values] null means "never answers", which is how the loading state is
/// reached without a timer or a real network.
class _FilterValuesClient implements MediaServerClient {
  _FilterValuesClient({required this.genres});

  /// Null hangs forever; a list resolves immediately.
  final List<String>? genres;

  @override
  Future<LibraryFilterResult> fetchLibraryFiltersWithValues(String libraryId) {
    final answer = genres;
    if (answer == null) return Completer<LibraryFilterResult>().future;
    return Future.value(
      LibraryFilterResult(
        filters: const [],
        cachedValues: {
          'genre': [for (final genre in answer) MediaFilterValue(key: genre, title: genre)],
        },
      ),
    );
  }

  @override
  MediaBackend get backend => MediaBackend.jellyfin;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.jellyfin;

  @override
  ServerId get serverId => ServerId('nas');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

  // J14: lege panelsecties. Het register hield deze rij als klasse C aan met
  // als reden dat geen enkel hoofdstuk "een panelsectie" definieert. Die audit
  // keek naar de scope-picker en het contextmenu; het filterpaneel implementeert
  // de invariant wél, in drie stukken die hieronder elk hun eigen test krijgen.
  //
  // Het productgedrag verandert hier niet. Dit is bewijs voor wat er al staat.
  group('J14: empty panel sections', () {
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

    // Plex plus Jellyfin is hoofdstuk 28's canonieke fixture, en die set
    // ondersteunt élke categorie. Dat is precies wat deze rij nodig heeft: een
    // categorie die ondersteund is en tóch nul waarden heeft, zodat "leeg" niet
    // met "niet ondersteund" verward kan worden.
    final capabilities = unifiedFilterCapabilitiesFor(libraries.map((l) => l.backend));

    /// Opens the production panel on [section].
    ///
    /// [genres] null gives a client that never answers (the loading state);
    /// an empty list gives no client at all, which is how a real fan-out that
    /// found nothing looks from here; a non-empty list gives those genres.
    Future<void> open(
      WidgetTester tester, {
      required TvCatalogFilterSection section,
      List<String> genres = const [],
      bool hangs = false,
      bool settle = true,
    }) async {
      // A bare shell first, so a panel from a previous state in the same test
      // is really gone. `OverlaySheetHost` keeps its element across a
      // `pumpWidget` of the same shape, and its entry with it, and the second
      // tap would then land on an overlay instead of on the button.
      await tester.pumpWidget(_shell((context) => const SizedBox()));
      await tester.pumpWidget(
        _shell(
          (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showTvCatalogFilterPanel(
                  context,
                  selection: UnifiedCatalogFilterSelection.empty,
                  capabilities: capabilities,
                  libraries: libraries,
                  initialSection: section,
                  clientFor: (_) => hangs
                      ? _FilterValuesClient(genres: null)
                      : (genres.isEmpty ? null : _FilterValuesClient(genres: genres)),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
        await tester.pump();
      }
    }

    /// Renders the production panel directly, under a maximum size rather than
    /// a fixed one.
    ///
    /// Not through `showTvCatalogFilterPanel` like the test above, and
    /// deliberately: the geometry claim is about the panel's own zone, so the
    /// overlay's entry animation and its viewport-derived sizing are noise that
    /// would have to be identical in both states rather than reasoned about.
    ///
    /// The **maximum** matters more than it looks. A fixed-height box would
    /// hand the zone its height from outside, and then this test passes with
    /// `_zoneHeight` deleted — which is exactly what the negative control
    /// caught on the first attempt. Under a loose constraint the panel's Column
    /// is `MainAxisSize.min`, so a zone that sized itself to its content really
    /// does shrink the panel and pull the footer up, and the assertions below
    /// have something to fail on.
    Future<void> render(WidgetTester tester, {required List<String> genres}) async {
      await tester.pumpWidget(
        _shell(
          (context) => Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900, maxHeight: 500),
                child: TvCatalogFilterPanel(
                  // A fresh State per render. The panel loads its values once,
                  // in `initState`, and has no reason to reload on an update —
                  // so without a distinct key the second render would keep the
                  // first one's genres and never reach the empty state at all.
                  key: ValueKey(genres.join('|')),
                  selection: UnifiedCatalogFilterSelection.empty,
                  capabilities: capabilities,
                  libraries: libraries,
                  initialSection: TvCatalogFilterSection.genre,
                  onApply: (_) {},
                  onClose: () {},
                  clientFor: (_) => genres.isEmpty ? null : _FilterValuesClient(genres: genres),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// The zone `_zoneHeight` sizes: the box that holds the rail and the
    /// options together, and the thing that must not resize when a category
    /// turns out to be empty.
    ///
    /// Reached through the `LayoutBuilder` rather than by key, because there is
    /// no key and adding one would be a production change this row does not
    /// need. It is the first `SizedBox` under that builder, which is the one
    /// the height is set on.
    Finder zone() => find.descendant(of: find.byType(LayoutBuilder), matching: find.byType(SizedBox)).first;

    testWidgets('a supported category with no values shows the no-values line, not a void', (tester) async {
      await open(tester, section: TvCatalogFilterSection.genre);

      // The category survives: it is supported, so it is in the rail even
      // though it has nothing to offer right now.
      expect(
        find.text(t.unifiedCatalog.filters.genre),
        findsOneWidget,
        reason: 'an empty value set is not the same as an unexecutable category',
      );
      // And it is still the *active* one. `_resolveInitialSection` falls back
      // only for a category this source set cannot execute; falling back because
      // the values happen to be empty would drop the user somewhere they never
      // asked to be.
      expect(
        find.text(t.unifiedCatalog.filters.noValues),
        findsOneWidget,
        reason: 'the content zone says why it is empty rather than being empty',
      );
      expect(
        find.text(t.unifiedCatalog.filters.someUnavailable),
        findsNothing,
        reason: 'nothing was left out of the rail, so nothing may apologise for it',
      );
      // A control from another category would mean the panel had quietly
      // switched away from genre.
      expect(find.text(t.unifiedCatalog.filters.unwatched), findsNothing, reason: 'no fallback to Status');
    });

    testWidgets('the no-values line is inside the zone, which keeps its size', (tester) async {
      // The same configuration twice, and only the value set differs.
      await render(tester, genres: const ['Drama', 'Komedie']);
      expect(find.text('Drama'), findsOneWidget, reason: 'state A has to really have values, or B proves nothing');
      final filled = tester.getSize(zone());
      final filledApply = tester.getTopLeft(find.text(t.unifiedCatalog.filters.apply));

      final filledPanel = tester.getSize(find.byType(TvCatalogFilterPanel));

      await render(tester, genres: const []);
      expect(find.text(t.unifiedCatalog.filters.noValues), findsOneWidget);
      expect(find.text('Drama'), findsNothing, reason: 'state B really is the empty one');
      final empty = tester.getSize(zone());

      expect(
        tester.getSize(find.byType(TvCatalogFilterPanel)),
        filledPanel,
        reason: 'the panel itself must not shrink around an empty category',
      );

      expect(
        empty.height,
        filled.height,
        reason: 'a panel sized to its active category jumps every time the focus walks the rail',
      );
      // Equal-but-collapsed would pass the line above, so the zone is also
      // checked against what it holds: the note alone is a single line of text,
      // and the zone is several rows tall by contract.
      final note = tester.getSize(find.text(t.unifiedCatalog.filters.noValues));
      expect(empty.height, greaterThan(note.height * 3), reason: 'the zone did not collapse onto its content');

      // The note lives inside that fixed box rather than next to it. Compared
      // edge by edge rather than with `Rect.contains`, which excludes its own
      // right and bottom edge and would fail a note that sits flush against one.
      final zoneRect = tester.getRect(zone());
      final noteRect = tester.getRect(find.text(t.unifiedCatalog.filters.noValues));
      expect(noteRect.top, greaterThanOrEqualTo(zoneRect.top));
      expect(noteRect.bottom, lessThanOrEqualTo(zoneRect.bottom));
      expect(noteRect.left, greaterThanOrEqualTo(zoneRect.left));
      expect(noteRect.right, lessThanOrEqualTo(zoneRect.right));

      // And nothing under the zone moved, which is the part the user sees.
      expect(
        tester.getTopLeft(find.text(t.unifiedCatalog.filters.apply)),
        filledApply,
        reason: 'the footer is where the empty state would push it if the zone gave way',
      );
    });

    testWidgets('loading and no-values are different states, not one blank', (tester) async {
      // The seam already exists: `clientFor` is injectable and
      // `_isLoadingOptions` is set synchronously in initState, so a client that
      // never answers holds the panel in its loading state with no timer.
      await open(tester, section: TvCatalogFilterSection.genre, hangs: true, settle: false);

      expect(find.text(t.common.loading), findsOneWidget);
      expect(
        find.text(t.unifiedCatalog.filters.noValues),
        findsNothing,
        reason: '"there are none" is a different claim from "we have not looked yet"',
      );
    });
  });
}
