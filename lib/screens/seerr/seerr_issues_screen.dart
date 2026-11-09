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
    await _load();
  }

  String _kind(SeerrIssue issue) => switch (issue.type) {
    1 => t.seerrIssues.video,
    2 => t.seerrIssues.audio,
    3 => t.seerrIssues.subtitles,
    _ => t.seerrIssues.other,
  };

  Widget _tile(SeerrIssue issue, {VoidCallback? onTap}) => FutureBuilder(
    future: _titles.putIfAbsent(issue.id, () => _client.issueMedia(issue)),
    builder: (context, snapshot) {
      final data = snapshot.data;
      final description = [
        _kind(issue),
        if (issue.season case final season?) t.seerrIssues.seasonNumber(number: season),
        if (issue.episode case final episode?) t.seerrIssues.episodeNumber(number: episode),
        ?issue.creator,
      ].join(' · ');
      final poster = data?.posterUrl;
      return ListTile(
        leading: poster == null || poster.isEmpty
            ? const Icon(Symbols.chat_bubble_outline_rounded)
            : ClipRRect(
                borderRadius: BorderRadius.circular(tokens(context).radiusSm),
                child: SizedBox(width: 36, height: 54, child: SeerrPosterImage(url: poster)),
              ),
        title: Text(data?.title ?? t.seerrIssues.number(number: issue.id)),
        subtitle: Text(description),
        trailing: onTap == null ? null : const Icon(Symbols.chevron_right_rounded),
        onTap: onTap,
      );
    },
  );

  List<Widget> _list() {
    final visible = _issues.where((issue) => _client.canViewAllIssues || issue.creatorId == _user).toList();
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          SegmentedTabGroup(
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
      for (final issue in visible)
        AutomationNode(
          id: AutomationIds.seerrIssueItem,
          instance: '${issue.id}',
          role: 'list.item',
          child: _tile(issue, onTap: () => unawaited(_open(issue))),
        ),
      if (_hasMore && !_failed)
        TextButton(onPressed: _busy ? null : () => _load(append: true), child: Text(t.seerrIssues.loadMore)),
    ];
  }

  List<Widget> _detail(SeerrIssue issue) => [
    _tile(issue),
    const Divider(),
    Text(issue.status == SeerrIssueStatus.open ? t.seerrIssues.open : t.seerrIssues.resolved),
    for (final (index, comment) in issue.comments.indexed)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    comment.author ?? (index == 0 ? issue.creator : null) ?? t.seerrIssues.unknownAuthor,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (comment.createdAt case final created?)
                  Text(
                    MaterialLocalizations.of(context).formatShortDate(created.toLocal()),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tokens(context).textMuted),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(comment.message),
          ],
        ),
      ),
    if (_client.canReplyToIssue(issue)) ...[
      FocusableTextField(
        controller: _reply,
        enabled: !_busy && !_failed,
        maxLines: 4,
        decoration: InputDecoration(labelText: t.seerrIssues.reply),
      ),
      const SizedBox(height: 8),
      ValueListenableBuilder(
        valueListenable: _reply,
        builder: (context, value, label) => FilledButton(
          onPressed: _busy || _failed || value.text.trim().isEmpty ? null : () => _mutate(issue, reply: true),
          child: label,
        ),
        child: Text(t.seerrIssues.sendReply),
      ),
    ],
    if (_client.canChangeIssueStatus(issue))
      AutomationNode(
        id: AutomationIds.seerrIssueStatusAction,
        role: 'button',
        state: () => {'status': issue.status.name, 'busy': _busy},
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: tokens(context).text),
          onPressed: _busy || _failed ? null : () => _mutate(issue, reply: false),
          child: Text(issue.status == SeerrIssueStatus.open ? t.seerrIssues.resolve : t.seerrIssues.reopen),
        ),
      ),
  ];

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
