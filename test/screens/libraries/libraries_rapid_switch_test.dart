/// LIB2: switching library twice in quick succession must settle on the second
/// library, whole.
///
/// `_loadLibraryContent` commits the new library synchronously and then
/// suspends on storage. Everything after that await — persisting the selected
/// key, restoring the tab this library was last left on, the focus hand-off —
/// used to run unconditionally, so an invocation the user had already
/// abandoned came back and wrote over the one that replaced it. What you saw
/// on TV was the second library's content under the first library's tab.
///
/// The race is driven, not slept through. `BaseSharedPreferencesService.onMutation`
/// is awaited inside every preference write, so holding it open for one library
/// suspends exactly that invocation at exactly the boundary the bug lives on,
/// while the other one runs to completion. No timers, no pump durations.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/mixins/refreshable.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/libraries/libraries_screen.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/focusable_tab_chip.dart';
import 'package:pleya/widgets/library_header_bar.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

MediaLibrary _lib(String id, String title) => MediaLibrary(
  id: id,
  backend: MediaBackend.plex,
  title: title,
  kind: MediaKind.movie,
  serverId: 's1',
  serverName: 'Server',
);

/// Where the screen starts, so switching to [_films] is a real library change
/// and not a reselect of what is already open.
final _start = _lib('1', 'Start');
final _films = _lib('2', 'Films');
final _series = _lib('3', 'Series');

/// Each library is left on a different tab, which is what makes a stale
/// restore visible: the tab on screen names the library whose invocation ran
/// last, independent of which library the page is actually showing.
const _filmsTab = 'playlists';
const _seriesTab = 'collections';

/// The page heading — the library that is actually open.
String? _openLibrary(WidgetTester tester) =>
    tester.widgetList<LibraryHeaderTitle>(find.byType(LibraryHeaderTitle)).map((w) => w.title).firstOrNull;

/// The tab the header line is on.
String? _openTab(WidgetTester tester) => tester
    .widgetList<FocusableTabChip>(find.byType(FocusableTabChip))
    .where((chip) => chip.isSelected)
    .map((chip) => chip.label)
    .firstOrNull;

class _Harness {
  _Harness(this.tester, this.libraries, this.storage);

  final WidgetTester tester;
  final LibrariesProvider libraries;
  final StorageService storage;

  /// Libraries whose selected-key write is currently suspended, and the gate
  /// that releases them.
  final _gates = <String, Completer<void>>{};

  /// Hold the tail of the next `_loadLibraryContent(globalKey)` at its first
  /// await past the synchronous commit. One shot: a later invocation for the
  /// same library runs through, which is what the A → B → A case needs.
  Completer<void> hold(String globalKey) => _gates[globalKey] = Completer<void>();

  void install() {
    BaseSharedPreferencesService.onMutation = (mutation) async {
      if (!mutation.key.endsWith('selected_library_key')) return;
      final gate = _gates.remove(mutation.value);
      if (gate != null) await gate.future;
    };
  }

  /// Switch library the way the TV chooser, the mobile dropdown and the side
  /// nav all do. Does not wait for the tail: a held invocation never finishes.
  Future<void> select(String globalKey) async {
    final state = tester.state(find.byType(LibrariesScreen)) as LibraryLoadable;
    await tester.runAsync(() async {
      state.loadLibraryByKey(globalKey);
      await _drain();
    });
    await tester.pump();
    await tester.pump();
  }

  Future<void> release(Completer<void> gate) async {
    await tester.runAsync(() async {
      gate.complete();
      await _drain();
    });
    await tester.pump();
    await tester.pump();
  }

  Future<void> settle() async {
    await tester.runAsync(_drain);
    await tester.pump();
    await tester.pump();
  }

  /// Let the microtasks and the in-memory preference channel out of the test's
  /// fake async. Everything under test is microtask- and channel-ordered, so
  /// this is deterministic — it is not a wait for a race to fall the right way.
  static Future<void> _drain() async {
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  String? get persistedLibrary => storage.getSelectedLibraryKey();
}

Future<_Harness> _pumpScreen(WidgetTester tester) async {
  late StorageService storage;
  await tester.runAsync(() async {
    await SettingsService.getInstance();
    storage = await StorageService.getInstance();
    // Where the screen opens, and where each library was last left.
    await storage.saveSelectedLibraryKey(_start.globalKey);
    await storage.saveLibraryTab(_films.globalKey, _filmsTab);
    await storage.saveLibraryTab(_series.globalKey, _seriesTab);
  });

  final manager = MultiServerManager();
  final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
  addTearDown(multiServer.dispose);
  final libraries = LibrariesProvider();
  final hidden = HiddenLibrariesProvider();
  await tester.runAsync(() => hidden.ensureInitialized());
  libraries.debugSetLibraries([_start, _films, _series]);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: libraries),
        ChangeNotifierProvider.value(value: hidden),
        ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
      ],
      child: MaterialApp(theme: monoTheme(dark: true), home: const LibrariesScreen()),
    ),
  );

  final harness = _Harness(tester, libraries, storage);
  await harness.settle();
  // The screen opened on the library it had saved, and on that library's tab.
  expect(_openLibrary(tester), 'Start');
  harness.install();
  return harness;
}

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
  });
  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    BaseSharedPreferencesService.onMutation = null;
  });

  testWidgets('a library abandoned mid-load does not restore its own tab over the one that replaced it', (
    tester,
  ) async {
    final harness = await _pumpScreen(tester);

    // Films is picked and suspends on storage; Series is picked before it
    // returns and runs all the way through.
    final films = harness.hold(_films.globalKey);
    await harness.select(_films.globalKey);
    await harness.select(_series.globalKey);
    expect(_openLibrary(tester), 'Series');
    expect(_openTab(tester), 'Collections', reason: 'Series opens on the tab Series was left on');

    // Films comes back, to a screen it no longer owns.
    await harness.release(films);

    expect(_openLibrary(tester), 'Series');
    expect(_openTab(tester), 'Collections', reason: "the abandoned library must not restore Films' tab");
    expect(harness.persistedLibrary, _series.globalKey);
  });

  testWidgets('switching away and back settles on the last intent, not on the invocation that resumes last', (
    tester,
  ) async {
    final harness = await _pumpScreen(tester);

    // A → B → A, with the first A resuming last. The key it carries is
    // current again by then, so a guard that only compares keys lets it
    // through; this is the case that decides the ownership rule.
    final firstFilms = harness.hold(_films.globalKey);
    await harness.select(_films.globalKey);
    await harness.select(_series.globalKey);
    await harness.select(_films.globalKey);
    expect(_openLibrary(tester), 'Films');
    expect(_openTab(tester), 'Playlists');

    await harness.release(firstFilms);

    expect(_openLibrary(tester), 'Films');
    expect(_openTab(tester), 'Playlists');
    expect(harness.persistedLibrary, _films.globalKey);
  });

  testWidgets('a library that finished loading still gets switched away from normally', (tester) async {
    final harness = await _pumpScreen(tester);

    await harness.select(_films.globalKey);
    await harness.settle();
    expect(_openLibrary(tester), 'Films');
    expect(_openTab(tester), 'Playlists');
    expect(harness.persistedLibrary, _films.globalKey);

    await harness.select(_series.globalKey);
    await harness.settle();
    expect(_openLibrary(tester), 'Series');
    expect(_openTab(tester), 'Collections');
    expect(harness.persistedLibrary, _series.globalKey);
  });

  testWidgets('a user selection outranks the fallback LIB1 reconciliation was still loading', (tester) async {
    final harness = await _pumpScreen(tester);

    // The open library disappears. Reconciliation falls back to the first
    // surviving one (Films) and loads it exactly as a press would — so it is a
    // writer on the same state, and the user beating it to Series must win.
    final films = harness.hold(_films.globalKey);
    harness.libraries.debugSetLibraries([_films, _series]);
    await harness.settle();
    expect(_openLibrary(tester), 'Films', reason: 'the fallback committed its library before suspending');

    await harness.select(_series.globalKey);
    await harness.release(films);

    expect(_openLibrary(tester), 'Series');
    expect(_openTab(tester), 'Collections');
    expect(harness.persistedLibrary, _series.globalKey);
  });
}
