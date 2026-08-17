import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../models/seerr/seerr_media.dart';
import '../../providers/seerr_provider.dart';
import '../../services/seerr/seerr_client.dart';
import '../../utils/seerr_error_message.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/state_view.dart';
import 'seerr_grid_sliver.dart';
import 'seerr_media_detail_screen.dart';

/// One discover row, expanded to a full grid. The carousels on discover only
/// show what fits on screen; this is where "show all" lands so browsing a row
/// works the same as browsing a library.
class SeerrRowGridScreen extends StatefulWidget {
  const SeerrRowGridScreen({super.key, required this.title, required this.fetch});

  final String title;
  final Future<SeerrMediaPage> Function(SeerrClient client, int page) fetch;

  @override
  State<SeerrRowGridScreen> createState() => _SeerrRowGridScreenState();
}

class _SeerrRowGridScreenState extends State<SeerrRowGridScreen> {
  List<SeerrMedia> _items = const [];
  int _page = 0;
  int _totalPages = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _errored = false;
  SeerrErrorKind _errorKind = SeerrErrorKind.generic;

  bool get _hasMore => _page < _totalPages;

  @override
  void initState() {
    super.initState();
    unawaited(_load(reset: true));
  }

  Future<void> _load({bool reset = false}) async {
    final client = context.read<SeerrProvider>().client;
    if (client == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (reset) {
      setState(() {
        _loading = true;
        _errored = false;
      });
    } else {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    }
    try {
      final next = reset ? 1 : _page + 1;
      final result = await widget.fetch(client, next);
      if (!mounted) return;
      setState(() {
        _items = reset ? result.items : [..._items, ...result.items];
        _page = result.page;
        _totalPages = result.totalPages;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (reset) {
          _errored = true;
          _errorKind = seerrErrorKindOf(e);
        }
      });
    }
  }

  void _openDetail(SeerrMedia media) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SeerrMediaDetailScreen(media: media)));
  }

  @override
  Widget build(BuildContext context) {
    return FocusedScrollScaffold(
      title: Text(widget.title),
      slivers: [
        if (_loading)
          const SliverPadding(
            padding: EdgeInsets.only(top: 48),
            sliver: SliverToBoxAdapter(child: Center(child: CircularProgressIndicator())),
          )
        else if (_errored)
          SliverFillRemaining(
            hasScrollBody: false,
            child: StateView.error(
              title: seerrErrorMessage(_errorKind),
              icon: Symbols.cloud_off_rounded,
              onRetry: () => unawaited(_load(reset: true)),
              retryLabel: t.common.retry,
            ),
          )
        else if (_items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: StateView.empty(title: t.seerr.noResults, icon: Symbols.search_off_rounded),
          )
        else
          buildSeerrGridSliver(
            items: _items,
            onTap: _openDetail,
            hasMore: _hasMore,
            loadingMore: _loadingMore,
            onLoadMore: () => unawaited(_load()),
          ),
      ],
    );
  }
}
