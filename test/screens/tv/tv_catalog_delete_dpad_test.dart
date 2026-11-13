/// The Alle films and Alle series menu on a remote: from the card's context
/// menu, DOWN reaches "Beheren", Select opens the management sheet, DOWN
/// reaches "Verwijderen van server", and Select asks before anything is sent.
/// Arrow keys and Select only; no row is focused by hand.
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:pleya/automation/automation_node.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/focus/dpad_navigator.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/source_availability.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/tv/tv_unified_context_menu.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_client.dart';
import 'package:pleya/services/unified_catalog/unified_management_menu.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/tv/tv_top_navigation.dart';

import '../../test_helpers/prefs.dart';
import '../../test_helpers/tv_full_bleed_catalog_harness.dart';

class _OwnerManager extends MultiServerManager {
  @override
  bool canManageServerMetadata(ServerId serverId) => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late PlexClient client;
  late List<String> calls;

  setUp(() {
    resetSharedPreferencesForTest();
    SelectKeyUpSuppressor.clearSuppression();
    TvDetectionService.debugSetTVOverride(true);
    calls = [];
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    client = PlexClient.forTesting(
      config: PlexConfig(
        baseUrl: 'https://nas.invalid',
        token: 'fixture',
        clientIdentifier: 'test',
        product: 'Pleya Verify',
        version: 'test',
      ),
      serverId: ServerId('nas'),
      serverName: 'NAS',
      httpClient: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        return http.Response('', 200);
      }),
    );
  });
  tearDown(() async {
    TvDetectionService.debugSetTVOverride(null);
    SelectKeyUpSuppressor.clearSuppression();
    client.close();
    await db.close();
  });

  UnifiedMediaGroup show() {
    final source = UnifiedMediaSource.fromItem(
      MediaItem(
        id: 'show-1',
        serverId: 'nas',
        serverName: 'NAS',
        backend: MediaBackend.plex,
        kind: MediaKind.show,
        title: 'Slow Horses',
      ),
    );
    return UnifiedMediaGroup(
      groupId: 'slow-horses',
      identity: CanonicalMediaIdentity.movie(title: 'Slow Horses'),
      sources: [source],
      representativeSourceKey: source.sourceKey,
      watchState: UnifiedWatchState(representativeSourceKey: source.sourceKey),
    );
  }

  /// The catalogue's own wiring (`TvUnifiedCatalogScreen._openContextMenu`):
  /// the trailing "Beheren" row opens [showUnifiedManagementMenu].
  Future<void> openMenu(WidgetTester tester) async {
    final manager = _OwnerManager()..debugRegisterClientForTesting(client);
    final provider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(provider.dispose);
    final group = show();
    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: provider,
        child: TranslationProvider(
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: InputModeTracker(
              child: OverlaySheetHost(
                child: Builder(
                  builder: (context) => Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () => showTvUnifiedContextMenu(
                          context,
                          group: group,
                          availabilityFor: (_) => SourceAvailability.online,
                          onNavigate: (_) async {},
                          extraAction: (
                            label: t.mediaMenu.manage,
                            onSelected: () => showUnifiedManagementMenu(context, group, isOffline: false),
                          ),
                        ),
                        child: const Text('open'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    await tester.pumpAndSettle();
  }

  /// DOWN until the row holding [label] has the remote, at most [limit] presses.
  Future<int> downTo(WidgetTester tester, String label, {int limit = 12}) async {
    for (var presses = 0; presses <= limit; presses++) {
      if (automationRowHasFocus(tester.element(find.text(label).last))) return presses;
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    fail('DOWN never reached "$label"');
  }

  testWidgets('DOWN reaches Beheren, then Verwijderen van server; Select asks, Annuleren sends nothing', (
    tester,
  ) async {
    await openMenu(tester);
    final toManage = await downTo(tester, t.mediaMenu.manage);
    await press(tester, LogicalKeyboardKey.select);
    expect(find.text(t.mediaMenu.deleteFromServer), findsOneWidget);
    final toDelete = await downTo(tester, t.mediaMenu.deleteFromServer);
    await press(tester, LogicalKeyboardKey.select);

    // The confirmation, with Annuleren under the remote first.
    expect(find.textContaining(t.mediaMenu.confirmDelete), findsOneWidget);
    expect(automationRowHasFocus(tester.element(find.text(t.common.cancel))), isTrue);
    await press(tester, LogicalKeyboardKey.select);
    expect(calls, isEmpty);
    // ignore: avoid_print
    print('presses: $toManage to Beheren, $toDelete to Verwijderen van server');
  });

  testWidgets('RIGHT to the confirm button and Select deletes exactly that item', (tester) async {
    await openMenu(tester);
    await downTo(tester, t.mediaMenu.manage);
    await press(tester, LogicalKeyboardKey.select);
    await downTo(tester, t.mediaMenu.deleteFromServer);
    await press(tester, LogicalKeyboardKey.select);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.select);
    expect(calls, ['DELETE /library/metadata/show-1']);
    await tester.pump(const Duration(seconds: 10));
  });

  group('on the Alle films wall itself', () {
    // The harness sets its own Apple TV override.
    setUp(() => TvDetectionService.debugSetTVOverride(null));

    testWidgets('after the delete the card leaves in place and the remote is on the next card, no reload', (
      tester,
    ) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
      final h = await FullBleedHarness.create([for (var i = 0; i < 8; i++) fakeMovie(i)], owner: true);
      await h.pump(tester);
      await h.open(tester);
      await h.press(tester, LogicalKeyboardKey.arrowRight);
      final deletedId = h.catalog.snapshot.groups[1].groupId;
      final nextLabel = h.cardLabel(2);
      expect(h.focused, h.cardLabel(1));
      final pagesBefore = h.client.queries.length;

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await downTo(tester, t.mediaMenu.manage);
      await press(tester, LogicalKeyboardKey.select);
      await downTo(tester, t.mediaMenu.deleteFromServer);
      await press(tester, LogicalKeyboardKey.select);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(h.client.deleted, hasLength(1));
      expect(h.catalog.snapshot.groups.map((g) => g.groupId), isNot(contains(deletedId)));
      expect(h.catalog.snapshot.groups, hasLength(7));
      expect(h.catalog.isInitialLoading, isFalse, reason: 'no skeleton');
      expect(h.client.queries.length, pagesBefore, reason: 'the wall is not reloaded for one card');
      expect(h.focused, nextLabel, reason: 'the remote lands on the card that took its place');
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('with the offline index restarting the wall, a remote moved to the top bar stays there', (
      tester,
    ) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
      final h = await FullBleedHarness.create([for (var i = 0; i < 8; i++) fakeMovie(i)], owner: true);
      await h.pump(tester);
      await h.open(tester);
      await h.press(tester, LogicalKeyboardKey.arrowRight);

      // The offline index answers a delete with a fail-closed restart, after
      // the menu has reported the delete (its deletion event arrives on a
      // stream); its first page is held so the wall stands on the skeleton.
      final held = Completer<void>();
      h.client.onDelete = () => Future<void>(() {
        h.client.pageGate = (_) => held.future;
        unawaited(h.catalog.refresh());
      });

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await downTo(tester, t.mediaMenu.manage);
      await press(tester, LogicalKeyboardKey.select);
      await downTo(tester, t.mediaMenu.deleteFromServer);
      await press(tester, LogicalKeyboardKey.select);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.select);
      expect(h.catalog.isInitialLoading, isTrue, reason: 'the restart is still on its first page');

      // Meanwhile the viewer goes to the top bar.
      final topBar = tester
          .widgetList<Focus>(find.descendant(of: find.byType(TvTopNavigation), matching: find.byType(Focus)))
          .firstWhere((focus) => focus.focusNode?.canRequestFocus ?? false)
          .focusNode!;
      topBar.requestFocus();
      await tester.pump();
      final onTopBar = FocusManager.instance.primaryFocus;

      h.client.pageGate = null;
      held.complete();
      await tester.pumpAndSettle();
      expect(h.catalog.isInitialLoading, isFalse);
      expect(FocusManager.instance.primaryFocus, same(onTopBar), reason: 'late content may not take the remote back');
      await tester.pump(const Duration(seconds: 10));
    });
  });
}
