/// The iPhone "Bibliotheken" picker (northstar 15). Same split as
/// `tv_libraries_screen_test.dart` documents for TV: the shared
/// `LibrariesScreen` this replaces on the phone always auto-selected a
/// library and showed its content directly — this screen's own negative
/// control is that it shows a card grid instead, with no library
/// auto-selected.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/screens/libraries/libraries_screen.dart';
import 'package:pleya/screens/libraries/mobile_libraries_screen.dart';
import 'package:pleya/screens/settings/library_visibility_screen.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
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
  late LibrariesProvider libraries;
  late HiddenLibrariesProvider hidden;
  late int backTaps;

  setUp(() {
    resetSharedPreferencesForTest();
    backTaps = 0;
  });

  tearDown(() {
    libraries.dispose();
    hidden.dispose();
  });

  Future<void> pump(WidgetTester tester, List<MediaLibrary> fixture, {Size size = const Size(393, 852)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Same singleton-race avoidance `tv_libraries_screen_test.dart` documents:
    // resolve `StorageService` once, sequentially, before the providers that
    // touch it concurrently.
    await tester.runAsync(() async {
      await StorageService.getInstance();
      await SettingsService.getInstance();
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
            home: MobileLibrariesScreen(onBack: () => backTaps++),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final filmsNas = _lib('m1', serverId: ServerId('nas'), serverName: 'NAS', title: 'Films 4K');
  final seriesNas = _lib('s1', serverId: ServerId('nas'), serverName: 'NAS', kind: MediaKind.show, title: 'Series 4K');
  final moviesJelly = _lib(
    'm2',
    serverId: ServerId('jelly'),
    serverName: 'Jellyfin thuis',
    backend: MediaBackend.jellyfin,
    title: 'Movies',
  );

  testWidgets('shows a card per visible library and no auto-selected content', (tester) async {
    await pump(tester, [filmsNas, seriesNas]);

    expect(find.text('Films 4K'), findsOneWidget);
    expect(find.text('Series 4K'), findsOneWidget);
    // Northstar 15 is a picker: no `LibrariesScreen` tab content underneath.
    expect(find.byType(LibrariesScreen), findsNothing);
  });

  testWidgets('one server draws no filter chips', (tester) async {
    await pump(tester, [filmsNas, seriesNas]);

    expect(find.text(t.libraries.all), findsNothing);
  });

  testWidgets('two servers draw filter chips and filtering hides the other server', (tester) async {
    await pump(tester, [filmsNas, moviesJelly]);

    expect(find.text(t.libraries.all), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'NAS'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Jellyfin thuis'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Jellyfin thuis'));
    await tester.pumpAndSettle();

    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Films 4K'), findsNothing);
  });

  testWidgets('hidden libraries stay off the grid', (tester) async {
    await pump(tester, [filmsNas, seriesNas]);
    await tester.runAsync(() => hidden.hideLibrary(seriesNas.globalKey));
    await tester.pumpAndSettle();

    expect(find.text('Films 4K'), findsOneWidget);
    expect(find.text('Series 4K'), findsNothing);
  });

  testWidgets('Bewerken opens library visibility management', (tester) async {
    await pump(tester, [filmsNas]);

    await tester.tap(find.text(t.common.edit));
    await tester.pumpAndSettle();

    expect(find.byType(LibraryVisibilityScreen), findsOneWidget);
  });

  testWidgets('the back button reaches My Pleya', (tester) async {
    await pump(tester, [filmsNas]);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(backTaps, 1);
  });

  testWidgets('tapping a card persists the selection and opens the shared library content', (tester) async {
    await pump(tester, [filmsNas, seriesNas]);

    // Not `pumpAndSettle`: the real `LibrariesScreen` this pushes into runs its
    // own focus-memory and retry timers that never quiesce in a bare test
    // harness (it is not this screen's job to fake that whole surface). The
    // tap handler's `StorageService` round trip runs detached from the tap
    // gesture itself, so a couple of plain pumps — not settle — give it room
    // to finish before the push is asserted.
    await tester.tap(find.text('Series 4K'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(LibrariesScreen), findsOneWidget);
    final storage = await StorageService.getInstance();
    expect(storage.getSelectedLibraryKey(), seriesNas.globalKey);
  });
}
