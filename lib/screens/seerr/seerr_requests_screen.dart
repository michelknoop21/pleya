import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/focusable_button.dart';
import '../../i18n/strings.g.dart';
import '../../models/seerr/seerr_request.dart';
import '../../providers/seerr_provider.dart';
import '../../services/seerr/seerr_client.dart';
import '../../services/seerr/seerr_constants.dart';
import '../../services/settings_service.dart';
import '../../theme/mono_theme.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focusable_filter_chip.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../focus/focusable_wrapper.dart';
import '../../models/seerr/seerr_media.dart';
import '../../widgets/pressable.dart';
import '../../widgets/seerr_poster_card.dart';
import '../../widgets/seerr_status_badge.dart';
import 'seerr_media_detail_screen.dart';

/// Jellyseerr / Overseerr requests-management screen.
///
/// Lists the current profile's requests (or every request for managers) with
/// filter chips, page-append pagination, and per-row approve / decline / cancel
/// actions. Fully d-pad focusable for TV.
class SeerrRequestsScreen extends StatefulWidget {
  const SeerrRequestsScreen({super.key});

  @override
  State<SeerrRequestsScreen> createState() => _SeerrRequestsScreenState();
}

class _SeerrRequestsScreenState extends State<SeerrRequestsScreen> {
  static const double _hInset = 16;

  String _filter = 'all';
  List<SeerrRequest> _items = const [];
  int _page = 1;
  int _totalPages = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _initialized = false;
  String? _error;

  // Bumped on each load so a filter switch (reset load) can invalidate an
  // in-flight load-more, preventing stale-filter items from being appended.
  int _loadGen = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _load(reset: true);
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  Future<void> _load({bool reset = false}) async {
    if (!mounted) return;
    final provider = context.read<SeerrProvider>();
    final client = provider.client;
    if (client == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final gen = ++_loadGen;
    final nextPage = reset ? 1 : _page + 1;
    setState(() {
      if (reset) {
        _loading = true;
        _error = null;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final result = await client.getRequests(
        filter: _filter,
        page: nextPage,
        requestedBy: provider.canManageRequests ? null : provider.session?.userId,
      );
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _items = reset ? result.items : [..._items, ...result.items];
        _page = nextPage;
        _totalPages = result.totalPages;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } on SeerrException catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = _errorText(e);
      });
    } catch (_) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = t.seerr.errorGeneric;
      });
    }
  }

  void _onFilter(String filter) {
    if (filter == _filter) return;
    setState(() => _filter = filter);
    _load(reset: true);
  }

  /// Runs a request action behind a blocking busy indicator, then reloads the
  /// current filter from page 1 (simplest correct refresh).
  Future<void> _runAction(Future<void> Function(SeerrClient client) action) async {
    final provider = context.read<SeerrProvider>();
    final client = provider.client;
    if (client == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    showLoadingDialog(context);
    String? errText;
    try {
      await action(client);
    } on SeerrException catch (e) {
      errText = _errorText(e);
    } catch (_) {
      errText = t.seerr.errorGeneric;
    }
    if (mounted) navigator.pop(); // dismiss the busy dialog
    if (errText != null) {
      messenger.showSnackBar(SnackBar(content: Text(errText)));
      return;
    }
    await _load(reset: true);
  }

  Future<void> _cancel(SeerrRequest req) async {
    final confirmed = await showConfirmDialog(
      context,
      title: t.seerr.cancelRequest,
      message: t.seerr.cancelRequestConfirm,
      confirmText: t.seerr.cancelRequest,
      cancelText: t.common.cancel,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    await _runAction((c) => c.deleteRequest(req.id));
  }

  String _errorText(SeerrException e) {
    if (e.isForbidden) return t.seerr.errorForbidden;
    if (e.isNetwork) return t.seerr.errorNetwork;
    return t.seerr.errorGeneric;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SeerrProvider>();
    final canManage = provider.canManageRequests;
    final ownUserId = provider.session?.userId;

    return FocusedScrollScaffold(
      title: Text(canManage ? t.seerr.allRequests : t.seerr.myRequests),
      slivers: [
        SliverToBoxAdapter(child: _filterRow()),
        ..._contentSlivers(canManage, ownUserId),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _filterRow() {
    final chips = <(String, IconData, String)>[
      ('all', Symbols.apps_rounded, t.seerr.filterAll),
      ('pending', Symbols.hourglass_empty_rounded, t.seerr.filterPending),
      ('approved', Symbols.check_circle_rounded, t.seerr.filterApproved),
      ('available', Symbols.download_done_rounded, t.seerr.filterAvailable),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(_hInset, 8, _hInset, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (value, icon, label) in chips)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FocusableFilterChip(icon: icon, label: label, onPressed: () => _onFilter(value)),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _contentSlivers(bool canManage, int? ownUserId) {
    if (_loading && _items.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    if (_error != null && _items.isEmpty) {
      return [_centeredMessage(_error!)];
    }
    if (_items.isEmpty) {
      return [_centeredMessage(t.seerr.noResults)];
    }

    final showLoadMore = _page < _totalPages && !_loading;
    return [
      SliverList.builder(
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final req = _items[index];
          final isOwn = ownUserId != null && req.requestedById == ownUserId;
          final actionable = canManage && req.isPending;
          return _SeerrRequestRow(
            request: req,
            onApprove: actionable ? () => _runAction((c) => c.approveRequest(req.id)) : null,
            onDecline: actionable ? () => _runAction((c) => c.declineRequest(req.id)) : null,
            onCancel: (isOwn && req.isPending) ? () => _cancel(req) : null,
          );
        },
      ),
      if (showLoadMore)
        SliverToBoxAdapter(
          child: FocusableListTile(
            leading: _loadingMore
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const AppIcon(Symbols.expand_more_rounded),
            title: Text(t.seerr.loadMore),
            onTap: _loadingMore ? null : () => _load(),
          ),
        ),
    ];
  }

  Widget _centeredMessage(String message) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Center(
          child: Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ),
    );
  }
}

/// One request row: media icon, season pills, availability badge, lifecycle
/// status, requester, and discrete focusable action buttons.
class _SeerrRequestRow extends StatelessWidget {
  const _SeerrRequestRow({required this.request, this.onApprove, this.onDecline, this.onCancel});

  final SeerrRequest request;
  final VoidCallback? onApprove;
  final VoidCallback? onDecline;
  final VoidCallback? onCancel;

  /// The tapped row opens the graphical media detail — the same screen the
  /// discover posters open — so a request is never a dead end.
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
    final isTv = request.mediaType == 'tv';
    final title = request.mediaTitle ?? (isTv ? t.discover.tvShow : t.discover.movie);
    final posterUrl = SeerrConstants.tmdbPosterUrl(request.posterPath);
    final canOpen = request.tmdbId != null;

    // Compact list thumbnail that follows the size slider (libraryDensity).
    final f = LibraryDensity.factor(SettingsService.instance.read(SettingsService.libraryDensity));
    final thumbW = 44 + f * 28; // 44→72
    final thumbH = thumbW * 1.5;

    final card = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.all(Radius.circular(tokens(context).radiusSm)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(tokens(context).radiusSm)),
            child: SizedBox(
              width: thumbW,
              height: thumbH,
              child: request.posterPath == null
                  ? ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Center(
                        child: AppIcon(
                          isTv ? Symbols.tv_rounded : Symbols.movie_rounded,
                          size: 24,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : SeerrPosterImage(url: posterUrl),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.mediaYear == null ? title : '$title (${request.mediaYear})',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Availability only when it says more than the lifecycle chip
                    // (otherwise two near-identical amber pills sit side by side).
                    if (request.mediaStatus == SeerrMediaStatus.partiallyAvailable ||
                        request.mediaStatus == SeerrMediaStatus.available)
                      SeerrStatusBadge(status: request.mediaStatus, compact: true),
                    _lifecycleChip(theme),
                    if (request.is4k || request.seasons.isNotEmpty) _plainPill(theme, _qualitySeasonsLabel()),
                  ],
                ),
                if (request.requestedByName != null && request.requestedByName!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    request.requestedByName!,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          if (onApprove != null || onDecline != null || onCancel != null) ...[
            const SizedBox(width: 12),
            _actions(context),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: FocusableWrapper(
        onSelect: canOpen ? () => _openDetail(context) : null,
        child: Pressable(onTap: canOpen ? () => _openDetail(context) : null, child: card),
      ),
    );
  }

  Widget _actions(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        if (onApprove != null)
          _actionButton(onApprove!, FilledButton(onPressed: onApprove, child: Text(t.seerr.approve))),
        if (onDecline != null)
          _actionButton(onDecline!, OutlinedButton(onPressed: onDecline, child: Text(t.seerr.decline))),
        if (onCancel != null)
          _actionButton(onCancel!, TextButton(onPressed: onCancel, child: Text(t.seerr.cancelRequest))),
      ],
    );
  }

  Widget _actionButton(VoidCallback onPressed, Widget child) {
    return FocusableButton(onPressed: onPressed, child: child);
  }

  String _qualitySeasonsLabel() {
    final parts = <String>[if (request.is4k) '4K', for (final n in request.seasons) t.seerr.season(number: n)];
    return parts.join(' · ');
  }

  Widget _lifecycleChip(ThemeData theme) {
    final (color, label) = switch (request.status) {
      SeerrRequestStatus.pending => (kAccentAlt, t.seerr.pending),
      SeerrRequestStatus.approved => (kSuccess, t.seerr.approved),
      SeerrRequestStatus.declined => (theme.colorScheme.error, t.seerr.declined),
      SeerrRequestStatus.completed => (kSuccess, t.seerr.completed),
      SeerrRequestStatus.failed => (theme.colorScheme.error, t.seerr.failed),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _plainPill(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
      child: Text(text, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}
