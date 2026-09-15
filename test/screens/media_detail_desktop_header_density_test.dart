import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/providers/download_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/media_detail_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/download_manager_service.dart';
import 'package:pleya/services/download_storage_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/detail_header_layout.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/placeholder_container.dart';
import 'package:provider/provider.dart';

import '../test_helpers/notice_layer.dart';
import '../test_helpers/prefs.dart';
import '../test_helpers/profile_navigation.dart';

/// F-D1 (docs/density-audit-2026-09.md): the desktop/iPad detail header used
/// to be a flat `size.height * 0.6`, so it kept growing with the window even
/// though the title/actions block anchored to its bottom edge does not —
/// a taller header on a big display or a portrait iPad only ever adds dead
/// backdrop. `detailHeaderHeight` (via `desktopDetailHeaderHeight` /
/// `tabletDetailHeaderHeight`) caps that per size class. Home and iPhone are
/// untouched — see media_detail_ovr1a_scale_test.dart for TV, and the mobile
/// detail suite for phone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(resetNotices);

  setUp(() {
    resetNotices();
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  MediaItem movie() => MediaItem(id: 'movie_1', backend: MediaBackend.jellyfin, kind: MediaKind.movie, title: 'Sintel');

  Future<double> pumpAndMeasureHeaderHeight(WidgetTester tester, Size viewSize, TargetPlatform platform) async {
    debugDefaultTargetPlatformOverride = platform;
    tester.view.physicalSize = viewSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await SettingsService.getInstance();

    // The desktop/iPad action row reaches a Consumer<DownloadProvider> that
    // the TV harness in media_detail_ovr1a_scale_test.dart never does — same
    // trimmed provider stack media_detail_screen_test.dart's
    // pumpDetailUnderPushableRoot uses for the phone build.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final downloadManager = DownloadManagerService(
      database: db,
      storageService: DownloadStorageService.instance,
      clientResolver: (serverId, {clientScopeId}) => null,
    );
    downloadManager.recoveryFuture = Future<void>.value();
    final downloadProvider = DownloadProvider.forTesting(downloadManager: downloadManager, database: db);
    await downloadProvider.ensureInitialized();
    final manager = MultiServerManager();
    final multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(() async {
      downloadProvider.dispose();
      downloadManager.dispose();
      multiServerProvider.dispose();
      await db.close();
    });

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
            ChangeNotifierProvider<DownloadProvider>.value(value: downloadProvider),
          ],
          child: MaterialApp(
            builder: withNoticeLayer(),
            theme: monoTheme(dark: true),
            home: InputModeTracker(
              child: OverlaySheetHost(
                child: withProfileNavigationScope(child: MediaDetailScreen(metadata: movie())),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // No artwork on `movie`, so the hero backdrop renders as a plain
    // PlaceholderContainer sized by the header's own SizedBox — reading its
    // rendered height is reading the header height without needing an
    // automation id on the header itself.
    final height = tester.getSize(find.byType(PlaceholderContainer).first).height;
    // Reset synchronously, before the test completes: `debugAssertAll
    // FoundationVarsUnset` runs right after the test body returns, ahead of
    // any addTearDown callback, so this can't be a teardown.
    debugDefaultTargetPlatformOverride = null;
    return height;
  }

  group('desktop tier (PlatformDetector.isDesktop)', () {
    testWidgets('1440x900: unchanged from the pre-cap 60% (540)', (tester) async {
      final height = await pumpAndMeasureHeaderHeight(tester, const Size(1440, 900), TargetPlatform.macOS);
      expect(height, closeTo(desktopDetailHeaderHeight(1440, 900), 0.5));
      expect(height, closeTo(540, 0.5));
    });

    testWidgets('1920x1080: unchanged from the pre-cap 60% (648)', (tester) async {
      final height = await pumpAndMeasureHeaderHeight(tester, const Size(1920, 1080), TargetPlatform.macOS);
      expect(height, closeTo(desktopDetailHeaderHeight(1920, 1080), 0.5));
      expect(height, closeTo(648, 0.5));
    });

    testWidgets('2560x1440: capped well under the old 864 (60%)', (tester) async {
      final height = await pumpAndMeasureHeaderHeight(tester, const Size(2560, 1440), TargetPlatform.macOS);
      expect(height, closeTo(desktopDetailHeaderHeight(2560, 1440), 0.5));
      expect(height, lessThan(700));
      expect(height, lessThan(1440 * 0.6));
    });
  });

  group('iPad / tablet tier (PlatformDetector.isDesktop == false, isPhone == false)', () {
    testWidgets('1032x1376 portrait: capped well under the old 826 (60%)', (tester) async {
      final height = await pumpAndMeasureHeaderHeight(tester, const Size(1032, 1376), TargetPlatform.iOS);
      expect(height, closeTo(tabletDetailHeaderHeight(1032, 1376), 0.5));
      expect(height, lessThan(620));
      expect(height, lessThan(1376 * 0.6));
    });

    testWidgets('1376x1032 landscape: close to the pre-cap 60% (619)', (tester) async {
      final height = await pumpAndMeasureHeaderHeight(tester, const Size(1376, 1032), TargetPlatform.iOS);
      expect(height, closeTo(tabletDetailHeaderHeight(1376, 1032), 0.5));
      expect(height, closeTo(600, 20));
    });
  });
}
