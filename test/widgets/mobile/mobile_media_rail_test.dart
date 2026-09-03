import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_hub.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/mobile/mobile_media_card.dart';
import 'package:pleya/widgets/mobile/mobile_media_rail.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  UnifiedMediaGroup group(String id) {
    final source = UnifiedMediaSource.fromItem(
      MediaItem(id: id, backend: .plex, kind: MediaKind.movie, title: 'Title $id', serverId: 'nas', serverName: 'NAS'),
    );
    return UnifiedMediaGroup(
      groupId: id,
      identity: CanonicalMediaIdentity.movie(title: 'Title $id', year: null),
      sources: [source],
      representativeSourceKey: source.sourceKey,
      watchState: UnifiedWatchState(representativeSourceKey: source.sourceKey),
    );
  }

  UnifiedMediaHub hub({int count = 3, String title = 'Continue watching', UnifiedHubViewAll? viewAll}) =>
      UnifiedMediaHub.synthesized(
        slug: 'test',
        title: title,
        kind: UnifiedHubKind.movie,
        groups: [for (var i = 0; i < count; i++) group('i$i')],
        viewAll: viewAll,
      );

  Future<void> pump(WidgetTester tester, Widget rail) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final manager = MultiServerManager();
    final multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(multiServerProvider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: multiServerProvider,
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(body: rail),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders the hub title and one card per group', (tester) async {
    // Two cards, well within the 393pt viewport: ListView.builder only
    // materializes what is on (or near) screen, so a wider count here would
    // pin the lazy-build window rather than the rail's own composition.
    await pump(tester, MobileMediaRail(hub: hub(count: 2), railIndex: 0));

    expect(find.text('Continue watching'), findsOneWidget);
    expect(find.byType(MobileMediaCard), findsNWidgets(2));
  });

  testWidgets('shows "View All" only when a callback is given', (tester) async {
    await pump(tester, MobileMediaRail(hub: hub(), railIndex: 0));
    expect(find.text('View All'), findsNothing);

    await pump(tester, MobileMediaRail(hub: hub(), railIndex: 0, onViewAll: () {}));
    expect(find.text('View All'), findsOneWidget);
  });

  testWidgets('a card tap reports its own group', (tester) async {
    UnifiedMediaGroup? tapped;
    await pump(tester, MobileMediaRail(hub: hub(count: 2), railIndex: 0, onCardTap: (g) => tapped = g));

    await tester.tap(find.byType(MobileMediaCard).last);
    expect(tapped?.groupId, 'i1');
  });
}
