import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.g.dart';
import '../media/watchlist_entry.dart';
import '../providers/offline_mode_provider.dart';
import '../providers/watchlist_provider.dart';
import '../widgets/desktop_app_bar.dart';
import '../widgets/state_view.dart';

/// The full kijklijst.
///
/// A flat grid in the order titles were added, available and unavailable mixed
/// together. Grouping by availability was considered and dropped: it needs the
/// whole list resolved before the screen can settle, so at 300 titles across
/// several servers the grid would keep reflowing while answers trickle in, and
/// that fights the lazy resolver instead of using it. Ordering by availability
/// is still possible, but only when the user asks for it through the filter.
class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  bool _requestedLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requestedLoad) return;
    _requestedLoad = true;
    final provider = context.read<WatchlistProvider?>();
    final isOffline = context.read<OfflineModeProvider?>()?.isOffline ?? false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) provider?.load(offline: isOffline);
    });
  }

  Future<void> _reload() async {
    final isOffline = context.read<OfflineModeProvider?>()?.isOffline ?? false;
    await context.read<WatchlistProvider?>()?.load(offline: isOffline);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WatchlistProvider?>();
    final entries = provider?.entriesByRecentlyAdded ?? const <WatchlistEntry>[];

    return Scaffold(
      body: CustomScrollView(
        // Not the default Clip.hardEdge: a focused card grows a ring that would
        // otherwise be sheared off at the viewport edge on TV.
        clipBehavior: Clip.none,
        slivers: [
          CustomAppBar(title: Text(t.watchlist.title), automaticallyImplyLeading: false),
          if (provider == null || (provider.isLoading && entries.isEmpty))
            const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
          else if (entries.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: StateView.empty(
                icon: Symbols.bookmark_add_rounded,
                title: t.watchlist.empty,
                message: t.watchlist.emptyBody,
                // Without a retry there is no focusable element left on this
                // screen, and a TV remote has nowhere to go.
                onRetry: _reload,
                retryLabel: t.watchlist.retry,
              ),
            )
          else
            SliverList.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) => ListTile(
                title: Text(entries[index].item.title ?? ''),
                subtitle: Text('${entries[index].item.year ?? ''}'),
              ),
            ),
        ],
      ),
    );
  }
}
