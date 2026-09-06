import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/source_availability.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_route_context.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/unified_catalog/mobile_activation.dart';

import '../../test_helpers/prefs.dart';

/// Fase 1's only activation-coordinator caller: the hero's Play button
/// (`docs/ios-unified-2026-fase1-plan.md` stap 7's BEWIJS — the picker opens
/// only with more than one usable source, and never chooses on its own).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  UnifiedMediaSource source(String id, {String serverId = 'nas'}) => UnifiedMediaSource.fromItem(
    MediaItem(id: id, backend: .plex, kind: MediaKind.movie, title: 'Dune', serverId: serverId, serverName: serverId),
  );

  UnifiedMediaGroup group(List<UnifiedMediaSource> sources) => UnifiedMediaGroup(
    groupId: 'g1',
    identity: CanonicalMediaIdentity.movie(title: 'Dune', year: 2021),
    sources: sources,
    representativeSourceKey: sources.first.sourceKey,
    watchState: UnifiedWatchState(representativeSourceKey: sources.first.sourceKey),
  );

  testWidgets('one usable source routes directly, without ever opening the picker', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox));

    var pickerOpened = false;
    UnifiedMediaSource? routed;
    final outcome = await tester.runAsync(
      () => activateMobileMediaGroup(
        context,
        group: group([source('i1')]),
        intent: UnifiedActivationIntent.play,
        availabilityFor: (_) => SourceAvailability.online,
        showPicker:
            ({
              required sources,
              required initialFocusSourceKey,
              preferredSourceKey,
              preferredServerId,
              required coverage,
            }) async {
              pickerOpened = true;
              return sources.first;
            },
        onRouted: (s) => routed = s,
      ),
    );

    expect(pickerOpened, isFalse);
    expect(routed?.sourceKey, 'nas:i1');
    expect(outcome, MobileActivationOutcome.routed);
  });

  testWidgets('more than one usable source opens the picker and routes to the choice', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox));

    final sources = [source('i1', serverId: 'nas'), source('i2', serverId: 'attic')];
    var pickerOpened = false;
    UnifiedMediaSource? routed;
    final outcome = await tester.runAsync(
      () => activateMobileMediaGroup(
        context,
        group: group(sources),
        intent: UnifiedActivationIntent.play,
        availabilityFor: (_) => SourceAvailability.online,
        showPicker:
            ({
              required sources,
              required initialFocusSourceKey,
              preferredSourceKey,
              preferredServerId,
              required coverage,
            }) async {
              pickerOpened = true;
              return sources.firstWhere((s) => s.sourceKey == 'attic:i2');
            },
        onRouted: (s) => routed = s,
      ),
    );

    expect(pickerOpened, isTrue);
    expect(routed?.sourceKey, 'attic:i2');
    expect(outcome, MobileActivationOutcome.routed);
  });

  testWidgets('dismissing the picker routes nowhere and reports cancelled', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox));

    final sources = [source('i1', serverId: 'nas'), source('i2', serverId: 'attic')];
    var routedCalls = 0;
    final outcome = await tester.runAsync(
      () => activateMobileMediaGroup(
        context,
        group: group(sources),
        intent: UnifiedActivationIntent.play,
        availabilityFor: (_) => SourceAvailability.online,
        showPicker:
            ({
              required sources,
              required initialFocusSourceKey,
              preferredSourceKey,
              preferredServerId,
              required coverage,
            }) async => null,
        onRouted: (_) => routedCalls++,
      ),
    );

    expect(routedCalls, 0);
    expect(outcome, MobileActivationOutcome.cancelled);
  });

  testWidgets('no usable source still shows the rows, but routes nowhere', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox));

    var pickerOpened = false;
    var routedCalls = 0;
    final outcome = await tester.runAsync(
      () => activateMobileMediaGroup(
        context,
        group: group([source('i1')]),
        intent: UnifiedActivationIntent.play,
        availabilityFor: (_) => SourceAvailability.offline,
        showPicker:
            ({
              required sources,
              required initialFocusSourceKey,
              preferredSourceKey,
              preferredServerId,
              required coverage,
            }) async {
              pickerOpened = true;
              return null;
            },
        onRouted: (_) => routedCalls++,
      ),
    );

    expect(pickerOpened, isTrue);
    expect(routedCalls, 0);
    expect(outcome, MobileActivationOutcome.noUsableSource);
  });
}
