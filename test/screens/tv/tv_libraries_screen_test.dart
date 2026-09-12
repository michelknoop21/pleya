/// Mijn Pleya ▸ Bibliotheken on TV, as bronbeheer instead of a second
/// browsing screen (LIB7, DEC-092).
///
/// Two halves, the same split `tv_my_pleya_screen_test.dart` uses. Which
/// actions a library row offers is a pure function, tested as one. What the
/// screen actually shows is DEC-092's own negative control: no Aanbevolen or
/// Bladeren tab exists at all, and every catalogable library row can reach
/// "Openen in catalogus" — this was never true of the shared `LibrariesScreen`
/// this replaces on TV, which drew exactly those two tabs.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/screens/tv/sections/tv_libraries_screen.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/tv/tv_panel_primitives.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

MediaLibrary _lib(
  String id, {
  required ServerId serverId,
  String? serverName,
  MediaKind kind = MediaKind.movie,
  MediaBackend backend = MediaBackend.plex,
  String title = 'L',
}) => MediaLibrary(id: id, backend: backend, title: title, kind: kind, serverId: serverId, serverName: serverName);

void main() {
  // ---------------------------------------------------------------------------
  // Which actions a row offers (mockup 27 B)
  // ---------------------------------------------------------------------------

  group('tvLibraryActionsFor', () {
    test('a Plex movie library gets the full set, in mockup order', () {
      final actions = tvLibraryActionsFor(_lib('1', serverId: ServerId('s')));
      expect(actions, [
        TvLibraryAction.openInCatalog,
        TvLibraryAction.refreshMetadata,
        TvLibraryAction.scan,
        TvLibraryAction.toggleVisibility,
        TvLibraryAction.analyze,
        TvLibraryAction.emptyTrash,
      ]);
    });

    test('a Jellyfin show library skips the Plex-only admin actions', () {
      final actions = tvLibraryActionsFor(
        _lib('1', serverId: ServerId('s'), kind: MediaKind.show, backend: MediaBackend.jellyfin),
      );
      expect(actions, [
        TvLibraryAction.openInCatalog,
        TvLibraryAction.refreshMetadata,
        TvLibraryAction.toggleVisibility,
      ]);
    });

    test('a music library has no catalog to open', () {
      final actions = tvLibraryActionsFor(_lib('1', serverId: ServerId('s'), kind: MediaKind.artist));
      expect(actions, isNot(contains(TvLibraryAction.openInCatalog)));
    });

    test('every library can still be shown or hidden, regardless of kind', () {
      for (final kind in MediaKind.values) {
        expect(
          tvLibraryActionsFor(_lib('1', serverId: ServerId('s'), kind: kind)),
          contains(TvLibraryAction.toggleVisibility),
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // The screen itself
  // ---------------------------------------------------------------------------

  group('the bronbeheer screen', () {
    late LibrariesProvider libraries;
    late HiddenLibrariesProvider hidden;

    setUp(() {
      resetSharedPreferencesForTest();
    });

    tearDown(() {
      libraries.dispose();
      hidden.dispose();
    });

    Future<void> pump(WidgetTester tester, List<MediaLibrary> fixture, {Size size = const Size(1280, 720)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Everything storage-backed runs inside one real async zone, and the
      // singleton is resolved *before* anything else can race it.
      // `BaseSharedPreferencesService.initializeInstance` registers its
      // instance in `_instances` before awaiting `sharedCache()` — so two
      // first-time callers racing for the same singleton (here:
      // `HiddenLibrariesProvider`'s constructor kicking off its own
      // storage-backed init, concurrently with `updateLibraryOrder`'s own
      // `StorageService.getInstance()`) can have the second one see the
      // instance already registered and return it before its `_cache` is
      // actually assigned — a `LateInitializationError` on first synchronous
      // read. Resolving the singleton once, sequentially, first, closes that
      // window.
      await tester.runAsync(() async {
        await StorageService.getInstance();
        libraries = LibrariesProvider();
        hidden = HiddenLibrariesProvider();
        await libraries.updateLibraryOrder(fixture);
      });

      await tester.pumpWidget(
        TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<LibrariesProvider>.value(value: libraries),
              ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hidden),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: monoTheme(dark: true),
              home: const InputModeTracker(child: Scaffold(body: TvLibrariesScreen())),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    TvLibrariesScreenState state(WidgetTester tester) =>
        tester.state<TvLibrariesScreenState>(find.byType(TvLibrariesScreen));

    Future<void> selectRow(WidgetTester tester, String libraryGlobalKey) async {
      state(tester).loadLibraryByKey(libraryGlobalKey);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
    }

    /// `TvPanelButton` is D-pad only — no `GestureDetector`, so `tester.tap`
    /// never reaches its `onPressed`. This is the same "find the node, focus
    /// it, press Select" shape as `tv_my_pleya_screen_test.dart`'s `press`
    /// helper, just reading the node off the button widget itself rather than
    /// off a `FocusMemoryTracker` key.
    Future<void> pressPanelButton(WidgetTester tester, String label) async {
      final button = tester.widget<TvPanelButton>(find.widgetWithText(TvPanelButton, label));
      button.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
    }

    final movie = _lib('m1', serverId: ServerId('srv'), serverName: 'Pleya', title: 'Films');
    final show = _lib('s1', serverId: ServerId('srv'), serverName: 'Pleya', kind: MediaKind.show, title: 'Series');
    final music = _lib('a1', serverId: ServerId('srv'), serverName: 'Pleya', kind: MediaKind.artist, title: 'Concert');

    testWidgets('draws no Aanbevolen or Bladeren tab — DEC-092 negative control', (tester) async {
      await pump(tester, [movie, show]);

      // The shared `LibrariesScreen` this replaces on TV always drew these two
      // tabs; this screen has no tab bar at all.
      expect(find.text(t.libraries.tabs.recommended), findsNothing);
      expect(find.text(t.libraries.tabs.browse), findsNothing);
      expect(find.text(t.libraries.tabs.collections), findsNothing);
      expect(find.text(t.libraries.tabs.playlists), findsNothing);
    });

    testWidgets('every row shows its title, grouped under its server', (tester) async {
      await pump(tester, [movie, show]);

      expect(find.text('Films'), findsOneWidget);
      expect(find.text('Series'), findsOneWidget);
      expect(find.text('PLEYA'), findsOneWidget);
    });

    testWidgets('a movie row opens the sheet with "Openen in Alle films"', (tester) async {
      await pump(tester, [movie, show]);

      await selectRow(tester, movie.globalKey);

      expect(find.text(t.libraries.openInAllMovies), findsOneWidget);
      expect(find.text(t.libraries.hideLibrary), findsOneWidget);
    });

    testWidgets('a show row opens the sheet with "Openen in Alle series"', (tester) async {
      await pump(tester, [movie, show]);

      await selectRow(tester, show.globalKey);

      expect(find.text(t.libraries.openInAllSeries), findsOneWidget);
    });

    testWidgets('a music row has no catalog action — nothing to browse it with', (tester) async {
      await pump(tester, [movie, music]);

      await selectRow(tester, music.globalKey);

      expect(find.text(t.libraries.openInAllMovies), findsNothing);
      expect(find.text(t.libraries.openInAllSeries), findsNothing);
      expect(find.text(t.libraries.hideLibrary), findsOneWidget);
    });

    testWidgets('Ordenen opens reorder mode, Klaar returns to the list', (tester) async {
      await pump(tester, [movie, show]);

      expect(find.text(t.libraries.reorder), findsOneWidget);
      await pressPanelButton(tester, t.libraries.reorder);

      expect(find.text(t.libraries.reorderIntro), findsOneWidget);
      expect(find.text(t.unifiedCatalog.homeRows.done), findsOneWidget);

      await pressPanelButton(tester, t.unifiedCatalog.homeRows.done);

      expect(find.text(t.libraries.reorderIntro), findsNothing);
      expect(find.text('Films'), findsOneWidget);
    });

    testWidgets('DOWN from Klaar reaches the first reorder row', (tester) async {
      await pump(tester, [movie, show]);

      await pressPanelButton(tester, t.libraries.reorder);
      final button = tester.widget<TvPanelButton>(find.widgetWithText(TvPanelButton, t.unifiedCatalog.homeRows.done));
      button.focusNode!.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus?.debugLabel, movie.globalKey);
    });

    testWidgets('a single library offers no Ordenen — nothing to reorder', (tester) async {
      await pump(tester, [movie]);

      expect(find.text(t.libraries.reorder), findsNothing);
    });
  });
}
