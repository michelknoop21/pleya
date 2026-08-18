import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.g.dart';
import '../media/watch_session.dart';
import '../providers/now_watching_provider.dart';
import '../utils/media_navigation_helper.dart';
import '../widgets/desktop_app_bar.dart';
import '../widgets/now_watching/now_watching_panel.dart';

/// The full-screen list of active streams.
///
/// This is the TV route. An overlay under a toolbar button cannot be focused
/// with a remote, which is why the server-tasks panel is switched off there, so
/// the same content becomes a page whose rows the D-pad walks and which Back
/// leaves.
///
/// It closes itself when the last stream ends. An empty page saying nobody is
/// watching would be a screen you have to dismiss to learn nothing.
class NowWatchingScreen extends StatefulWidget {
  const NowWatchingScreen({super.key});

  @override
  State<NowWatchingScreen> createState() => _NowWatchingScreenState();
}

class _NowWatchingScreenState extends State<NowWatchingScreen> {
  NowWatchingProvider? _provider;

  /// A pop takes a frame or two, during which this still builds and still
  /// reports `mounted` and `canPop`. Without this the second build would
  /// schedule a second pop and take the screen underneath with it.
  bool _popping = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<NowWatchingProvider?>();
    if (identical(provider, _provider)) return;
    _provider?.releaseDetail();
    _provider = provider?..watchDetail();
  }

  @override
  void dispose() {
    _provider?.releaseDetail();
    super.dispose();
  }

  Future<void> _openSession(WatchSession session) async {
    final ratingKey = session.ratingKey;
    final provider = _provider;
    if (ratingKey == null || provider == null) return;

    final item = await provider.resolveItem(ratingKey);
    if (item == null || !mounted) return;
    await navigateToMediaItem(context, item);
  }

  @override
  Widget build(BuildContext context) {
    final now = context.watch<NowWatchingProvider?>()?.now;

    // Nothing left to show: leave rather than stand on an empty page. Deferred
    // to after the frame because this can land during a rebuild, and guarded so
    // it happens exactly once.
    if (now != null && !now.hasOthers && !_popping) {
      _popping = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      });
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          CustomAppBar(title: Text(t.nowWatching.title)),
          if (now != null && now.hasOthers)
            SliverToBoxAdapter(
              child: NowWatchingPanel(now: now, large: true, onOpenSession: _openSession),
            ),
        ],
      ),
    );
  }
}
