/// The context menu of hoofdstuk 23 on a unified TV card: the actions, the
/// scope question when one is owed, and the dispatch to the services that
/// already implement each write.
///
/// This is the wiring, not the rules. What may be offered and where a write
/// lands is [resolveUnifiedActionTarget]; what a write *does* is
/// `WatchActions` / `WatchlistUiActions` / the rating sheet, unchanged. Keeping
/// those two apart is what stops the menu from acquiring a second, slightly
/// different copy of either.
///
/// **Why the menu never routes.** The playback picker ends in a route; this
/// ends in a value and a message. A user who marks something watched from a row
/// expects to still be on that row afterwards, so nothing here pushes, and the
/// overlay sheet's `restoreLauncherFocus` hands focus back to the tile that
/// opened it.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_item.dart';
import '../../media/unified/source_availability.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_source.dart';
import 'package:provider/provider.dart';

import '../../exceptions/media_server_exceptions.dart';
import '../../providers/offline_watch_provider.dart';
import '../../providers/watchlist_provider.dart';
import '../../providers/watchlist_store.dart';
import '../../services/watch_actions.dart';
import '../../services/watchlist_ui_actions.dart';
import '../../utils/app_logger.dart';
import '../../utils/layout_constants.dart';
import '../../utils/provider_extensions.dart';
import '../../widgets/overlay_sheet.dart';
import '../../widgets/overlay_sheet_geometry.dart';
import '../../widgets/rating_bottom_sheet.dart';
import '../../widgets/tv/tv_action_scope_picker.dart';
import '../../widgets/tv/tv_catalog_sort_panel.dart';
import '../../widgets/tv/tv_panel_primitives.dart';
import '../../widgets/tv/tv_unified_layout.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/snackbar_helper.dart';
import 'tv_unified_context_actions.dart';

/// Opens the context menu for [group].
///
/// [availabilityFor] is the same live reader the activation environment uses;
/// a menu can sit open across a server health change, so availability is never
/// read off the stamped [UnifiedMediaSource.availability].
///
/// [isInContinueWatching] gates the one action whose availability is about
/// *where the card is* rather than what the title is: hoofdstuk 13.4's remove
/// only means something on a Continue Watching row.
///
/// [onChanged] fires after a write that actually landed, so the surface can
/// refresh the group. It does not fire on cancel.
Future<void> showTvUnifiedContextMenu(
  BuildContext context, {
  required UnifiedMediaGroup group,
  required SourceAvailability Function(UnifiedMediaSource source) availabilityFor,
  bool isInContinueWatching = false,
  bool isOffline = false,
  VoidCallback? onChanged,
}) async {
  final representative = group.representativeSource.item;
  final actions = availableUnifiedGroupActions(
    group: group,
    isInContinueWatching: isInContinueWatching,
    isOffline: isOffline,
    watchlist: unifiedWatchlistState(
      store: context.read<WatchlistStore?>(),
      provider: context.read<WatchlistProvider?>(),
      item: representative,
    ),
  );
  if (actions.isEmpty) return;

  final chosen = await OverlaySheetController.showAdaptive<UnifiedGroupAction>(
    context,
    presentation: OverlaySheetPresentation.panel,
    restoreLauncherFocus: true,
    builder: (sheetContext) => _ActionMenuPanel(
      title: representative.displayTitle,
      actions: actions,
      onChoose: (action) => OverlaySheetController.closeAdaptive(sheetContext, action),
      onClose: () => OverlaySheetController.closeAdaptive(sheetContext, null),
    ),
  );

  if (chosen == null || !context.mounted) return;
  await runUnifiedGroupAction(
    context,
    action: chosen,
    group: group,
    availabilityFor: availabilityFor,
    onChanged: onChanged,
  );
}

/// What the kijklijst can do with this title right now.
///
/// Three states rather than a bool, because "not on the list" and "cannot be
/// put on any list" lead to different menus: the first offers Toevoegen, the
/// second offers nothing at all. `WatchlistUiActions.canOffer` already draws
/// that line — a title needs a source that will take it, and a removal needs
/// the entry its memberships hang off.
enum UnifiedWatchlistState { unsupported, notOnList, onList }

/// Reads [UnifiedWatchlistState] off the two providers that own it, so
/// [availableUnifiedGroupActions] can stay a pure function of its inputs.
UnifiedWatchlistState unifiedWatchlistState({
  required WatchlistStore? store,
  required WatchlistProvider? provider,
  required MediaItem item,
}) {
  final onList = WatchlistUiActions.isOnList(store: store, provider: provider, item: item);
  if (!WatchlistUiActions.canOffer(provider: provider, item: item, onList: onList)) {
    return UnifiedWatchlistState.unsupported;
  }
  return onList ? UnifiedWatchlistState.onList : UnifiedWatchlistState.notOnList;
}

/// Which of [UnifiedGroupAction] this card may offer at all.
///
/// Availability *of a source* is not consulted here — that is
/// [resolveUnifiedActionTarget]'s job, and an action that is meaningful but
/// currently unreachable should say so when picked rather than vanish from the
/// menu, so a user is not left wondering where it went.
///
/// Watched and unwatched are mutually exclusive on the group's representative
/// watch state: offering both would make the menu a toggle the user has to read
/// twice.
List<UnifiedGroupAction> availableUnifiedGroupActions({
  required UnifiedMediaGroup group,
  required bool isInContinueWatching,
  required bool isOffline,
  UnifiedWatchlistState watchlist = UnifiedWatchlistState.unsupported,
}) {
  return [
    if (group.watchState.isWatched) UnifiedGroupAction.markUnwatched else UnifiedGroupAction.markWatched,
    // DEC-020: a watchlist mutation is refused offline rather than queued,
    // because a deferred write has no merge rule against what the same account
    // did on plex.tv-web in the meantime. So the action disappears offline
    // instead of failing on press.
    if (!isOffline)
      switch (watchlist) {
        UnifiedWatchlistState.onList => UnifiedGroupAction.removeFromWatchlist,
        UnifiedWatchlistState.notOnList => UnifiedGroupAction.addToWatchlist,
        UnifiedWatchlistState.unsupported => null,
      },
    // A rating is written to a server, so offline it has nowhere to go.
    if (!isOffline) UnifiedGroupAction.rate,
    if (isInContinueWatching) UnifiedGroupAction.removeFromContinueWatching,
  ].nonNulls.toList();
}

/// Carries out [action], asking for a scope first when the contract owes the
/// user that question.
///
/// Split out from [showTvUnifiedContextMenu] so a test can drive an action
/// without opening the menu, and so the "which target" and "do it" halves stay
/// separately readable.
Future<void> runUnifiedGroupAction(
  BuildContext context, {
  required UnifiedGroupAction action,
  required UnifiedMediaGroup group,
  required SourceAvailability Function(UnifiedMediaSource source) availabilityFor,
  VoidCallback? onChanged,
}) async {
  final target = resolveUnifiedActionTarget(action: action, group: group, availabilityFor: availabilityFor);

  switch (target) {
    case ActionUnavailable():
      showAppSnackBar(context, t.tvContextMenu.noUsableSource);

    case ApplyActionToSource(:final source):
      await _applyToSources(context, action: action, group: group, sources: [source], onChanged: onChanged);

    case ApplyActionToAllSources(:final sources, :final deferredSources):
      await _applyToSources(
        context,
        action: action,
        group: group,
        sources: sources,
        deferredSources: deferredSources,
        onChanged: onChanged,
      );

    case AskForActionScope(:final sources, :final allowAllSources):
      final choice = await _askForActionScope(
        context,
        action: action,
        group: group,
        sources: sources,
        allowAllSources: allowAllSources,
      );
      if (choice == null || !context.mounted) return;
      final chosenSources = switch (choice) {
        ChoseOneSource(:final source) => [source],
        ChoseAllSources(:final sources) => sources,
      };
      await _applyToSources(context, action: action, group: group, sources: chosenSources, onChanged: onChanged);
  }
}

Future<UnifiedActionScopeChoice?> _askForActionScope(
  BuildContext context, {
  required UnifiedGroupAction action,
  required UnifiedMediaGroup group,
  required List<UnifiedMediaSource> sources,
  required bool allowAllSources,
}) {
  // Focus starts on the first row in plain hoofdstuk 4.7 order — the top row
  // when there is an "Alle bronnen", the best-ranked source otherwise. No
  // preferred-source tier reaches this picker, so this cannot land on a
  // remembered playback choice.
  final firstRowKey = allowAllSources ? kAllSourcesRowKey : sources.first.sourceKey;
  return OverlaySheetController.showAdaptive<UnifiedActionScopeChoice>(
    context,
    presentation: OverlaySheetPresentation.panel,
    restoreLauncherFocus: true,
    builder: (sheetContext) => _ScopeSession(
      sources: sources,
      allowAllSources: allowAllSources,
      firstRowKey: firstRowKey,
      actionTitle: _scopeTitleFor(action),
      mediaTitle: group.representativeSource.item.displayTitle,
      onChoose: (choice) => OverlaySheetController.closeAdaptive(sheetContext, choice),
      onClose: () => OverlaySheetController.closeAdaptive(sheetContext, null),
    ),
  );
}

String _scopeTitleFor(UnifiedGroupAction action) => switch (action) {
  UnifiedGroupAction.markWatched => t.tvContextMenu.scopeTitleMarkWatched,
  UnifiedGroupAction.markUnwatched => t.tvContextMenu.scopeTitleMarkUnwatched,
  UnifiedGroupAction.rate => t.tvContextMenu.scopeTitleRate,
  // The logical actions never reach the scope picker; a title for them would
  // be dead copy that a future reader would have to disprove.
  UnifiedGroupAction.addToWatchlist ||
  UnifiedGroupAction.removeFromWatchlist ||
  UnifiedGroupAction.removeFromContinueWatching => t.tvContextMenu.title,
};

String labelForUnifiedGroupAction(UnifiedGroupAction action) => switch (action) {
  UnifiedGroupAction.markWatched => t.mediaMenu.markAsWatched,
  UnifiedGroupAction.markUnwatched => t.mediaMenu.markAsUnwatched,
  UnifiedGroupAction.addToWatchlist => t.watchlist.add,
  UnifiedGroupAction.removeFromWatchlist => t.watchlist.remove,
  UnifiedGroupAction.rate => t.mediaMenu.rate,
  UnifiedGroupAction.removeFromContinueWatching => t.mediaMenu.removeFromContinueWatching,
};

/// Runs [action] against every source in [sources] and reports honestly.
///
/// Sequential rather than concurrent: these are writes to several servers, and
/// a partial result has to be able to say *which* ones landed. It also keeps
/// the tracker and watch-state events in a defined order rather than
/// interleaved.
///
/// A partial failure is reported, never swallowed and never rolled back —
/// hoofdstuk 13.4 point 5 and 13.5's "mislukte subset" both ask for one clear
/// message rather than a rollback that pretends nothing happened.
///
/// **The denominator is the intent, not the reachable subset.** [sources] is
/// what can be written to now and [deferredSources] is what the contract also
/// targets but that is currently unreachable; the tally counts both. Saying
/// "klaar op alle 2" while a third membership was never touched is the exact
/// sentence hoofdstuk 13.4 point 5 exists to forbid.
///
/// **The retry promise is only made when a retry exists.** For an action with
/// [UnifiedGroupAction.queuesUnreachableMemberships] every deferred membership
/// — and every write that failed for a retryable reason — is put on the offline
/// queue, so "de rest wordt opnieuw geprobeerd" names a row that really is
/// waiting. For every other action nothing is queued, and the message says so
/// by leaving that clause out rather than promising a retry nothing performs.
/// A failure a reconnect cannot fix (an auth rejection, a backend without the
/// endpoint at all) is never queued either way.
Future<void> _applyToSources(
  BuildContext context, {
  required UnifiedGroupAction action,
  required UnifiedMediaGroup group,
  required List<UnifiedMediaSource> sources,
  List<UnifiedMediaSource> deferredSources = const [],
  VoidCallback? onChanged,
}) async {
  // Read before the first write. The queue is what makes the partial message
  // true, so it must survive the surface being torn down halfway through a
  // fan-out — holding the provider itself rather than reaching back through a
  // BuildContext after several awaits is what guarantees that.
  final offlineWatch = action.queuesUnreachableMemberships ? context.read<OfflineWatchProvider?>() : null;

  // The logical watchlist actions are not per-source at all: DEC-020 gives the
  // entry a list of memberships and `WatchlistUiActions` already writes to all
  // of them, so fanning out here would write the same list N times.
  if (action == UnifiedGroupAction.addToWatchlist || action == UnifiedGroupAction.removeFromWatchlist) {
    await WatchlistUiActions.toggle(context, group.representativeSource.item);
    onChanged?.call();
    return;
  }

  if (action == UnifiedGroupAction.rate) {
    // Rating is source-specific, so `sources` is always exactly one here — the
    // scope picker never offers "Alle bronnen" for it.
    final source = sources.single;
    final client = context.tryGetMediaClientForServer(source.serverId);
    if (client == null) {
      showAppSnackBar(context, t.tvContextMenu.noUsableSource);
      return;
    }
    await OverlaySheetController.showAdaptive(
      context,
      showDragHandle: true,
      builder: (sheetContext) =>
          RatingBottomSheet(item: source.item, serverClient: client, onServerRatingChanged: (_) => onChanged?.call()),
    );
    return;
  }

  final total = sources.length + deferredSources.length;
  final toQueue = action.queuesUnreachableMemberships ? [...deferredSources] : <UnifiedMediaSource>[];

  var done = 0;
  for (final source in sources) {
    if (!context.mounted) return;
    try {
      await _applyToOneSource(context, action: action, item: source.item);
      done++;
    } catch (e, st) {
      appLogger.w('Unified context action ${action.name} failed on ${source.sourceKey}', error: e, stackTrace: st);
      // A write that failed on a server that *was* online is still a write
      // the contract wanted; if the reason is one a reconnect fixes, it joins
      // the queue instead of being reported and forgotten.
      if (action.queuesUnreachableMemberships && isRetryableServerWriteFailure(e)) toQueue.add(source);
    }
  }

  final queued = await _queueDeferred(offlineWatch, toQueue);

  if (!context.mounted) return;
  if (done > 0 || queued > 0) onChanged?.call();

  final message = unifiedActionOutcomeMessage(done: done, total: total, queued: queued);
  if (message != null) showAppSnackBar(context, message);
}

/// The one sentence the user gets after a fan-out, or null when there is
/// nothing worth saying.
///
/// Pure and top-level so the honesty rule is testable without a server, a
/// queue and a widget tree — the rule *is* the feature, and it was wrong in
/// two different ways before fase 9: the denominator counted only the sources
/// that happened to be reachable, and the message promised a retry for actions
/// that queue nothing.
///
/// - Everything landed: a tally only when there was more than one target. A
///   single write either worked or it did not, and "klaar op alle 1 bronnen"
///   is noise.
/// - Nothing landed and nothing was held: a plain failure.
/// - Something is held: hoofdstuk 13.4 point 5's message, retry clause and
///   all — there is a queue entry behind it. This is also the branch a fully
///   deferred removal takes (done 0, queued 3), which is a success the user
///   should see rather than the failure it would otherwise read as.
/// - Something landed but nothing is held: the same tally without the retry
///   clause, because nothing is going to be retried.
String? unifiedActionOutcomeMessage({required int done, required int total, required int queued}) {
  if (done == total) return total > 1 ? t.tvContextMenu.doneOnAll(count: total) : null;
  if (done == 0 && queued == 0) return t.tvContextMenu.failed;
  if (queued > 0) return t.tvContextMenu.doneOnSome(done: done, total: total);
  return t.tvContextMenu.doneOnSomeNoRetry(done: done, total: total);
}

/// Puts every membership in [sources] on the offline queue, and returns how
/// many entries actually landed.
///
/// The count matters: it is what decides whether the user is told the rest
/// will be retried. A queue write that itself fails leaves nothing waiting,
/// and the message has to fall back to the plain tally rather than describe a
/// row that does not exist.
Future<int> _queueDeferred(OfflineWatchProvider? offlineWatch, List<UnifiedMediaSource> sources) async {
  if (offlineWatch == null || sources.isEmpty) return 0;

  var queued = 0;
  for (final source in sources) {
    try {
      await offlineWatch.queueRemoveFromContinueWatching(source.item);
      queued++;
    } catch (e, st) {
      appLogger.w('Could not queue Continue Watching removal for ${source.sourceKey}', error: e, stackTrace: st);
    }
  }
  return queued;
}

Future<void> _applyToOneSource(
  BuildContext context, {
  required UnifiedGroupAction action,
  required MediaItem item,
}) async {
  switch (action) {
    case UnifiedGroupAction.markWatched:
      await WatchActions.setWatched(context, item, watched: true);
    case UnifiedGroupAction.markUnwatched:
      await WatchActions.setWatched(context, item, watched: false);
    case UnifiedGroupAction.removeFromContinueWatching:
      await WatchActions.removeFromContinueWatching(context, item);
    case UnifiedGroupAction.addToWatchlist || UnifiedGroupAction.removeFromWatchlist || UnifiedGroupAction.rate:
      // Handled wholesale in [_applyToSources]; unreachable.
      throw StateError('${action.name} is not a per-source write');
  }
}

/// The menu panel: one column of actions, nothing else.
///
/// No artwork and no metadata header beyond the title. The user is looking at
/// the card that opened this and does not need it described back to them; what
/// they need is the shortest path from "I pressed the menu button" to the verb
/// they wanted.
class _ActionMenuPanel extends StatelessWidget {
  const _ActionMenuPanel({required this.title, required this.actions, required this.onChoose, required this.onClose});

  final String title;
  final List<UnifiedGroupAction> actions;
  final ValueChanged<UnifiedGroupAction> onChoose;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final mono = tokens(context);
    final radius = tvPanelBorderRadius(MediaQuery.sizeOf(context));

    return DecoratedBox(
      decoration: tvPanelDecoration(mono, radius),
      child: Padding(
        padding: EdgeInsets.all(TvSourcePickerLayout.panelPadding * scale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: TvSourcePickerLayout.titleFontSize * scale,
                fontWeight: FontWeight.w600,
                color: mono.text.withValues(alpha: TvSourcePickerLayout.inkPrimary),
              ),
            ),
            SizedBox(height: TvSourcePickerLayout.sectionGap * scale),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: actions.length,
                separatorBuilder: (_, _) => SizedBox(height: TvSourcePickerLayout.rowGap * scale),
                itemBuilder: (context, index) => TvCatalogOptionRow(
                  key: ValueKey(actions[index]),
                  label: labelForUnifiedGroupAction(actions[index]),
                  // Nothing here is a setting, so nothing is "the current
                  // answer". A selected tint on an action row would read as
                  // "this one is already on".
                  isSelected: false,
                  scale: scale,
                  onPressed: () => onChoose(actions[index]),
                ),
              ),
            ),
            SizedBox(height: TvSourcePickerLayout.footerGap * scale),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [TvPanelButton(scale: scale, label: t.common.close, onPressed: onClose, primary: false)],
            ),
          ],
        ),
      ),
    );
  }
}

/// Holds the focused row of an open scope picker, which is the one thing that
/// changes while it is up.
class _ScopeSession extends StatefulWidget {
  const _ScopeSession({
    required this.sources,
    required this.allowAllSources,
    required this.firstRowKey,
    required this.actionTitle,
    required this.mediaTitle,
    required this.onChoose,
    required this.onClose,
  });

  final List<UnifiedMediaSource> sources;
  final bool allowAllSources;
  final String firstRowKey;
  final String actionTitle;
  final String mediaTitle;
  final ValueChanged<UnifiedActionScopeChoice> onChoose;
  final VoidCallback onClose;

  @override
  State<_ScopeSession> createState() => _ScopeSessionState();
}

class _ScopeSessionState extends State<_ScopeSession> {
  late String _focusedRowKey = widget.firstRowKey;

  @override
  Widget build(BuildContext context) => TvActionScopePicker(
    sources: widget.sources,
    focusedRowKey: _focusedRowKey,
    actionTitle: widget.actionTitle,
    mediaTitle: widget.mediaTitle,
    allowAllSources: widget.allowAllSources,
    initialFocusRowKey: widget.firstRowKey,
    onChoose: widget.onChoose,
    onFocusRow: (key) => setState(() => _focusedRowKey = key),
    onClose: widget.onClose,
  );
}
