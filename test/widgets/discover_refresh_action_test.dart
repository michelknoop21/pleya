import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/widgets/discover_refresh_action.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';

/// Holds a load pass open so the in-flight state can be pumped and asserted.
class _GatedAggregationService extends DataAggregationService {
  _GatedAggregationService(super.serverManager);

  final gate = Completer<void>();

  @override
  Future<OnDeckAggregationResult> getOnDeckFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async {
    await gate.future;
    return (items: const <MediaItem>[], succeededServerIds: const {'server_1'});
  }

  @override
  Future<HubAggregationResult> getHubsFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    bool useGlobalHubs = true,
    bool includePlaybackHubs = true,
    Set<String>? serverIds,
  }) async {
    await gate.future;
    return (hubs: const <MediaHub>[], succeededServerIds: const {'server_1'});
  }
}

class _FakeClient implements MediaServerClient {
  @override
  ServerId get serverId => ServerId('server_1');

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _GatedAggregationService aggregation;
  late MultiServerProvider multiServer;
  late HiddenLibrariesProvider hiddenLibraries;
  late LibrariesProvider libraries;
  late DiscoverProvider discover;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);

    final manager = MultiServerManager()..debugRegisterClientForTesting(_FakeClient());
    aggregation = _GatedAggregationService(manager);
    multiServer = MultiServerProvider(manager, aggregation);
    hiddenLibraries = HiddenLibrariesProvider();
    libraries = LibrariesProvider();
    discover = DiscoverProvider(multiServer, hiddenLibraries, libraries, isProfileBinding: () => false);
  });

  tearDown(() {
    discover.dispose();
    libraries.dispose();
    hiddenLibraries.dispose();
    multiServer.dispose();
  });

  Widget harness() => MaterialApp(
    home: ChangeNotifierProvider<DiscoverProvider>.value(
      value: discover,
      child: Scaffold(
        body: Center(
          child: DiscoverRefreshAction(color: const Color(0xFFFFFFFF), onPressed: () => unawaited(discover.load())),
        ),
      ),
    ),
  );

  final spinner = find.byType(CircularProgressIndicator);
  final glyph = find.byIcon(Symbols.refresh_rounded);

  testWidgets('shows a spinner while the pass runs and the glyph again after', (tester) async {
    await tester.pumpWidget(harness());

    expect(glyph, findsOneWidget);
    expect(spinner, findsNothing);

    await tester.tap(find.byType(IconButton));
    await tester.pump();

    expect(spinner, findsOneWidget);
    expect(glyph, findsNothing);
    // Disabled while running, so a second press can't queue a trailing pass.
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);

    aggregation.gate.complete();
    // The pass hops between the tester's fake-async zone and real
    // shared-prefs I/O, so it only advances when both are drained in turn.
    for (var round = 0; round < 20 && discover.isRefreshing; round++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(() => pumpEventQueue());
    }
    await tester.pump();

    // That the flag itself falls back on the trailing notify is guarded in
    // discover_provider_test; this only asserts the render follows it.
    expect(discover.isRefreshing, isFalse);
    expect(spinner, findsNothing);
    expect(glyph, findsOneWidget);
  });
}
