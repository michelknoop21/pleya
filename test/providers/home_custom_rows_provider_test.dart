/// The provider that owns what is *in* an own Home row (ROW1).
///
/// Loading is per row, never joined and never queued: a load already in flight
/// re-checks the stored row when it lands and starts the next round itself.
/// That shape is the whole reason these tests exist — everything that can
/// change while a load is out has to be visible to the load that lands.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/home_custom_rows_provider.dart';
import 'package:pleya/providers/home_layout_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/services/unified_catalog/home_custom_row.dart';
import 'package:pleya/services/unified_catalog/home_custom_row_loader.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';

import '../test_helpers/prefs.dart';

/// A loader whose answers are handed out by the test, one completer per call.
class _ManualLoader implements HomeCustomRowLoader {
  final List<Completer<HomeCustomRowContent>> pending = [];
  final List<HomeCustomRow> calls = [];

  @override
  Future<HomeCustomRowContent> load(HomeCustomRow row, {required int limit}) {
    calls.add(row);
    final completer = Completer<HomeCustomRowContent>();
    pending.add(completer);
    return completer.future;
  }

  /// The content itself is beside the point here: these tests are about *when*
  /// a round is started and which answer is allowed to land, not about cards.
  void answer(int index) => pending[index].complete(const HomeCustomRowContent(isExact: true));
}

MediaLibrary _library(String id) => MediaLibrary(
  id: id,
  backend: MediaBackend.plex,
  title: id,
  kind: MediaKind.movie,
  serverId: 'nas',
  serverName: 'NAS',
);

void main() {
  late HomeLayoutProvider layout;
  late LibrariesProvider libraries;
  late HiddenLibrariesProvider hiddenLibraries;
  late MultiServerProvider multiServer;
  late _ManualLoader loader;

  const row = HomeCustomRow(id: 'r1', kind: MediaKind.movie, preferences: UnifiedCatalogPreferences.defaults);

  setUp(() async {
    resetSharedPreferencesForTest();
    // Ahead of the first provider: two racing `StorageService.getInstance()`
    // calls let the second one through before the first has assigned the
    // shared cache, and the read then throws a late-init error.
    await StorageService.getInstance();
    layout = HomeLayoutProvider();
    await layout.ensureInitialized();
    await layout.saveCustomRow(row);
    libraries = LibrariesProvider()..debugSetLibraries([_library('films')]);
    hiddenLibraries = HiddenLibrariesProvider();
    final manager = MultiServerManager();
    multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    loader = _ManualLoader();
  });

  tearDown(() {
    multiServer.dispose();
    hiddenLibraries.dispose();
    libraries.dispose();
    layout.dispose();
  });

  HomeCustomRowsProvider build() => HomeCustomRowsProvider(
    layout: layout,
    multiServer: multiServer,
    libraries: libraries,
    hiddenLibraries: hiddenLibraries,
    loader: loader,
  );

  // ROW1h. `_load` refuses to join a load that is already in flight, and the
  // load that lands only compared the *row*. A source change arriving in that
  // window was therefore lost twice over: `refreshAll` cleared `_loadedFor`,
  // the landing load wrote the stale answer straight back into it, and the
  // re-check in the `finally` then had nothing to compare against.
  test('a source change during a load in flight is not lost', () async {
    final provider = build();
    addTearDown(provider.dispose);
    await pumpEventQueue();
    expect(loader.calls, hasLength(1), reason: 'the row is asked once at construction');

    // A second library appears while the first answer is still out.
    libraries.debugSetLibraries([_library('films'), _library('docs')]);
    await pumpEventQueue();
    expect(loader.pending, hasLength(1), reason: 'the in-flight load is not joined');

    loader.answer(0);
    await pumpEventQueue();

    expect(
      loader.calls,
      hasLength(2),
      reason: 'the answer was computed against one library and the row now draws on two',
    );
  });

  // ROW1o. `_reconcile` gave up early while the profile had no rows, and gave up
  // without writing down what it had seen. The next comparison was therefore
  // made against the library set this provider was *built* with, so a set that
  // moved and moved back in the meantime read as no change at all.
  test('a library set that changes while there are no rows still updates the baseline', () async {
    await layout.removeCustomRow('r1');
    final provider = build();
    addTearDown(provider.dispose);
    await pumpEventQueue();
    expect(loader.calls, isEmpty, reason: 'no rows, nothing to ask');

    // Two libraries now, and nobody to tell.
    libraries.debugSetLibraries([_library('films'), _library('docs')]);
    await pumpEventQueue();

    await layout.saveCustomRow(row);
    await pumpEventQueue();
    expect(loader.calls, hasLength(1), reason: 'the new row is asked, against the two libraries');
    loader.answer(0);
    await pumpEventQueue();

    // Back to one. Measured against a stale baseline this is "no change".
    libraries.debugSetLibraries([_library('films')]);
    await pumpEventQueue();

    expect(loader.calls, hasLength(2), reason: 'the row still held the answer for two libraries');
  });

  test('nothing reloads when the library set did not actually change', () async {
    final provider = build();
    addTearDown(provider.dispose);
    await pumpEventQueue();
    loader.answer(0);
    await pumpEventQueue();

    // A provider that notifies on every poll must not restart the merge.
    libraries.debugSetLibraries([_library('films')]);
    await pumpEventQueue();

    expect(loader.calls, hasLength(1));
  });
}
