import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../automation/automation_ids.dart';
import '../automation/automation_node.dart';
import '../focus/focusable_button.dart';
import '../i18n/strings.g.dart';
import '../models/seerr/seerr_request.dart';
import '../services/seerr/seerr_constants.dart';
import '../services/seerr/seerr_request_rights.dart';
import '../theme/mono_tokens.dart';
import 'app_icon.dart';
import 'focusable_list_tile.dart';
import 'overlay_sheet.dart';
import 'seerr_request_form_parts.dart';
import 'seerr_poster_card.dart';

/// What the menu behind a request was closed with.
enum SeerrRequestAction { open, approve, decline, edit, cancel }

/// The menu behind one request: the TV card's context menu, and the row's
/// "more" button everywhere else.
///
/// It only lists what [rights] allows, and when that is nothing beyond opening
/// the title it says why, so an empty menu does not read as a broken one.
Future<SeerrRequestAction?> showSeerrRequestActionsSheet(
  BuildContext context, {
  required SeerrRequest request,
  required SeerrRequestRights rights,
  required bool isOwn,
}) {
  // The control the menu opens on is named to the host. Left to itself the
  // host focuses whichever control attached first, and now that the rows sit
  // in a scrolling list they attach a frame after Sluiten does.
  final initialFocus = FocusNode(debugLabel: 'SeerrRequestActionsInitial');
  // The menu owns the node from the moment it is built. The future completes
  // when the menu is told to close, and on a screen without an overlay host
  // that is before the closing animation has finished with the controls.
  var handedOver = false;
  return OverlaySheetController.showAdaptive<SeerrRequestAction>(
    context,
    restoreLauncherFocus: true,
    initialFocusNode: initialFocus,
    builder: (_) {
      handedOver = true;
      return _OwnedFocusNode(
        node: initialFocus,
        child: SeerrRequestActionsSheet(request: request, rights: rights, isOwn: isOwn, initialFocusNode: initialFocus),
      );
    },
  ).whenComplete(() {
    if (!handedOver) initialFocus.dispose();
  });
}

/// Disposes [node] when [child] leaves the tree, and not a frame earlier.
class _OwnedFocusNode extends StatefulWidget {
  const _OwnedFocusNode({required this.node, required this.child});

  final FocusNode node;
  final Widget child;

  @override
  State<_OwnedFocusNode> createState() => _OwnedFocusNodeState();
}

class _OwnedFocusNodeState extends State<_OwnedFocusNode> {
  @override
  void dispose() {
    widget.node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class SeerrRequestActionsSheet extends StatelessWidget {
  const SeerrRequestActionsSheet({
    super.key,
    required this.request,
    required this.rights,
    required this.isOwn,
    this.initialFocusNode,
  });

  /// Carried by the control the menu opens on: Goedkeuren when there is a
  /// decision to make, otherwise Titel openen, otherwise Sluiten.
  final FocusNode? initialFocusNode;

  final SeerrRequest request;
  final SeerrRequestRights rights;
  final bool isOwn;

  void _pick(BuildContext context, SeerrRequestAction action) => OverlaySheetController.closeAdaptive(context, action);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tk = tokens(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: tk.textMuted);
    final by = request.requestedByName;
    final who = isOwn ? t.seerr.ownRequest : (by == null || by.isEmpty ? null : t.seerr.requestedBy(name: by));
    final canOpen = request.tmdbId != null;
    final opensOn = rights.canApprove ? SeerrRequestAction.approve : (canOpen ? SeerrRequestAction.open : null);

    return AutomationNode(
      id: AutomationIds.requestsActions,
      role: 'dialog',
      label: request.mediaTitle,
      state: () => {'request': request.id, 'status': request.status.name},
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(tk.radiusSm),
                      child: SizedBox(
                        width: 48,
                        height: 72,
                        child: SeerrPosterImage(url: SeerrConstants.tmdbPosterUrl(request.posterPath)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            [_statusLabel, ?who].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: muted,
                          ),
                          if (request.mediaTitle case final title?)
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          Text(_kindLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // The header above and Sluiten below keep their place; the rows
              // between them take what is left and scroll when that is less
              // than they need. A plain column asked for its full height from
              // a surface that is capped, and on TV with every action present
              // the last row was drawn past the bottom edge.
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    if (canOpen)
                      _row(
                        context,
                        SeerrRequestAction.open,
                        Symbols.info_rounded,
                        t.seerr.openTitle,
                        autofocus: !rights.canApprove,
                        opensOn: opensOn,
                      ),
                    if (rights.canApprove)
                      _row(
                        context,
                        SeerrRequestAction.approve,
                        Symbols.check_rounded,
                        t.seerr.approve,
                        autofocus: true,
                        opensOn: opensOn,
                      ),
                    if (rights.canDecline)
                      _row(context, SeerrRequestAction.decline, Symbols.close_rounded, t.seerr.decline),
                    if (rights.canEdit) _row(context, SeerrRequestAction.edit, Symbols.edit_rounded, t.seerr.edit),
                    if (rights.canCancel)
                      _row(
                        context,
                        SeerrRequestAction.cancel,
                        Symbols.delete_rounded,
                        t.seerr.cancelRequest,
                        color: theme.colorScheme.error,
                      ),
                    if (!rights.hasAny)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                        child: Text(
                          request.isPending ? t.seerr.actionsNoRight : t.seerr.actionsNotPending,
                          style: muted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _control(
                    instance: 'close',
                    label: t.common.close,
                    initial: opensOn == null,
                    builder: (_, node) => FocusableButton(
                      focusNode: node,
                      autofocus: !canOpen && !rights.hasAny,
                      onPressed: () => OverlaySheetController.closeAdaptive(context),
                      child: TextButton(
                        onPressed: () => OverlaySheetController.closeAdaptive(context),
                        child: Text(t.common.close),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    SeerrRequestAction action,
    IconData icon,
    String label, {
    bool autofocus = false,
    Color? color,
    SeerrRequestAction? opensOn,
  }) {
    return _control(
      instance: action.name,
      label: label,
      initial: action == opensOn,
      builder: (_, node) => FocusableListTile(
        focusNode: node,
        autofocus: autofocus,
        leading: AppIcon(icon, color: color),
        title: Text(label),
        textColor: color,
        iconColor: color,
        onTap: () => _pick(context, action),
      ),
    );
  }

  /// One focusable control of the menu with its automation node. The control
  /// the menu opens on carries [initialFocusNode] instead of a node of its own,
  /// so the host can be told where to put the focus.
  Widget _control({
    required String instance,
    required String label,
    required bool initial,
    required Widget Function(BuildContext context, FocusNode node) builder,
  }) {
    final node = initial ? initialFocusNode : null;
    if (node == null) {
      return SeerrFocusNode(
        id: AutomationIds.requestsActionsItem,
        instance: instance,
        role: 'button',
        label: label,
        builder: builder,
      );
    }
    return AutomationNode(
      id: AutomationIds.requestsActionsItem,
      instance: instance,
      role: 'button',
      label: label,
      focusNode: node,
      child: Builder(builder: (context) => builder(context, node)),
    );
  }

  String get _statusLabel => switch (request.status) {
    SeerrRequestStatus.pending => t.seerr.pending,
    SeerrRequestStatus.approved => t.seerr.approved,
    SeerrRequestStatus.declined => t.seerr.declined,
    SeerrRequestStatus.failed => t.seerr.failed,
    SeerrRequestStatus.completed => t.seerr.completed,
  };

  String get _kindLine {
    final isTv = request.mediaType == 'tv';
    final kind = isTv ? t.seerr.kindShow : t.seerr.kindMovie;
    final seasons = request.seasons;
    if (!isTv || seasons.isEmpty) return kind;
    final range = seerrSeasonRanges(seasons);
    final label = seasons.length == 1
        ? t.seerr.season(number: seasons.first)
        : (range == null ? t.seerr.seasonsCount(count: seasons.length) : t.seerr.seasonsRange(range: range));
    return '$kind · $label';
  }
}
