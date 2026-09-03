/// The TV library chooser: the fix for the one defect in the 2 September 2026
/// audit that was not about styling.
///
/// What the audit measured: `LibrariesProvider: Loaded 2 libraries` in the
/// bundle's `app.log`, one library on screen, and no way to the other. The
/// chain was closed and documented — `shouldUseSideNavigation` is
/// `isDesktop || isTV`, so on tvOS the app-bar title takes the static branch
/// and the dropdown that is the screen's only picker is never built, while the
/// sidebar that gives desktop its second route does not exist in the TV shell.
///
/// So these are reachability tests, not styling tests. Every visible library
/// gets a way in; hidden ones do not get a second route around Library
/// Visibility; and the capsule the viewer is standing in is marked.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/screens/libraries/tv_library_chooser.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/tv/tv_page_chip_bar.dart';

MediaLibrary lib(String id, String title, {MediaKind kind = MediaKind.movie, String? serverId, String? serverName}) =>
    MediaLibrary(
      id: id,
      backend: MediaBackend.plex,
      title: title,
      kind: kind,
      serverId: serverId,
      serverName: serverName,
    );

void main() {
  test('one library is no choice, so no chooser', () {
    expect(tvLibraryChooserVisible([lib('1', 'Movies')]), isFalse);
    expect(tvLibraryChooserVisible(const []), isFalse);
    expect(tvLibraryChooserVisible([lib('1', 'Movies'), lib('2', 'Shows')]), isTrue);
  });

  test('every visible library gets a capsule, and the open one is marked', () {
    final movies = lib('1', 'Movies');
    final shows = lib('2', 'Shows', kind: MediaKind.show);

    final chips = tvLibraryChooserChips(
      visibleLibraries: [movies, shows],
      selectedGlobalKey: shows.globalKey,
      onSelect: (_) {},
    );

    expect(chips.map((c) => c.label), ['Movies', 'Shows']);
    expect(chips.map((c) => c.selected), [false, true]);
    // Every capsule can be pressed, including the one already open — pressing
    // it reloads rather than dead-ending, which is what the mobile dropdown
    // does too.
    expect(chips.every((c) => c.onSelect != null), isTrue);
  });

  test('choosing hands back the library key the screen loads by', () {
    final movies = lib('1', 'Movies');
    final shows = lib('2', 'Shows', kind: MediaKind.show);
    final chosen = <String>[];

    tvLibraryChooserChips(
      visibleLibraries: [movies, shows],
      selectedGlobalKey: movies.globalKey,
      onSelect: chosen.add,
    )[1].onSelect!();

    expect(chosen, [shows.globalKey]);
  });

  test('a hidden library has no capsule: the chooser is not a second route around visibility', () {
    final movies = lib('1', 'Movies');
    final shows = lib('2', 'Shows', kind: MediaKind.show);

    // The screen passes its already-filtered `visibleLibraries`; this is the
    // contract that keeps that filtering meaningful.
    final chips = tvLibraryChooserChips(
      visibleLibraries: [movies],
      selectedGlobalKey: movies.globalKey,
      onSelect: (_) {},
    );

    expect(chips.map((c) => c.key), ['library_${movies.globalKey}']);
    expect(chips.any((c) => c.key.contains(shows.id)), isFalse);
  });

  test('the server name appears only when it is what tells two libraries apart', () {
    final oneServer = tvLibraryChooserChips(
      visibleLibraries: [
        lib('1', 'Movies', serverId: 'a', serverName: 'Zolder'),
        lib('2', 'Shows', serverId: 'a', serverName: 'Zolder'),
      ],
      selectedGlobalKey: null,
      onSelect: (_) {},
    );
    expect(oneServer.map((c) => c.label), ['Movies', 'Shows']);

    final twoServers = tvLibraryChooserChips(
      visibleLibraries: [
        lib('1', 'Movies', serverId: 'a', serverName: 'Zolder'),
        lib('1', 'Movies', serverId: 'b', serverName: 'Kantoor'),
      ],
      selectedGlobalKey: null,
      onSelect: (_) {},
    );
    expect(twoServers.map((c) => c.label), ['Movies · Zolder', 'Movies · Kantoor']);
  });

  testWidgets('the declared height matches the drawn one, so the tabs below are not clipped', (tester) async {
    // A `PreferredSize` cannot measure its child: the library header reserves
    // `TvPageChipBar.heightFor` for this row, and if that number drifts from
    // what the capsules actually draw, the tab line under it loses its bottom.
    final nodes = FocusMemoryTracker(debugLabelPrefix: 'test');
    addTearDown(nodes.dispose);

    late double declared;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              declared = TvPageChipBar.heightFor(context);
              return Align(
                alignment: Alignment.topLeft,
                child: TvPageChipBar(
                  singleLine: true,
                  nodes: nodes,
                  chips: tvLibraryChooserChips(
                    visibleLibraries: [
                      lib('1', 'Movies'),
                      lib('2', 'Shows', kind: MediaKind.show),
                    ],
                    selectedGlobalKey: null,
                    onSelect: (_) {},
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(TvPageChipBar)).height, moreOrLessEquals(declared, epsilon: 1.0));
  });
}
