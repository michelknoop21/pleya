import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/source_availability.dart';
import 'package:pleya/media/unified/source_coverage_state.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/mobile/mobile_source_picker_sheet.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  MediaItem item(String id, {String serverId = 'nas', MediaBackend backend = MediaBackend.plex}) => MediaItem(
    id: id,
    backend: backend,
    kind: MediaKind.movie,
    title: 'Dune',
    serverId: serverId,
    serverName: serverId,
  );

  Future<void> pump(WidgetTester tester, Widget sheet) async {
    final manager = MultiServerManager();
    final multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(multiServerProvider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: multiServerProvider,
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(body: sheet),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows one row per source and the multi-server count', (tester) async {
    final sources = [
      UnifiedMediaSource.fromItem(item('i1', serverId: 'nas'), availability: SourceAvailability.online),
      UnifiedMediaSource.fromItem(item('i2', serverId: 'attic'), availability: SourceAvailability.online),
    ];
    await pump(
      tester,
      MobileSourcePickerSheet(
        representative: sources.first.item,
        sources: sources,
        coverage: SourceCoverageState.complete({'nas', 'attic'}),
        onChosen: (_) {},
      ),
    );

    expect(find.text('Available on 2 servers'), findsOneWidget);
    expect(find.text('nas'), findsOneWidget);
    expect(find.text('attic'), findsOneWidget);
  });

  testWidgets('tapping a usable row reports that source and no other', (tester) async {
    final sources = [
      UnifiedMediaSource.fromItem(item('i1', serverId: 'nas'), availability: SourceAvailability.online),
      UnifiedMediaSource.fromItem(item('i2', serverId: 'attic'), availability: SourceAvailability.online),
    ];
    UnifiedMediaSource? chosen;
    await pump(
      tester,
      MobileSourcePickerSheet(
        representative: sources.first.item,
        sources: sources,
        coverage: SourceCoverageState.complete({'nas', 'attic'}),
        onChosen: (s) => chosen = s,
      ),
    );

    await tester.tap(find.text('Play on attic'));
    expect(chosen?.sourceKey, 'attic:i2');
  });

  testWidgets('an offline row cannot be chosen at all', (tester) async {
    final sources = [
      UnifiedMediaSource.fromItem(item('i1', serverId: 'nas'), availability: SourceAvailability.offline),
      UnifiedMediaSource.fromItem(item('i2', serverId: 'attic'), availability: SourceAvailability.online),
    ];
    var calls = 0;
    await pump(
      tester,
      MobileSourcePickerSheet(
        representative: sources.first.item,
        sources: sources,
        coverage: SourceCoverageState.complete({'nas', 'attic'}),
        onChosen: (_) => calls++,
      ),
    );

    // No "Play on nas" button exists for the offline row.
    expect(find.text('Play on nas'), findsNothing);
    expect(calls, 0);
  });

  testWidgets('incomplete coverage shows the checking hint', (tester) async {
    final sources = [UnifiedMediaSource.fromItem(item('i1'), availability: SourceAvailability.online)];
    await pump(
      tester,
      MobileSourcePickerSheet(
        representative: sources.first.item,
        sources: sources,
        coverage: SourceCoverageState(expectedServerIds: const {'nas', 'attic'}, checkedServerIds: const {'nas'}),
        onChosen: (_) {},
      ),
    );

    expect(find.text('Checking more sources…'), findsOneWidget);
  });
}
