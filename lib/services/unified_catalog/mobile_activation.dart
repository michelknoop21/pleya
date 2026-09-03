/// Mobile Home's use of `UnifiedActivationCoordinator` (iOS Unified 2026
/// fase 1, `docs/ios-unified-2026-fase1-plan.md` stap 7). The integration
/// pattern this ports from `tv_media_source_picker_route.dart` on the tvOS
/// branch, without the overlay-specific TV picker session: preferences in,
/// `coordinator.decide` out, picker only when the decision asks for one.
///
/// Deliberately narrower than the tvOS file for fase 1. A tapped card opens
/// detail on `group.representativeSource.item` (a read), and long-press
/// still opens today's `MediaContextMenu` on that same item — the existing,
/// unimproved behaviour the plan's stap 7 WAAROM section calls out.
/// Source-aware detail routing, "Wijzigen", and the playback-failure
/// re-entry all belong to fase 5, which takes the group all the way through
/// `navigateToMediaItem`. This file only wires the hero's Play button, the
/// one place fase 1 needs a source-aware decision at all.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../media/unified/source_availability.dart';
import '../../media/unified/source_coverage_state.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_source.dart';
import '../../media/unified/unified_route_context.dart';
import 'preferred_server_store.dart';
import 'source_preference_store.dart';
import 'unified_activation_coordinator.dart';

/// What [activateMobileMediaGroup] ended up doing.
enum MobileActivationOutcome {
  /// A concrete source was routed to (directly, or after the user chose).
  routed,

  /// The picker opened and the user dismissed it without choosing.
  cancelled,

  /// Nothing was reachable (hoofdstuk 14.7).
  noUsableSource,
}

/// Decides which source to route [group] to, opening the picker only when
/// [UnifiedActivationCoordinator.decide] asks for one. [onRouted] receives
/// the chosen [UnifiedMediaSource] and is responsible for the actual
/// navigation — this function owns the decision, not the route.
Future<MobileActivationOutcome> activateMobileMediaGroup(
  BuildContext context, {
  required UnifiedMediaGroup group,
  required UnifiedActivationIntent intent,
  required SourceAvailability Function(UnifiedMediaSource source) availabilityFor,
  required Future<UnifiedMediaSource?> Function({
    required List<UnifiedMediaSource> sources,
    required String initialFocusSourceKey,
    String? preferredSourceKey,
    String? preferredServerId,
    required SourceCoverageState coverage,
  })
  showPicker,
  required ValueChanged<UnifiedMediaSource> onRouted,
  SourceCoverageState? coverage,
}) async {
  const coordinator = UnifiedActivationCoordinator();
  final preferredSourceKey = await SourcePreferenceStore.read(group.identity);
  final preferredServerId = await PreferredServerStore.read();
  if (!context.mounted) return MobileActivationOutcome.cancelled;

  final decision = coordinator.decide(
    group: group,
    intent: intent,
    availabilityFor: availabilityFor,
    coverage: coverage,
    preferredSourceKey: preferredSourceKey,
    preferredServerId: preferredServerId,
  );

  switch (decision) {
    // Hoofdstuk 14.6: one usable source is not a question, so it is not
    // asked, and nothing is remembered — the user chose nothing.
    case ActivateSourceDirectly(:final source):
      onRouted(source);
      return MobileActivationOutcome.routed;

    case ShowSourcePicker(
      :final sources,
      :final initialFocusSourceKey,
      :final coverage,
      preferredSourceKey: final marked,
    ):
      final chosen = await showPicker(
        sources: sources,
        initialFocusSourceKey: initialFocusSourceKey,
        preferredSourceKey: marked,
        preferredServerId: preferredServerId,
        coverage: coverage,
      );
      if (chosen == null || !context.mounted) return MobileActivationOutcome.cancelled;
      // Fire-and-forget: a preference is a convenience, and blocking the
      // route on a disk round-trip is the wrong trade against Select→player.
      unawaited(SourcePreferenceStore.remember(group.identity, chosen.sourceKey));
      onRouted(chosen);
      return MobileActivationOutcome.routed;

    // Hoofdstuk 14.7: the rows still show which server is down, but nothing
    // is directly reachable.
    case NoUsableSource(:final sources, :final coverage):
      await showPicker(
        sources: sources,
        initialFocusSourceKey: sources.first.sourceKey,
        preferredServerId: preferredServerId,
        coverage: coverage,
      );
      return MobileActivationOutcome.noUsableSource;
  }
}
