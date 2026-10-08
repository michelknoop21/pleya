import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../automation/automation_ids.dart';
import '../automation/automation_node.dart';
import '../focus/focusable_button.dart';
import '../i18n/strings.g.dart';
import '../models/seerr/seerr_media.dart';
import '../services/seerr/seerr_constants.dart';
import '../theme/mono_theme.dart';
import '../theme/mono_tokens.dart';
import 'app_icon.dart';
import 'focusable_list_tile.dart';
import 'loading_indicator_box.dart';

/// The pieces the request form and the edit form share: the boxed message, the
/// season rows, the admin target section and the button row.

/// An automation node around one focusable control, with a focus node of its
/// own handed to both. Pleya Verify reads `focused` off that node, so a
/// scenario can wait for the remote to be on this control and not merely on
/// the form.
class SeerrFocusNode extends StatefulWidget {
  const SeerrFocusNode({
    super.key,
    required this.id,
    required this.role,
    required this.builder,
    this.instance,
    this.label,
    this.state,
  });

  final String id;
  final String role;
  final String? instance;
  final String? label;
  final Object? Function()? state;
  final Widget Function(BuildContext context, FocusNode node) builder;

  @override
  State<SeerrFocusNode> createState() => _SeerrFocusNodeState();
}

class _SeerrFocusNodeState extends State<SeerrFocusNode> {
  late final FocusNode _node = FocusNode(debugLabel: '${widget.id}[${widget.instance ?? ''}]');

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AutomationNode(
    id: widget.id,
    instance: widget.instance,
    role: widget.role,
    label: widget.label,
    focusNode: _node,
    state: widget.state,
    child: widget.builder(context, _node),
  );
}

enum SeerrFormNoticeTone { info, warning, error }

/// A message that stands in the form rather than over it, so the choices it is
/// about stay visible underneath.
class SeerrFormNotice extends StatelessWidget {
  const SeerrFormNotice({
    super.key,
    required this.kind,
    required this.title,
    this.body,
    this.tone = SeerrFormNoticeTone.info,
  });

  /// The automation instance: `requests.form.notice[<kind>]`.
  final String kind;
  final String title;
  final String? body;
  final SeerrFormNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tk = tokens(context);
    final (icon, color) = switch (tone) {
      SeerrFormNoticeTone.info => (Symbols.info_rounded, tk.textMuted),
      SeerrFormNoticeTone.warning => (Symbols.warning_rounded, kAccentAlt),
      SeerrFormNoticeTone.error => (Symbols.warning_rounded, theme.colorScheme.error),
    };
    return AutomationNode(
      id: AutomationIds.requestsFormNotice,
      instance: kind,
      role: 'status',
      label: title,
      child: Semantics(
        liveRegion: true,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: tk.surfaceElevated, borderRadius: BorderRadius.circular(tk.radiusMd)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIcon(icon, size: 20, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    if (body != null) ...[
                      const SizedBox(height: 2),
                      Text(body!, style: theme.textTheme.bodyMedium?.copyWith(color: tk.textMuted)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Close on the left, the action on the right.
///
/// While [busy] the primary button keeps its focus and its place and ignores
/// Select. Handing Flutter a disabled button here would drop the focus to
/// wherever the traversal policy puts it, and on tvOS a sheet without a focused
/// control is a sheet the remote cannot leave.
class SeerrFormButtons extends StatelessWidget {
  const SeerrFormButtons({
    super.key,
    required this.closeLabel,
    required this.onClose,
    this.primaryLabel,
    this.primaryIcon,
    this.primaryInstance = 'submit',
    this.onPrimary,
    this.busy = false,
    this.hint,
  });

  final String closeLabel;
  final VoidCallback onClose;
  final String? primaryLabel;
  final IconData? primaryIcon;
  final String primaryInstance;

  /// Null draws the primary button disabled and gives Close the focus.
  final VoidCallback? onPrimary;
  final bool busy;

  /// One line left of the buttons: what a save will do, or who it is for.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = primaryLabel;
    final primaryEnabled = onPrimary != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                hint!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: tokens(context).textMuted),
              ),
            ),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              SeerrFocusNode(
                id: AutomationIds.requestsFormButton,
                instance: 'close',
                role: 'button',
                label: closeLabel,
                builder: (_, node) => FocusableButton(
                  focusNode: node,
                  // The safe button holds the focus whenever there is nothing
                  // to submit.
                  autofocus: primary == null || !primaryEnabled,
                  onPressed: busy ? () {} : onClose,
                  child: TextButton(onPressed: busy ? null : onClose, child: Text(closeLabel)),
                ),
              ),
              if (primary != null)
                SeerrFocusNode(
                  id: AutomationIds.requestsFormButton,
                  instance: primaryInstance,
                  role: 'button',
                  label: primary,
                  state: () => {'busy': busy, 'enabled': primaryEnabled && !busy},
                  builder: (_, node) => FocusableButton(
                    focusNode: node,
                    autofocus: primaryEnabled,
                    onPressed: busy ? () {} : onPrimary,
                    child: FilledButton.icon(
                      onPressed: busy ? null : onPrimary,
                      icon: busy
                          ? const LoadingIndicatorBox()
                          : (primaryIcon == null ? const SizedBox.shrink() : AppIcon(primaryIcon!, fill: 1)),
                      label: Text(primary),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One season row. [locked] names why it cannot be chosen; null means it can.
class SeerrSeasonTile extends StatelessWidget {
  const SeerrSeasonTile({
    super.key,
    required this.season,
    required this.selected,
    required this.onToggle,
    this.locked,
    this.enabled = true,
  });

  final SeerrSeason season;
  final bool selected;
  final VoidCallback onToggle;
  final String? locked;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final selectable = locked == null;
    final episodes = season.episodeCount;
    return SeerrFocusNode(
      id: AutomationIds.requestsFormOption,
      instance: 'season.${season.seasonNumber}',
      role: 'list.item',
      state: () => {'selected': selected, 'selectable': selectable},
      builder: (_, node) => FocusableListTile(
        focusNode: node,
        enabled: selectable && enabled,
        title: Text(t.seerr.season(number: season.seasonNumber)),
        subtitle: selectable ? (episodes > 0 ? Text(t.seerr.episodeCount(count: episodes)) : null) : Text(locked!),
        trailing: selectable
            ? Checkbox(value: selected, onChanged: enabled ? (_) => onToggle() : null)
            : const AppIcon(Symbols.lock_rounded, size: 20),
        onTap: selectable && enabled ? onToggle : null,
      ),
    );
  }
}

/// Why a season that is not requestable is not, in the catalog's own words.
String seerrSeasonLockLabel(SeerrMediaStatus status) => switch (status) {
  SeerrMediaStatus.available || SeerrMediaStatus.partiallyAvailable => t.seerr.available,
  SeerrMediaStatus.processing => t.seerr.processing,
  _ => t.seerr.requested,
};

/// The tri-state "Alle seizoenen" row above a season list.
class SeerrAllSeasonsTile extends StatelessWidget {
  const SeerrAllSeasonsTile({
    super.key,
    required this.chosen,
    required this.total,
    required this.onToggle,
    this.enabled = true,
  });

  final int chosen;
  final int total;
  final VoidCallback onToggle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SeerrFocusNode(
      id: AutomationIds.requestsFormOption,
      instance: 'season.all',
      role: 'list.item',
      state: () => {'chosen': chosen, 'total': total},
      builder: (_, node) => FocusableListTile(
        focusNode: node,
        enabled: enabled,
        leading: const AppIcon(Symbols.select_all_rounded, fill: 1),
        title: Text(t.seerr.allSeasons),
        subtitle: Text(t.seerr.seasonsChosen(count: chosen, total: total)),
        trailing: Checkbox(
          tristate: true,
          value: chosen == 0 ? false : (chosen == total ? true : null),
          onChanged: enabled ? (_) => onToggle() : null,
        ),
        onTap: enabled ? onToggle : null,
      ),
    );
  }
}
