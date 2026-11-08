import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/source_availability.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_route_context.dart';
import 'package:pleya/navigation/tv/tv_content_route_registry.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/screens/media_detail_screen.dart';
import 'package:pleya/screens/tv/tv_media_source_picker_route.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';
import '../../test_helpers/tv_discovery_fixtures.dart';

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  for (final backend in [MediaBackend.plex, MediaBackend.jellyfin, MediaBackend.pleyaServer]) {
    for (final kind in [MediaKind.episode, MediaKind.movie]) {
      testWidgets('More info opens selected $backend $kind details despite play preferences', (tester) async {
        final settings = await SettingsService.getInstance();
        await settings.write(SettingsService.episodeAction, EpisodeAction.play);
        await settings.write(SettingsService.continueWatchingAction, ContinueWatchingAction.play);
        final item = MediaItem(
          id: 'episode',
          backend: backend,
          kind: kind,
          title: 'Episode',
          grandparentId: 'series',
          grandparentTitle: 'Series',
          parentId: 'season',
          parentIndex: 2,
          index: 3,
          serverId: 'chosen-server',
        );
        final group = (kind == MediaKind.episode ? tvDiscoveryEpisodeGroup : tvDiscoveryGroup)('continue-group', [
          item.copyWith(id: 'other-episode', grandparentId: 'other-series', serverId: 'other-server'),
          item,
        ]);
        TvNestedRoute? opened;
        Future<Object?> capture(TvNestedRoute route) async {
          opened = route;
          return null;
        }

        tvContentRouteRegistry.attach(capture);
        addTearDown(() => tvContentRouteRegistry.detach(capture));
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        );
        final restore = TvFocusRestoreTarget(itemId: group.groupId, containerId: 'continueWatching');
        final activation = activateUnifiedMediaGroup(
          context,
          group: group,
          intent: UnifiedActivationIntent.details,
          forceDetails: true,
          environment: const UnifiedActivationEnvironment(availabilityFor: _online),
          restoreTarget: restore,
        );
        await tester.runAsync(() => activation);
        expect(opened, isNotNull);
        final detail = opened!.builder(context) as MediaDetailScreen;
        expect(detail.metadata.id, kind == MediaKind.episode ? 'series' : 'episode');
        expect(detail.metadata.serverId, 'chosen-server');
        expect(detail.initialSeasonId, kind == MediaKind.episode ? 'season' : null);
        expect(detail.initialEpisodeId, kind == MediaKind.episode ? 'episode' : null);
        expect(opened!.restoreTarget, same(restore));
        expect(detail.unifiedRouteContext?.sourceKey, 'chosen-server:episode');
      });
    }
  }
}

SourceAvailability _online(UnifiedMediaSource source) =>
    source.serverId.value == 'chosen-server' ? SourceAvailability.online : SourceAvailability.offline;
