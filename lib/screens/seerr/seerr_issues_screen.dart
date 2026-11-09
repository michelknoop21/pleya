import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../focus/focusable_text_field.dart';
import '../../i18n/strings.g.dart';
import '../../models/seerr/seerr_issue.dart';
import '../../profiles/active_profile_provider.dart';
import '../../providers/offline_mode_provider.dart';
import '../../providers/seerr_provider.dart';
import '../../services/seerr/seerr_client.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/focusable_filter_chip.dart';
import '../../widgets/focusable_tab_chip.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/mobile/mobile_dense_title_row.dart';
import '../../widgets/segmented_tab_group.dart';
import '../../widgets/seerr_poster_card.dart';
import '../../widgets/state_view.dart';
import '../../focus/focusable_wrapper.dart';
import '../../theme/mono_theme.dart';
import '../../widgets/pressable.dart';
import '../../widgets/seerr_cockpit_tiles.dart';
import '../../widgets/seerr_request_row.dart' show seerrRequestAge;

class SeerrIssuesScreen extends StatefulWidget {
  const SeerrIssuesScreen({super.key, required this.client, required this.profileId, this.issueId});

  final SeerrClient client;
  final String profileId;
  final int? issueId;

  @override
  State<SeerrIssuesScreen> createState() => _SeerrIssuesScreenState();
}

class _SeerrIssuesScreenState extends State<SeerrIssuesScreen> {
  final _reply = TextEditingController();
  final _titles = <int, Future<({String? title, String? posterUrl})>>{};
  final _issues = <SeerrIssue>[];
  late final _user = widget.client.session.userId;
  SeerrIssueStatus _status = SeerrIssueStatus.open;
  SeerrIssue? _issue;
  bool _own = true;
  bool _busy = false;
  bool _hasMore = false;
  bool _failed = false;
  bool _unsupported = false;
  bool _mutationFailed = false;
  ({String message, int lastId})? _unconfirmedReply;
  int _page = 0;
  ({int open, int resolved})? _counts;

  SeerrClient get _client => widget.client;

  bool _isCurrent({bool watch = false}) {
    if (!mounted) return false;
    final active = Provider.of<ActiveProfileProvider>(context, listen: watch);
    final client = Provider.of<SeerrProvider>(context, listen: watch).client;
    final offline = Provider.of<OfflineModeProvider?>(context, listen: watch)?.isOffline ?? false;
    return !offline &&
        !active.isBinding &&
        active.activeId == widget.profileId &&
        identical(client, _client) &&
        _client.session.userId == _user &&
        _client.canViewIssues;
  }

  @override
  void initState() {
    super.initState();
    _own = !_client.canViewAllIssues;
    unawaited(_load());
    if (widget.issueId == null) unawaited(_loadCounts());
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    if (_busy || !_isCurrent()) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final id = widget.issueId;
      if (id != null) {
        final issue = await _client.getIssue(id);
        if (!mounted || !_isCurrent()) return;
        if (_unconfirmedReply case final sent?) {
          if (issue.comments.any((c) => c.id > sent.lastId && c.userId == _user && c.message == sent.message)) {
            _reply.clear();
          }
          _unconfirmedReply = null;
        }
        setState(() => _issue = issue);
      } else {
        final page = append ? _page + 1 : 1;
        final result = await _client.getIssues(status: _status, ownOnly: _own, page: page);
        if (!mounted || !_isCurrent()) return;
        setState(() {
          if (!append) _issues.clear();
          final seen = _issues.map((issue) => issue.id).toSet();
          _issues.addAll(result.items.where((issue) => seen.add(issue.id)));
          _hasMore = result.hasMore;
          _page = page;
        });
      }
    } catch (error) {
      if (mounted && _isCurrent()) {
        setState(() {
          _failed = true;
          // A 404 on the list route means this server has no issues at all.
          _unsupported = widget.issueId == null && error is SeerrException && error.statusCode == 404;
          if (error is SeerrException && (error.isAuth || error.isForbidden)) {
            _issue = null;
            _issues.clear();
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _mutate(SeerrIssue issue, {required bool reply}) async {
    if (_busy || _failed || _unconfirmedReply != null || !_isCurrent()) return;
    final message = _reply.text.trim();
    if (reply && message.isEmpty) return;
    setState(() {
      _busy = true;
      _mutationFailed = false;
    });
    try {
      if (reply) {
        await _client.replyToIssue(issue, message);
        if (mounted && _isCurrent()) _reply.clear();
      } else {
        await _client.setIssueStatus(
          issue,
          issue.status == SeerrIssueStatus.open ? SeerrIssueStatus.resolved : SeerrIssueStatus.open,
        );
      }
    } catch (error) {
      if (mounted && _isCurrent()) {
        _mutationFailed = true;
        if (reply && error is SeerrException && error.outcomeUnknown) {
          _unconfirmedReply = (message: message, lastId: issue.comments.lastOrNull?.id ?? 0);
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
  }

  void _filter({SeerrIssueStatus? status, bool? own}) {
    setState(() {
      _status = status ?? _status;
      _own = own ?? _own;
      _issues.clear();
      _hasMore = false;
      _page = 0;
    });
    unawaited(_load());
  }

  Future<void> _open(SeerrIssue issue) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SeerrIssuesScreen(client: _client, profileId: widget.profileId, issueId: issue.id),
      ),
    );
    unawaited(_loadCounts());
    await _load();
  }

  String _kind(SeerrIssue issue) => switch (issue.type) {
    1 => t.seerrIssues.video,
    2 => t.seerrIssues.audio,
    3 => t.seerrIssues.subtitles,
    _ => t.seerrIssues.other,
  };

  IconData _kindIcon(SeerrIssue issue) => switch (issue.type) {
    1 => Symbols.image_rounded,
    2 => Symbols.volume_up_rounded,
    3 => Symbols.closed_caption_rounded,
    _ => Symbols.help_rounded,
  };

  /// "Ravi · S1 A3": who reported it and where, in the Regiekamer's short form.
  String _where(SeerrIssue issue) => [
    ?issue.creator,
    if (issue.season case final season?) t.seerrIssues.seasonNumber(number: season),
    if (issue.episode case final episode?) t.seerrIssues.episodeNumber(number: episode),
  ].join(' · ');

  Future<({String? title, String? posterUrl})> _media(SeerrIssue issue) =>
      _titles.putIfAbsent(issue.id, () => _client.issueMedia(issue));

  Future<void> _loadCounts() async {
    if (!_client.canViewAllIssues) return;
    final counts = await _client.getIssueCounts();
    if (!mounted || !_isCurrent()) return;
    setState(() => _counts = counts);
  }

  /// One report in the Regiekamer queue (mockup C3): the kind as a round
  /// icon, "Title · Kind", who and where, and how long ago it was reported.
  Widget _issueRow(SeerrIssue issue, {required bool first, required bool last}) {
    final tk = tokens(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: tk.textMuted, fontSize: 12.5);
    final radius = Radius.circular(tk.radiusMd);
    final age = seerrRequestAge(issue.createdAt?.toIso8601String());
    return FutureBuilder(
      future: _media(issue),
      builder: (context, snapshot) {
        final title = snapshot.data?.title ?? t.seerrIssues.number(number: issue.id);
        void open() => unawaited(_open(issue));
        return FocusableWrapper(
          onSelect: open,
          disableScale: true,
          borderRadius: tk.radiusMd,
          child: Pressable(
            onTap: open,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: tk.surface,
                borderRadius: BorderRadius.vertical(
                  top: first ? radius : Radius.zero,
                  bottom: last ? radius : Radius.zero,
                ),
                border: last ? null : Border(bottom: BorderSide(color: tk.outline.withValues(alpha: 0.6))),
              ),
              child: Row(
                children: [
                  _KindIcon(icon: _kindIcon(issue)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$title · ${_kind(issue)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 14.5),
                        ),
                        if (_where(issue) case final where when where.isNotEmpty)
                          Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                      ],
                    ),
                  ),
                  if (age != null) ...[
                    const SizedBox(width: 8),
                    Text(age, style: muted?.copyWith(fontSize: 12, color: tk.textMuted.withValues(alpha: 0.6))),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _list() {
    final visible = _issues.where((issue) => _client.canViewAllIssues || issue.creatorId == _user).toList();
    final counts = _counts;
    return [
      // The counts are the whole server's: next to the own list they would be
      // numbers about reports that are not on it.
      if (_client.canViewAllIssues && !_own)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              for (final status in SeerrIssueStatus.values) ...[
                if (status != SeerrIssueStatus.values.first) const SizedBox(width: 8),
                Expanded(
                  child: SeerrCockpitTile(
                    instance: 'issues-${status.name}',
                    count: counts == null ? null : (status == SeerrIssueStatus.open ? counts.open : counts.resolved),
                    label: status == SeerrIssueStatus.open ? t.seerrIssues.tileOpen : t.seerrIssues.tileResolved,
                    tone: status == SeerrIssueStatus.open ? SeerrCockpitTone.waiting : SeerrCockpitTone.neutral,
                    selected: _status == status,
                    onTap: () {
                      if (!_busy && _status != status) _filter(status: status);
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          SegmentedTabGroup(
            outlined: false,
            children: [
              for (final status in SeerrIssueStatus.values)
                FocusableTabChip(
                  style: TabChipStyle.segmented,
                  isSelected: _status == status,
                  label: status == SeerrIssueStatus.open ? t.seerrIssues.open : t.seerrIssues.resolved,
                  onSelect: () {
                    if (!_busy) _filter(status: status);
                  },
                ),
            ],
          ),
          if (_client.canViewAllIssues && _user != null)
            FocusableFilterChip(
              selected: _own,
              label: t.seerrIssues.mine,
              onPressed: () {
                if (!_busy) _filter(own: !_own);
              },
            ),
        ],
      ),
      const SizedBox(height: 12),
      if (visible.isEmpty && !_failed && !_busy) Text(t.seerrIssues.empty),
      for (final (index, issue) in visible.indexed)
        AutomationNode(
          id: AutomationIds.seerrIssueItem,
          instance: '${issue.id}',
          role: 'list.item',
          child: _issueRow(issue, first: index == 0, last: index == visible.length - 1),
        ),
      if (_hasMore && !_failed)
        TextButton(onPressed: _busy ? null : () => _load(append: true), child: Text(t.seerrIssues.loadMore)),
    ];
  }

  /// The report itself: what and where on top, then the conversation as
  /// messages (the viewer's own on the right), then the way to answer.
  List<Widget> _detail(SeerrIssue issue) {
    final tk = tokens(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: tk.textMuted);
    final open = issue.status == SeerrIssueStatus.open;
    return [
      FutureBuilder(
        future: _media(issue),
        builder: (context, snapshot) {
          final poster = snapshot.data?.posterUrl;
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: tk.surface, borderRadius: BorderRadius.circular(tk.radiusMd)),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 46,
                    height: 69,
                    child: poster == null || poster.isEmpty
                        ? const SeerrPosterPlaceholder()
                        : SeerrPosterImage(url: poster),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        snapshot.data?.title ?? t.seerrIssues.number(number: issue.id),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (_where(issue) case final where when where.isNotEmpty)
                        Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _KindIcon(icon: _kindIcon(issue), size: 24),
                          const SizedBox(width: 6),
                          Text(_kind(issue), style: muted?.copyWith(color: tk.text)),
                          const SizedBox(width: 12),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: open ? kAccentAlt : kSuccess, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            open ? t.seerrIssues.open : t.seerrIssues.resolved,
                            style: muted?.copyWith(color: tk.text),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      const SizedBox(height: 16),
      for (final (index, comment) in issue.comments.indexed)
        _Bubble(
          author: comment.author ?? (index == 0 ? issue.creator : null) ?? t.seerrIssues.unknownAuthor,
          date: comment.createdAt == null
              ? null
              : MaterialLocalizations.of(context).formatShortDate(comment.createdAt!.toLocal()),
          message: comment.message,
          mine: comment.userId != null && comment.userId == _user,
        ),
      const SizedBox(height: 8),
      if (_client.canReplyToIssue(issue)) ...[
        if (open)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final text in [
                  t.seerrIssues.quickLooking,
                  t.seerrIssues.quickNewVersion,
                  t.seerrIssues.quickFixed,
                ])
                  // Fills the answer, never sends it: a tap on a chip is easy to
                  // make by accident, and the answer can still be changed.
                  FocusableFilterChip(
                    selected: false,
                    label: text,
                    onPressed: () {
                      if (_busy || _failed) return;
                      // Never over a draft: an empty field gets the text, a
                      // field with words in it gets it added.
                      final draft = _reply.text.trimRight();
                      final next = draft.isEmpty ? text : '$draft $text';
                      _reply.value = TextEditingValue(
                        text: next,
                        selection: TextSelection.collapsed(offset: next.length),
                      );
                    },
                  ),
              ],
            ),
          ),
        FocusableTextField(
          controller: _reply,
          enabled: !_busy && !_failed,
          maxLines: 4,
          minLines: 1,
          decoration: InputDecoration(labelText: t.seerrIssues.reply),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder(
          valueListenable: _reply,
          builder: (context, value, label) => FilledButton.icon(
            onPressed: _busy || _failed || value.text.trim().isEmpty ? null : () => _mutate(issue, reply: true),
            icon: const Icon(Symbols.send_rounded, size: 18),
            label: label!,
            style: FilledButton.styleFrom(backgroundColor: tk.text, foregroundColor: tk.bg),
          ),
          child: Text(t.seerrIssues.sendReply),
        ),
      ],
      if (_client.canChangeIssueStatus(issue)) ...[
        const SizedBox(height: 8),
        AutomationNode(
          id: AutomationIds.seerrIssueStatusAction,
          role: 'button',
          state: () => {'status': issue.status.name, 'busy': _busy},
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: tk.text),
            onPressed: _busy || _failed ? null : () => _mutate(issue, reply: false),
            icon: Icon(open ? Symbols.check_rounded : Symbols.refresh_rounded, size: 18),
            label: Text(open ? t.seerrIssues.resolve : t.seerrIssues.reopen),
          ),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final current = _isCurrent(watch: true);
    final title = widget.issueId == null ? t.seerrIssues.title : t.seerrIssues.number(number: widget.issueId!);
    final issue = _issue;
    final canShowDetail = issue != null && (_client.canViewAllIssues || issue.creatorId == _user);
    return FocusedScrollScaffold(
      title: Text(title),
      sliverAppBar: PlatformDetector.isHandheldIOS(context)
          ? MobileDenseSliverAppBar(
              pinned: true,
              row: MobileDenseTitleRow(title: title, onBack: () => Navigator.of(context).maybePop()),
            )
          : null,
      slivers: [
        if (!current)
          SliverFillRemaining(hasScrollBody: false, child: StateView.error(title: t.seerrIssues.unavailable))
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            sliver: SliverList.list(
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_failed && _unsupported)
                  Text(t.seerrIssues.serverUnsupported)
                else if (_failed) ...[
                  Text(t.seerrIssues.loadFailed),
                  TextButton(onPressed: _busy ? null : _load, child: Text(t.common.retry)),
                ],
                if (_mutationFailed && !_failed) Text(t.seerrIssues.changeUnconfirmed),
                if (widget.issueId == null) ..._list() else if (canShowDetail) ..._detail(issue),
              ],
            ),
          ),
      ],
    );
  }
}

/// The kind of a report as a round icon, the Regiekamer's way of telling
/// Beeld, Geluid, Ondertiteling and Overig apart at a glance.
class _KindIcon extends StatelessWidget {
  const _KindIcon({required this.icon, this.size = 32});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: tk.text.withValues(alpha: 0.12), shape: BoxShape.circle),
      child: Icon(icon, size: size / 2, color: tk.text),
    );
  }
}

/// One message of the conversation. The viewer's own sits on the right on the
/// raised surface, everyone else's on the left.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.author, required this.date, required this.message, required this.mine});

  final String author;
  final String? date;
  final String message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final theme = Theme.of(context);
    const small = Radius.circular(4);
    const big = Radius.circular(14);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        // Never the full width: the side a message sits on is what tells the
        // viewer's own from everyone else's.
        child: FractionallySizedBox(
          widthFactor: 0.82,
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: BoxDecoration(
              color: mine ? tk.surfaceElevated : tk.surface,
              borderRadius: BorderRadius.only(
                topLeft: mine ? big : small,
                topRight: mine ? small : big,
                bottomLeft: big,
                bottomRight: big,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: author,
                        style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: tk.text),
                      ),
                      if (date != null)
                        TextSpan(
                          text: '  $date',
                          style: theme.textTheme.labelSmall?.copyWith(color: tk.textMuted),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(message, style: theme.textTheme.bodyMedium?.copyWith(height: 1.35)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
