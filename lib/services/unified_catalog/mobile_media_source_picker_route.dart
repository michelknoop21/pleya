/// Takes a [UnifiedMediaGroup] all the way through the existing navigation
/// helpers (iOS Unified 2026 workitem 4/I5, `docs/unified-2026-closure.md`
/// §5 row 4). Mirrors `tv_media_source_picker_route.dart`'s sequence without
/// the overlay-specific TV chrome (`initialFocusNode`, `TvNestedRouteScope`):
/// [activateMobileMediaGroup] decides and hands back a source plus its
/// [UnifiedMediaRouteContext], and this file is what does something with
/// that — routes to [navigateToMediaItemDetails] or [navigateToMediaItem]
/// depending on whether the caller asked to play directly, wires "Wijzigen"
/// back into the same picker, and offers an alternative after a failed
/// playback start.
library;

import 'package:provider/provider.dart';
import '../../providers/local_library_provider.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../i18n/strings.g.dart';
import '../../providers/watch_state_store.dart';
import '../../media/media_item.dart';
import '../../media/unified/source_availability.dart';
import '../../media/unified/source_coverage_state.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_source.dart';
import '../../media/unified/unified_route_context.dart';
import '../../utils/dialogs.dart';
import '../../utils/media_navigation_helper.dart';
import '../../widgets/mobile/mobile_source_picker_sheet.dart';
import 'mobile_activation.dart';
import 'preferred_server_store.dart';
import 'source_preference_store.dart';
import 'unified_activation_coordinator.dart';

/// Opens [group] via [activateMobileMediaGroup] and, once a source is
/// decided, takes it through [navigateToMediaItem] — the "Wijzigen" line and
/// the playback-failure re-entry come along for free because both hang off
/// [UnifiedMediaRouteContext.hasAlternativeSources] the same way they do on
/// tvOS.
///
/// [pickerContext] is for a caller whose own [context] sits above its
/// [OverlaySheetHost], as `MobileCatalogScreen` when it is pushed as a route:
/// the picker opens from there, everything else stays on [context].
Future<MobileActivationOutcome> openMobileMediaGroup(
  BuildContext context, {
  required UnifiedMediaGroup group,
  required UnifiedActivationIntent intent,
  required SourceAvailability Function(UnifiedMediaSource source) availabilityFor,
  BuildContext? pickerContext,
  SourceCoverageState? coverage,
  bool playDirectly = false,
  bool isOffline = false,
  void Function(String)? onRefresh,
  ValueChanged<MediaItem>? onPlaybackReturned,
}) async {
  // Offline catalog browsing has metadata, but must never claim the source
  // is playable. Only the read-only details intent takes this local route.
  if (intent == UnifiedActivationIntent.details &&
      !playDirectly &&
      group.sources.every((source) => !availabilityFor(source).isUsable)) {
    final local = context.read<LocalLibraryProvider?>();
    for (final source in group.sources) {
      final item = local?.item(source.serverId, source.item.id);
      if (item != null) {
        await navigateToMediaItemDetails(context, item, isOffline: true, onRefresh: onRefresh);
        return MobileActivationOutcome.routed;
      }
    }
  }
  return activateMobileMediaGroup(
    context,
    group: group,
    intent: intent,
    availabilityFor: availabilityFor,
    coverage: coverage,
    showPicker:
        ({
          required sources,
          required initialFocusSourceKey,
          preferredSourceKey,
          preferredServerId,
          required coverage,
        }) => showMobileSourcePickerSheet(
          pickerContext ?? context,
          representative: group.representativeSource.item,
          sources: sources,
          preferredSourceKey: preferredSourceKey,
          preferredServerId: preferredServerId,
          coverage: coverage,
        ),
    onRouted: (source, routeContext) => unawaited(
      _routeMobileSource(
        context,
        group: group,
        source: source,
        routeContext: routeContext,
        availabilityFor: availabilityFor,
        playDirectly: playDirectly,
        isOffline: isOffline,
        onRefresh: onRefresh,
        onPlaybackReturned: onPlaybackReturned,
      ),
    ),
  );
}

/// [playDirectly] picks the navigation helper, not just a flag passed through
/// to it: [navigateToMediaItem] lets the per-kind setting
/// (`episodeAction`/`continueWatchingAction`) override even a details-intent
/// tap for an episode, which is right for a card whose tap always meant
/// "play" but wrong here — a details tap on every one of this file's callers
/// means details, full stop, so that case goes through
/// [navigateToMediaItemDetails] directly instead.
Future<void> _routeMobileSource(
  BuildContext context, {
  required UnifiedMediaGroup group,
  required UnifiedMediaSource source,
  required UnifiedMediaRouteContext routeContext,
  required SourceAvailability Function(UnifiedMediaSource source) availabilityFor,
  required bool playDirectly,
  required bool isOffline,
  required void Function(String)? onRefresh,
  required ValueChanged<MediaItem>? onPlaybackReturned,
}) async {
  final onChangeSource = routeContext.hasAlternativeSources
      ? (BuildContext detailContext, UnifiedMediaRouteContext current, {bool pageFailed = false}) =>
            _changeSourceFromDetail(
              detailContext,
              group: group,
              routeContext: current,
              pageFailed: pageFailed,
              availabilityFor: availabilityFor,
              isOffline: isOffline,
              onRefresh: onRefresh,
              onPlaybackReturned: onPlaybackReturned,
            )
      : null;

  if (!playDirectly) {
    await navigateToMediaItemDetails(
      context,
      group.itemOf(routeContext.pageSourceKey),
      isOffline: isOffline,
      onRefresh: onRefresh,
      unifiedRouteContext: routeContext,
      onChangeSource: onChangeSource,
    );
    return;
  }

  var playbackInitFailed = false;
  await navigateToMediaItem(
    context,
    group.itemOf(routeContext.pageSourceKey),
    onRefresh: onRefresh,
    isOffline: isOffline,
    playDirectly: true,
    onPlaybackReturned: onPlaybackReturned,
    unifiedRouteContext: routeContext,
    onPlaybackInitFailed: () => playbackInitFailed = true,
    onChangeSource: onChangeSource,
  );

  if (playbackInitFailed && context.mounted) {
    await _offerAlternativeAfterPlaybackFailure(
      context,
      group: group,
      failedSourceKey: source.sourceKey,
      routeContext: routeContext,
      availabilityFor: availabilityFor,
      isOffline: isOffline,
      onRefresh: onRefresh,
      onPlaybackReturned: onPlaybackReturned,
    );
  }
}

/// The detail page's "[ Wijzigen ]". Mirrors tvOS' `_changeSourceFromDetail`:
/// the picker opens on every source (not just the alternatives), the current
/// one marked. A choice that leaves the page as it is goes back to the page;
/// only one that changes the page pops the old route before the new one opens,
/// so Back does not walk the viewer backwards through every source they looked
/// at.
Future<UnifiedMediaRouteContext?> _changeSourceFromDetail(
  BuildContext context, {
  required UnifiedMediaGroup group,
  required UnifiedMediaRouteContext routeContext,
  required bool pageFailed,
  required SourceAvailability Function(UnifiedMediaSource source) availabilityFor,
  required bool isOffline,
  required void Function(String)? onRefresh,
  required ValueChanged<MediaItem>? onPlaybackReturned,
}) async {
  const coordinator = UnifiedActivationCoordinator();
  final preferredServerId = await PreferredServerStore.read();
  if (!context.mounted) return null;
  // [group] dates from before any play on this page; the session's own watch
  // state is what makes the picker and the position current.
  final live = group.withFreshSourceItems(context.readFreshWatchState, preferredSourceKey: routeContext.sourceKey);
  // Not the ones the page dropped: a copy deleted meanwhile is no choice.
  final ordered = rankSources(
    live.sources
        .where((s) => routeContext.availableSourceKeys.contains(s.sourceKey))
        .map((s) => s.withAvailability(availabilityFor(s)))
        .toList(),
    preferredSourceKey: routeContext.sourceKey,
  );
  final chosen = await showMobileSourcePickerSheet(
    context,
    representative: live.representativeSource.item,
    sources: ordered,
    currentSourceKey: routeContext.sourceKey,
    preferredServerId: preferredServerId,
    coverage: routeContext.coverage,
  );
  if (chosen == null || !context.mounted) return null;
  if (chosen.sourceKey == routeContext.sourceKey && !pageFailed) return null;

  final next = coordinator.buildRouteContext(
    group: live,
    orderedSources: rankSources(ordered, preferredSourceKey: chosen.sourceKey),
    sourceKey: chosen.sourceKey,
    coverage: routeContext.coverage,
    intent: UnifiedActivationIntent.details,
    pageFollowsChoice: pageFailed,
  );
  unawaited(SourcePreferenceStore.remember(group.identity, chosen.sourceKey));
  if (next.pageSourceKey == routeContext.pageSourceKey && !pageFailed) return next;

  final navigator = Navigator.of(context);
  if (navigator.canPop()) navigator.pop();
  if (!context.mounted) return null;

  await _routeMobileSource(
    context,
    group: live,
    source: chosen,
    routeContext: next,
    availabilityFor: availabilityFor,
    playDirectly: false,
    isOffline: isOffline,
    onRefresh: onRefresh,
    onPlaybackReturned: onPlaybackReturned,
  );
  return null;
}

/// The offer after a failed playback start (hoofdstuk 15, mirrors tvOS'
/// `_offerAlternativeAfterPlaybackFailure`). Nothing is shown when the
/// coordinator has no alternative to offer — the player's own error state
/// already reported the failure once.
Future<void> _offerAlternativeAfterPlaybackFailure(
  BuildContext context, {
  required UnifiedMediaGroup group,
  required String failedSourceKey,
  required UnifiedMediaRouteContext routeContext,
  required SourceAvailability Function(UnifiedMediaSource source) availabilityFor,
  required bool isOffline,
  required void Function(String)? onRefresh,
  required ValueChanged<MediaItem>? onPlaybackReturned,
}) async {
  const coordinator = UnifiedActivationCoordinator();
  final options = coordinator.evaluatePlaybackFailure(
    sources: group.sources,
    failedSourceKey: failedSourceKey,
    availabilityFor: availabilityFor,
  );
  if (!options.hasAlternatives) return;

  final wantsAnother = await showConfirmDialog(
    context,
    title: t.common.error,
    message: t.sourcePicker.playbackFailedTitle,
    confirmText: t.sourcePicker.chooseAnotherSource,
    cancelText: t.common.close,
  );
  if (!wantsAnother || !context.mounted) return;

  final preferredServerId = await PreferredServerStore.read();
  if (!context.mounted) return;
  final chosen = await showMobileSourcePickerSheet(
    context,
    representative: group.representativeSource.item,
    sources: options.alternatives,
    preferredServerId: preferredServerId,
    coverage: routeContext.coverage,
  );
  if (chosen == null || !context.mounted) return;

  unawaited(SourcePreferenceStore.remember(group.identity, chosen.sourceKey));
  await _routeMobileSource(
    context,
    group: group,
    source: chosen,
    routeContext: coordinator.buildRouteContext(
      group: group,
      orderedSources: options.alternatives,
      sourceKey: chosen.sourceKey,
      coverage: routeContext.coverage,
      intent: UnifiedActivationIntent.play,
    ),
    availabilityFor: availabilityFor,
    playDirectly: true,
    isOffline: isOffline,
    onRefresh: onRefresh,
    onPlaybackReturned: onPlaybackReturned,
  );
}
