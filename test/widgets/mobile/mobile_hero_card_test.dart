import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/mobile/mobile_hero_card.dart';
import 'package:pleya/widgets/mobile/mobile_hero_indicator.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  UnifiedMediaGroup group(String id, {String title = 'Dune'}) {
    final source = UnifiedMediaSource.fromItem(
      MediaItem(id: id, backend: .plex, kind: MediaKind.movie, title: title, serverId: 'nas', serverName: 'NAS'),
    );
    return UnifiedMediaGroup(
      groupId: id,
      identity: CanonicalMediaIdentity.movie(title: title, year: null),
      sources: [source],
      representativeSourceKey: source.sourceKey,
      watchState: UnifiedWatchState(representativeSourceKey: source.sourceKey),
    );
  }

  Future<void> pump(WidgetTester tester, Widget hero) async {
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
          home: Scaffold(body: hero),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('sizes the card to exactly what the caller hands in, radius 14', (tester) async {
    await pump(
      tester,
      MobileHeroCard(groups: [group('i1')], width: 361, height: 220, onPlay: (_) {}, onSecondaryAction: (_) {}),
    );

    final clip = tester.widget<ClipRRect>(find.byType(ClipRRect).first);
    expect(clip.borderRadius, BorderRadius.circular(14));
    final sized = tester.widgetList<SizedBox>(find.byType(SizedBox)).first;
    expect(sized.width, 361);
    expect(sized.height, 220);
  });

  testWidgets('a single group draws no indicator', (tester) async {
    await pump(
      tester,
      MobileHeroCard(groups: [group('i1')], width: 361, height: 220, onPlay: (_) {}, onSecondaryAction: (_) {}),
    );
    expect(find.byType(MobileHeroIndicator), findsNothing);
  });

  testWidgets('more than one group draws the indicator', (tester) async {
    await pump(
      tester,
      MobileHeroCard(
        groups: [group('i1'), group('i2')],
        width: 361,
        height: 220,
        onPlay: (_) {},
        onSecondaryAction: (_) {},
      ),
    );
    expect(find.byType(MobileHeroIndicator), findsOneWidget);
  });

  testWidgets('Play reports the currently visible group', (tester) async {
    UnifiedMediaGroup? played;
    await pump(
      tester,
      MobileHeroCard(
        groups: [
          group('i1', title: 'Dune'),
          group('i2', title: 'Arrival'),
        ],
        width: 361,
        height: 220,
        onPlay: (g) => played = g,
        onSecondaryAction: (_) {},
      ),
    );

    await tester.tap(find.text('Play'));
    expect(played?.groupId, 'i1');
  });

  testWidgets('an empty group list renders an empty box without throwing', (tester) async {
    await pump(
      tester,
      MobileHeroCard(groups: const [], width: 361, height: 220, onPlay: (_) {}, onSecondaryAction: (_) {}),
    );
    expect(tester.takeException(), isNull);
  });
}
