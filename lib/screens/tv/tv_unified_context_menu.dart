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

    case ApplyActionToAllSources(:final sources):
      await _applyToSources(context, action: action, group: group, sources: sources, onChanged: onChanged);

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
/// message rather than a rollback that pretends nothing happened. The local
/// suppression and its replay on reconnect (13.4 points 3 and 4) belong to
/// G10/G11 and are not built here; what this does is tell the user the truth
/// about the sources it could not reach.
Future<void> _applyToSources(
  BuildContext context, {
  required UnifiedGroupAction action,
  required UnifiedMediaGroup group,
  required List<UnifiedMediaSource> sources,
  VoidCallback? onChanged,
}) async {
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

  var done = 0;
  for (final source in sources) {
    if (!context.mounted) return;
    try {
      await _applyToOneSource(context, action: action, item: source.item);
      done++;
    } catch (e, st) {
      appLogger.w('Unified context action ${action.name} failed on ${source.sourceKey}', error: e, stackTrace: st);
    }
  }

  if (!context.mounted) return;
  if (done > 0) onChanged?.call();

  if (done == sources.length) {
    // A single-source write needs no tally; it either worked or it did not.
    if (sources.length > 1) showAppSnackBar(context, t.tvContextMenu.doneOnAll(count: sources.length));
  } else if (done == 0) {
    showAppSnackBar(context, t.tvContextMenu.failed);
  } else {
    showAppSnackBar(context, t.tvContextMenu.doneOnSome(done: done, total: sources.length));
  }
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
