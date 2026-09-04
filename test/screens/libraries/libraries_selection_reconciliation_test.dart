/// LIB1: the Libraries page must never end up blank because the library it had
/// selected is no longer there.
///
/// [LibrariesProvider] swaps its whole list on a reload and keeps `isLoading`
/// false while doing so, so a server that drops out takes its libraries with it
/// without the screen passing through a loading state. The selection step was a
/// one-shot post-frame callback, so nothing re-resolved the selection: the page
/// rendered an empty `SizedBox` with other libraries sitting right behind it,
/// and on TV without the chooser — which only mounts next to a selected
/// library — there was no way back out of it.
///
/// These drive the real screen against the real providers. The tab bodies fail
/// to load (no `MultiServerProvider` here) and say so in the log; what a tab
/// fetches is not what this file is about. The assertions are on which branch
/// the screen takes and on where the remote ends up.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/mixins/refreshable.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/screens/libraries/libraries_screen.dart';
import 'package:pleya/screens/libraries/state_messages.dart';
import 'package:pleya/screens/libraries/tv_library_chooser.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/library_header_bar.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

const _films = 'Films';
const _series = 'Series';
const _kids = 'Kids';

MediaLibrary _library(String id, String title) => MediaLibrary(
  id: id,
  backend: MediaBackend.plex,
  title: title,
  kind: MediaKind.movie,
  serverId: 's1',
  serverName: 'Server',
);

final _all = [_library('1', _films), _library('2', _series), _library('3', _kids)];

/// The page heading, which only exists when a library is actually open.
String? _openLibrary(WidgetTester tester) =>
    tester.widgetList<LibraryHeaderTitle>(find.byType(LibraryHeaderTitle)).map((w) => w.title).firstOrNull;

/// The header line under the heading (chooser + tabs). Mounted only on the
/// branch that has a selected library, so its absence is the blank page.
bool _headerLineShown(WidgetTester tester) => find.byType(LibraryHeaderBar).evaluate().isNotEmpty;

class _Harness {
  _Harness(this.libraries, this.hidden);

  final LibrariesProvider libraries;
  final HiddenLibrariesProvider hidden;
}

Future<_Harness> _pumpScreen(WidgetTester tester, List<MediaLibrary> initial) async {
  await tester.runAsync(() async {
    await SettingsService.getInstance();
    await StorageService.getInstance();
  });
  final libraries = LibrariesProvider();
  final hidden = HiddenLibrariesProvider();
  await tester.runAsync(() => hidden.ensureInitialized());
  if (initial.isNotEmpty) libraries.debugSetLibraries(initial);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: libraries),
        ChangeNotifierProvider.value(value: hidden),
      ],
      child: MaterialApp(theme: monoTheme(dark: true), home: const LibrariesScreen()),
    ),
  );
  await _settle(tester);
  return _Harness(libraries, hidden);
}

/// The screen resolves its selection over storage, so the microtasks have to be
/// let out of the test's fake async before the frame is worth looking at.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
  await tester.pump();
}

/// Switch library the way the TV chooser and the mobile dropdown both do.
Future<void> _select(WidgetTester tester, String globalKey) async {
  final state = tester.state(find.byType(LibrariesScreen)) as LibraryLoadable;
  await tester.runAsync(() async {
    state.loadLibraryByKey(globalKey);
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
  });
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  testWidgets('a selected library that disappears falls back instead of blanking the page', (tester) async {
    final harness = await _pumpScreen(tester, _all);
    await _select(tester, 's1:2');
    expect(_openLibrary(tester), _series);

    // The server drops "Series". A stable, non-empty set that no longer holds
    // the selection — no loading state, nothing else changes.
    harness.libraries.debugSetLibraries([_library('1', _films), _library('3', _kids)]);
    await _settle(tester);

    expect(harness.libraries.isLoading, isFalse);
    expect(_openLibrary(tester), _films, reason: 'falls back to the first surviving library');
    expect(_headerLineShown(tester), isTrue, reason: 'the page is open, not blank');
  });

  testWidgets('a selection that survives the update is left exactly where it was', (tester) async {
    final harness = await _pumpScreen(tester, _all);
    await _select(tester, 's1:2');

    // A different library disappears; the selected one is untouched.
    harness.libraries.debugSetLibraries([_library('1', _films), _library('2', _series)]);
    await _settle(tester);

    expect(_openLibrary(tester), _series);
    expect(_headerLineShown(tester), isTrue);
  });

  testWidgets('losing every library shows the empty state, not a blank page', (tester) async {
    final harness = await _pumpScreen(tester, _all);
    await _select(tester, 's1:2');

    harness.libraries.debugSetLibraries([]);
    await _settle(tester);

    expect(_headerLineShown(tester), isFalse);
    expect(find.byType(EmptyStateWidget), findsOneWidget);
    expect(find.text(t.libraries.noLibrariesFound), findsOneWidget);
  });

  testWidgets('libraries that arrive after the screen mounted still get selected', (tester) async {
    // The one-shot selection step gave up here: it ran post-frame against an
    // empty provider and never ran again.
    final harness = await _pumpScreen(tester, const []);
    expect(_headerLineShown(tester), isFalse);

    harness.libraries.debugSetLibraries([_library('1', _films), _library('3', _kids)]);
    await _settle(tester);

    expect(_openLibrary(tester), _films);
    expect(_headerLineShown(tester), isTrue);
  });

  testWidgets('the remote does not strand when the focused chooser chip disappears', (tester) async {
    final harness = await _pumpScreen(tester, _all);
    await _select(tester, 's1:2');

    final node = _chooserNode(tvLibraryChooserChipKey('s1:2'));
    expect(node, isNotNull, reason: 'the chooser has a chip for the open library');
    node!.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(node));

    harness.libraries.debugSetLibraries([_library('1', _films), _library('3', _kids)]);
    await _settle(tester);

    // Disposing the focused node hands primary focus to the enclosing scope,
    // which is a page the remote can neither move within nor leave.
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      tvLibraryChooserChipKey('s1:1'),
      reason: 'focus follows the library the page switched to',
    );
  });
}

/// The chooser's focus nodes are owned by the screen's [FocusMemoryTracker] and
/// labelled with their chip key, so the focus tree is the honest way to reach
/// them from outside.
FocusNode? _chooserNode(String debugLabel) {
  FocusNode? found;
  void walk(FocusNode node) {
    if (node.debugLabel == debugLabel) found = node;
    for (final child in node.children) {
      walk(child);
    }
  }

  walk(FocusManager.instance.rootScope);
  return found;
}
