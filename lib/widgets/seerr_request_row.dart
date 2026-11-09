import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../automation/automation_ids.dart';
import '../automation/automation_node.dart';
import '../focus/focusable_button.dart';
import '../focus/focusable_wrapper.dart';
import '../i18n/strings.g.dart';
import '../models/seerr/seerr_media.dart';
import '../models/seerr/seerr_request.dart';
import '../screens/seerr/seerr_media_detail_screen.dart';
import '../services/seerr/seerr_constants.dart';
import '../theme/mono_theme.dart';
import '../theme/mono_tokens.dart';
import 'pressable.dart';
import 'seerr_poster_card.dart';

/// How long a request has been waiting, as the Regiekamer queue says it:
/// "3 d", "5 u", "12 m". Null when the server gave no readable date.
String? seerrRequestAge(String? createdAt, {DateTime? now}) {
  final created = createdAt == null ? null : DateTime.tryParse(createdAt);
  if (created == null) return null;
  final age = (now ?? DateTime.now()).difference(created);
  if (age.isNegative) return null;
  if (age.inDays >= 1) return t.seerr.cockpit.ageDays(n: age.inDays);
  if (age.inHours >= 1) return t.seerr.cockpit.ageHours(n: age.inHours);
  return t.seerr.cockpit.ageMinutes(n: age.inMinutes < 1 ? 1 : age.inMinutes);
}

/// One request in the Regiekamer list (mockup C1): a small poster, the title,
/// one line of facts, the wait time and, for a decision that is still open,
/// round Afwijzen and Goedkeuren buttons. Everything else a request allows sits
/// behind the row itself, which opens the menu with the facts (C2).
///
/// Rows of one section sit in one card: [groupFirst] and [groupLast] round the
/// card's corners and drop the hairline under the last row.
class SeerrRequestRow extends StatelessWidget {
  const SeerrRequestRow({
    super.key,
    required this.request,
    this.onApprove,
    this.onDecline,
    this.onCancel,
    this.onEdit,
    this.onMore,
    this.onOpen,
    this.onSwipeDecline,
    this.selected,
    this.onSelectedChanged,
    this.busy = false,
    this.statusUnknown = false,
    this.focusNode,
    this.automationInstance,
    this.groupFirst = true,
    this.groupLast = true,
    this.now,
  });

  /// Names this row for a scenario (`requests.list.more[<it>]`): the row is the
  /// way into its menu.
  final String? automationInstance;

  /// For a caller that has to put the focus on this row itself.
  final FocusNode? focusNode;

  final SeerrRequest request;
  final VoidCallback? onApprove;
  final VoidCallback? onDecline;
  final VoidCallback? onCancel;

  /// Offered in the menu, not on the row.
  final VoidCallback? onEdit;

  /// The menu behind the row: the facts, every action, and the reason when
  /// there are none.
  final VoidCallback? onMore;

  /// Opens the title. Only used when there is no menu to open.
  final VoidCallback? onOpen;

  /// A swipe to the left. Separate from [onDecline] so the screen can ask
  /// first: a swipe is easier to make by accident than a tap.
  final VoidCallback? onSwipeDecline;

  /// Null hides the selection box. Only a decision the viewer may take is
  /// selectable.
  final bool? selected;
  final ValueChanged<bool>? onSelectedChanged;

  /// An action for this request is on the wire: the row says so and its
  /// buttons do nothing until the answer is in.
  final bool busy;

  /// The last action for this request was sent and its outcome could not be
  /// read. The row says so, and opening it is the one thing that still works:
  /// that reads the request again.
  final bool statusUnknown;

  final bool groupFirst;
  final bool groupLast;

  /// For tests: the moment the wait time is measured against.
  final DateTime? now;

  void _openDetail(BuildContext context) {
    final tmdbId = request.tmdbId;
    if (tmdbId == null) return;
    final media = SeerrMedia(
      tmdbId: tmdbId,
      mediaType: request.mediaType,
      title: request.mediaTitle ?? '',
      year: request.mediaYear?.toString(),
      posterPath: request.posterPath,
      backdropPath: request.backdropPath,
      status: request.mediaStatus,
    );
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SeerrMediaDetailScreen(media: media)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tk = tokens(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: tk.textMuted, fontSize: 12.5);
    // No stand-in title. Naming the media type where the title belongs told the
    // user nothing about what was actually requested.
    final title = request.mediaTitle;
    final open = onMore ?? onOpen ?? (request.tmdbId == null ? null : () => _openDetail(context));
    final locked = busy || statusUnknown;
    final decides = onApprove != null || onDecline != null;
    final age = seerrRequestAge(request.createdAt, now: now);
    final radius = Radius.circular(tk.radiusMd);

    // One line, one text: the name first (who asked is what a manager reads
    // first), then the kind or seasons, then 4K. Separate shrinking boxes each
    // kept a share of the width they did not use and cut the name short next
    // to a short "Film".
    final name = request.requestedByName;
    final facts = Text.rich(
      TextSpan(
        style: muted,
        children: [
          if (name != null && name.isNotEmpty) TextSpan(text: '$name · '),
          TextSpan(text: _kindOrSeasons),
          if (request.is4k)
            TextSpan(
              text: ' · ${t.seerr.fourKBadge}',
              style: TextStyle(color: tk.text, fontWeight: FontWeight.w700),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    final body = Row(
      children: [
        if (selected != null) ...[
          _SelectBox(
            selected: selected!,
            enabled: !locked && onSelectedChanged != null,
            onChanged: onSelectedChanged,
            label: title ?? '',
          ),
          const SizedBox(width: 8),
        ],
        ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(4)),
          child: SizedBox(
            width: 32,
            height: 48,
            // The shared poster widget already falls back to a placeholder on
            // an empty or failing URL.
            child: SeerrPosterImage(url: SeerrConstants.tmdbPosterUrl(request.posterPath)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null)
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 14.5),
                ),
              const SizedBox(height: 2),
              facts,
              if (locked || !decides) ...[const SizedBox(height: 4), _statusLine(theme, tk)],
            ],
          ),
        ),
        if (age != null) ...[
          const SizedBox(width: 8),
          Text(age, style: muted?.copyWith(fontSize: 12, color: tk.textMuted.withValues(alpha: 0.6))),
        ],
        ..._buttons(context),
      ],
    );

    Widget row = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tk.surface,
        borderRadius: BorderRadius.vertical(
          top: groupFirst ? radius : Radius.zero,
          bottom: groupLast ? radius : Radius.zero,
        ),
        border: groupLast ? null : Border(bottom: BorderSide(color: tk.outline.withValues(alpha: 0.6))),
      ),
      child: body,
    );

    // Vegen: rechts keurt goed, links wijst af (na een vraag, zie onSwipeDecline).
    // Nothing moves away: the row stays where it is and says Bezig like a tap.
    // Always the same wrapper, with the swipe switched off while the row is
    // busy: a wrapper that came and went with busy rebuilt the whole row, and
    // the focused Goedkeuren with it, the moment it was pressed.
    final canApprove = !locked && onApprove != null;
    final canDecline = !locked && onSwipeDecline != null;
    row = Dismissible(
      key: ValueKey('seerr-swipe-${request.id}'),
      direction: canApprove && canDecline
          ? DismissDirection.horizontal
          : canApprove
          ? DismissDirection.startToEnd
          : canDecline
          ? DismissDirection.endToStart
          : DismissDirection.none,
      background: _swipeBackground(tk, approve: true),
      secondaryBackground: _swipeBackground(tk, approve: false),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          if (canApprove) onApprove?.call();
        } else if (canDecline) {
          onSwipeDecline?.call();
        }
        return false;
      },
      child: row,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AutomationNode(
        id: automationInstance == null ? null : AutomationIds.requestsListMore,
        instance: automationInstance,
        role: 'button',
        label: statusUnknown ? t.seerr.checkStatus : t.seerr.moreActions,
        child: FocusableWrapper(
          focusNode: focusNode,
          onSelect: open,
          child: Pressable(onTap: open, child: row),
        ),
      ),
    );
  }

  /// The decision on the row: Afwijzen and Goedkeuren, or Annuleren on the
  /// viewer's own request. Busy keeps every button where it is and takes its
  /// action away, so the focus has somewhere to stay while the answer is out.
  List<Widget> _buttons(BuildContext context) {
    VoidCallback? guarded(VoidCallback? action) => action == null ? null : (busy || statusUnknown ? null : action);
    final out = <Widget>[];
    void add(VoidCallback? action, IconData icon, String label, {bool primary = false}) {
      if (action == null) return;
      out
        ..add(SizedBox(width: out.isEmpty ? 6 : 2))
        ..add(_RoundButton(onPressed: guarded(action), icon: icon, label: label, primary: primary));
    }

    add(onDecline, Symbols.close_rounded, t.seerr.decline);
    add(onApprove, Symbols.check_rounded, t.seerr.approve, primary: true);
    if (onApprove == null && onDecline == null) add(onCancel, Symbols.close_rounded, t.seerr.cancelRequest);
    return out;
  }

  Widget _statusLine(ThemeData theme, MonoTokens tk) {
    final style = theme.textTheme.bodySmall?.copyWith(color: tk.textMuted, fontSize: 12);
    if (statusUnknown || !request.statusKnown) {
      return Text(t.seerr.statusUnknownBadge, style: style?.copyWith(color: kAccentAlt));
    }
    if (busy) return Text(t.seerr.actionBusy, style: style);
    final (color, label) = switch (request.status) {
      SeerrRequestStatus.pending => (kAccentAlt, t.seerr.pending),
      SeerrRequestStatus.approved => (tk.text, t.seerr.approved),
      SeerrRequestStatus.declined => (kAccent, t.seerr.declined),
      SeerrRequestStatus.completed => (kSuccess, t.seerr.completed),
      SeerrRequestStatus.failed => (kAccent, t.seerr.failed),
    };
    final extra = _availability;
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: style),
        // Availability is a second dimension, not a second opinion: it only
        // earns a mention where it says something the status does not.
        if (extra != null) ...[
          Text(' · ', style: style),
          Flexible(
            child: Text(extra, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
          ),
        ],
      ],
    );
  }

  String? get _availability => switch (request.mediaStatus) {
    SeerrMediaStatus.partiallyAvailable => t.seerr.partiallyAvailable,
    SeerrMediaStatus.available when request.status != SeerrRequestStatus.completed => t.seerr.available,
    _ => null,
  };

  /// "Film · 2022", or for a show the seasons as one compact label: "Seizoen 3",
  /// "Seizoenen 18-22", or a count once they are too scattered to name.
  String get _kindOrSeasons {
    final seasons = request.seasons;
    final year = request.mediaYear;
    String withYear(String kind) => year == null ? kind : '$kind · $year';
    if (request.mediaType != 'tv') return withYear(t.discover.movie);
    if (seasons.isEmpty) return withYear(t.discover.tvShow);
    if (seasons.length == 1) return t.seerr.season(number: seasons.first);
    final range = seerrSeasonRanges(seasons);
    return range == null ? t.seerr.seasonsCount(count: seasons.length) : t.seerr.seasonsRange(range: range);
  }

  Widget _swipeBackground(MonoTokens tk, {required bool approve}) {
    return Container(
      alignment: approve ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: (approve ? kSuccess : kAccent).withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(tk.radiusMd),
      ),
      child: Icon(approve ? Symbols.check_rounded : Symbols.close_rounded, color: tk.text),
    );
  }
}

/// A 36 pt round icon button with its label as tooltip and semantics. Goedkeuren
/// is the white one, everything else sits on the quiet fill.
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.onPressed, required this.icon, required this.label, this.primary = false});

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final fill = primary ? tk.text : tk.text.withValues(alpha: 0.12);
    final ink = primary ? tk.bg : tk.text;
    return FocusableButton(
      onPressed: onPressed ?? () {},
      child: Opacity(
        opacity: onPressed == null ? 0.4 : 1,
        child: IconButton(
          onPressed: onPressed,
          tooltip: label,
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          padding: EdgeInsets.zero,
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: ink),
          ),
        ),
      ),
    );
  }
}

class _SelectBox extends StatelessWidget {
  const _SelectBox({required this.selected, required this.enabled, required this.onChanged, required this.label});

  final bool selected;
  final bool enabled;
  final ValueChanged<bool>? onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final tap = enabled ? () => onChanged?.call(!selected) : null;
    return Semantics(
      checked: selected,
      label: t.seerr.cockpit.select(title: label),
      child: FocusableButton(
        onPressed: tap ?? () {},
        child: GestureDetector(
          onTap: tap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 24,
            height: 44,
            child: Center(
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: selected ? tk.text : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: selected ? tk.text : tk.textMuted.withValues(alpha: 0.5), width: 2),
                ),
                child: selected ? Icon(Symbols.check_rounded, size: 14, color: tk.bg) : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
