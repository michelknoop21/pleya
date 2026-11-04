/// [HubFocusMemory] outlives the rail, and a detail page's hub ids are the same
/// on every title: without a scope the card left on one title is where the next
/// one opens.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/focus/locked_hub_controller.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/tv_browse_rail.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    HubFocusMemory.clear();
  });

  testWidgets('the card left on one title does not follow you to the next', (tester) async {
    await SettingsService.getInstance();
    final manager = MultiServerManager();
    const hubId = 'detail_actors';
    final hub = MediaHub(
      id: hubId,
      title: 'Cast',
      type: 'movie',
      size: 6,
      items: [
        for (var i = 0; i < 6; i++)
          MediaItem(id: 'p$i', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'P$i', serverId: 's'),
      ],
    );
    final railKey = GlobalKey<TvBrowseRailState>();

    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>(
        create: (_) => MultiServerProvider(manager, DataAggregationService(manager)),
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: InputModeTracker(
            child: Scaffold(
              body: SizedBox(
                width: 1280,
                height: 720,
                child: TvBrowseRail(
                  key: railKey,
                  hubs: [hub],
                  iconForHub: (_, _) => Icons.person,
                  focusMemoryScope: 'film-a',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    railKey.currentState!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 300));

    expect(HubFocusMemory.getForHubOnly('film-a::$hubId', 6), 2);
    expect(HubFocusMemory.getForHubOnly('film-b::$hubId', 6), 0);
    expect(HubFocusMemory.getForHubOnly(':$hubId', 6), 0, reason: 'the shared key is what leaked');
  });
}
