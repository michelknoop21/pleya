import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../models/seerr/seerr_request.dart';
import '../../providers/seerr_provider.dart';
import '../../services/seerr/seerr_client.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/dialogs.dart';
import '../../utils/media_server_timeouts.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/segmented_tab_group.dart';
import '../../widgets/focusable_tab_chip.dart';
import 'seerr_discover_screen.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../focus/focusable_wrapper.dart';
import '../../widgets/seerr_request_row.dart';

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

  final ScrollController _filterScrollController = ScrollController();
  static const _filterKeys = ['all', 'pending', 'approved', 'available'];
  final Map<String, GlobalKey> _filterChipKeys = {for (final k in _filterKeys) k: GlobalKey()};

  /// Counts shown next to the filter tabs. Zero means "not known yet"; the tab
  /// then renders without a number instead of claiming there are none.
  ({int total, int pending, int approved, int available, int processing})? _counts;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _load(reset: true);
    _loadCounts();
    _revealSelectedFilter();
  }

  @override
  void dispose() {
    _filterScrollController.dispose();
    super.dispose();
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
    // A non-manager may only see their own requests; without a known userId
    // a null requestedBy would return everyone's requests (privacy leak).
    final requestedBy = provider.canManageRequests ? null : provider.session?.userId;
    if (!provider.canManageRequests && requestedBy == null) {
      setState(() {
        _items = const [];
        _loading = false;
        _loadingMore = false;
      });
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
      final result = await client.getRequests(filter: _filter, page: nextPage, requestedBy: requestedBy);
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _items = reset ? result.items : [..._items, ...result.items];
        _page = nextPage;
        _totalPages = result.totalPages;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });

      // Titles and artwork are not part of the request payload and have to be
      // resolved per title, so the rows land first and fill themselves in. The
      // alternative is holding a page of twenty back on a metadata round trip
      // that may never come.
      final hydrated = await client.hydrateRequests(result.items);
      if (!mounted || gen != _loadGen) return;
      final byId = {for (final r in hydrated) r.id: r};
      setState(() {
        _items = [for (final r in _items) byId[r.id] ?? r];
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

  Future<void> _loadCounts() async {
    final client = context.read<SeerrProvider>().client;
    if (client == null) return;
    final counts = await client.getRequestCounts();
    if (mounted) setState(() => _counts = counts);
  }

  void _onFilter(String filter) {
    if (filter == _filter) return;
    setState(() => _filter = filter);
    _revealSelectedFilter();
    _load(reset: true);
  }

  /// Runs a request action behind a blocking busy indicator, then reloads the
  /// current filter from page 1 (simplest correct refresh).
  Future<void> _runAction(Future<void> Function(SeerrClient client) action) async {
    final provider = context.read<SeerrProvider>();
    final client = provider.client;
    if (client == null) return;
    final messenger = ScaffoldMessenger.of(context);
    String? errText;
    try {
      await showCancellableLoadingDialog(
        context: context,
        timeout: MediaServerTimeouts.interactive,
        timeoutMessage: t.common.timedOut,
        task: action(client),
      );
    } on SeerrException catch (e) {
      errText = _errorText(e);
    } catch (_) {
      errText = t.seerr.errorGeneric;
    }
    if (!mounted) return;
    if (errText != null) {
      messenger.showSnackBar(SnackBar(content: Text(errText)));
      return;
    }
    // The counts come from a separate endpoint, so approving or cancelling
    // leaves them a page behind unless they are asked for again. Not awaited:
    // the list refresh below is what the user is waiting for.
    unawaited(_loadCounts());
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
        SliverToBoxAdapter(child: _discoverBar()),
        ..._contentSlivers(canManage, ownUserId),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _filterRow() {
    final tabs = <(String, String, int?)>[
      ('all', t.seerr.filterAll, _counts?.total),
      ('pending', t.seerr.filterPending, _counts?.pending),
      ('approved', t.seerr.filterApproved, _counts?.approved),
      ('available', t.seerr.filterAvailable, _counts?.available),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: SingleChildScrollView(
        controller: _filterScrollController,
        scrollDirection: Axis.horizontal,
        // Inset lives on the scroll view, not around it: as padding around the
        // scrollport it is outside the scrollable area, so the first and last
        // chip ended up hard against the viewport edge the moment the strip was
        // dragged. Here it scrolls with the content and stays a real margin.
        padding: const EdgeInsets.symmetric(horizontal: _hInset),
        child: SegmentedTabGroup(
          children: [
            for (var i = 0; i < tabs.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              FocusableTabChip(
                key: _filterChipKeys[tabs[i].$1],
                style: TabChipStyle.segmented,
                label: (tabs[i].$3 ?? 0) > 0 ? '${tabs[i].$2}  ${tabs[i].$3}' : tabs[i].$2,
                isSelected: _filter == tabs[i].$1,
                onSelect: () => _onFilter(tabs[i].$1),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Brings the active filter fully into view, with the same inset the strip
  /// starts with. Without this the selected chip could sit off-screen entirely,
  /// and the focus system's own ensureVisible scrolls the minimum distance,
  /// which leaves the neighbouring chip cut in half.
  void _revealSelectedFilter() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_filterScrollController.hasClients) return;
      final context = _filterChipKeys[_filter]?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        alignment: 0.5,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  /// Entry point to the discover screen. Without it this page is a dead end:
  /// you can review requests but never start one.
  Widget _discoverBar() {
    final tk = tokens(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(_hInset, 8, _hInset, 12),
      child: FocusableWrapper(
        disableScale: true,
        borderRadius: 12,
        onSelect: _openDiscover,
        // The button that used to spell this out is gone, so the destination
        // has to be named for a screen reader.
        semanticLabel: t.seerr.discoverTitle,
        child: GestureDetector(
          onTap: _openDiscover,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: tk.surface,
              borderRadius: BorderRadius.circular(tk.radiusMd),
              border: Border.all(color: tk.outline.withValues(alpha: 0.7)),
            ),
            // The whole bar is one target that opens discover, so the filled
            // "Discover" button was a second label for what the row already
            // does -- and on a phone it squeezed the placeholder onto two
            // lines. A trailing chevron says "this goes somewhere" in the space
            // of a glyph and leaves the sentence room to read.
            child: Row(
              children: [
                AppIcon(Symbols.search_rounded, fill: 1, size: 20, color: tk.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t.seerr.searchPlaceholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: tk.textMuted),
                  ),
                ),
                const SizedBox(width: 8),
                AppIcon(Symbols.chevron_right_rounded, size: 20, color: tk.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openDiscover() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SeerrDiscoverScreen()));
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
          return SeerrRequestRow(
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
