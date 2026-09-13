/// Mijn Pleya ▸ Activiteit on TV (MOC-16b).
///
/// Before this existed, `TvMyPleyaSection.activity` mounted the shared
/// [NowWatchingScreen] (`lib/screens/now_watching_screen.dart`) — a
/// `Scaffold`/`CustomAppBar` built for a `Navigator.push` from mobile and
/// desktop. Inside a [TvNestedRoute] that screen's `Navigator.pop` reaches the
/// profile navigator that owns the whole shell instead of just closing this
/// route (ACT2). This screen is the ten-foot presentation on the shared
/// [TvPageSurface] frame, dismissing itself through [TvNestedRouteScope]
/// exactly as `FocusableDetailScreenMixin.dismissDetailScreen` does elsewhere.
///
/// [NowWatchingPanel] itself needs no change: it is already shared by the
/// desktop overlay, the mobile sheet and this screen, and its rows are already
/// remote-focusable.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../i18n/strings.g.dart';
import '../../../media/watch_session.dart';
import '../../../navigation/tv/tv_nested_surface.dart';
import '../../../providers/now_watching_provider.dart';
import '../../../utils/media_navigation_helper.dart';
import '../../../widgets/now_watching/now_watching_panel.dart';
import '../../../widgets/tv/tv_page_surface.dart';

class TvNowWatchingScreen extends StatefulWidget {
  const TvNowWatchingScreen({super.key});

  @override
  State<TvNowWatchingScreen> createState() => _TvNowWatchingScreenState();
}

class _TvNowWatchingScreenState extends State<TvNowWatchingScreen> {
  NowWatchingProvider? _provider;

  /// Same guard as the shared screen: a dismiss takes a frame, during which
  /// this still builds and would otherwise schedule a second one.
  bool _dismissing = false;

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

  /// Closes this route through the nested-route coordinator when there is
  /// one, so a route inside a [TvNestedRoute] never falls through to
  /// `Navigator.pop` and takes the shell's own navigator down with it (ACT2).
  void _dismiss([Object? result]) {
    final nested = TvNestedRouteScope.of(context);
    if (nested != null) {
      nested.dismiss(result);
      return;
    }
    if (Navigator.canPop(context)) Navigator.pop(context, result);
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

    // Every entry on this destination's nested-route stack shares the same
    // dismiss callback (`TvRootShell`'s `dismissNestedRoute`), which always
    // pops whatever is currently on top — not the entry that called it. This
    // screen keeps rebuilding on provider changes even while a route it
    // opened (e.g. a session's detail page, via `_openSession`) covers it, so
    // without this check an empty state reached while covered would kick the
    // user out of that detail page instead of closing itself. `TickerMode`
    // is the shell's own covered/on-top signal (`TvRootShell` wraps every
    // stack entry in `TickerMode(enabled: i == stack.length - 1)`), so riding
    // it here needs no new plumbing, and a later uncover re-triggers this
    // build and re-evaluates the same check.
    final onTop = TickerMode.valuesOf(context).enabled;

    // Nothing left to show: leave rather than stand on an empty page, exactly
    // as the shared screen does. Deferred to after the frame because this can
    // land during a rebuild, and guarded so it happens exactly once.
    if (onTop && now != null && !now.hasOthers && !_dismissing) {
      _dismissing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && TickerMode.valuesOf(context).enabled) _dismiss();
      });
    }

    return TvPageSurface(
      title: t.nowWatching.title,
      automationInstance: 'activity',
      children: [
        if (now != null && now.hasOthers) NowWatchingPanel(now: now, large: true, onOpenSession: _openSession),
      ],
    );
  }
}
