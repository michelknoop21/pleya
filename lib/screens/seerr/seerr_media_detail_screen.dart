import 'dart:async';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../focus/focusable_button.dart';
import '../../focus/key_event_utils.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_identity.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../models/seerr/seerr_media.dart';
import '../../navigation/tv/tv_content_route_registry.dart';
import '../../navigation/tv/tv_nested_surface.dart';
import '../../models/seerr/seerr_request.dart';
import '../../providers/seerr_provider.dart';
import '../../providers/watchlist_provider.dart';
import '../../services/companion_remote/companion_remote_receiver.dart';
import '../../services/seerr/seerr_client.dart';
import '../../services/seerr/seerr_constants.dart';
import '../../services/settings_service.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/formatters.dart' show formatDurationTextual;
import '../../utils/external_ids.dart';
import '../../utils/layout_constants.dart';
import '../../utils/media_navigation_helper.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/collapsible_text.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/overlay_sheet.dart';
import '../../widgets/pressable.dart';
import '../../widgets/seerr_poster_card.dart';
import '../../widgets/seerr_request_form_parts.dart';
import '../../widgets/seerr_request_sheet.dart';
import '../../widgets/seerr_status_badge.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/state_view.dart';
import '../media_detail_screen.dart';
import 'seerr_requests_screen.dart';

part 'seerr_media_detail_parts.dart';

/// A graphical detail page for a Jellyseerr / Overseerr media item, styled to
/// match the app's own [MediaDetailScreen] (hero backdrop + poster + metadata +
/// action). Loads the full detail (genres, runtime, cast) on open and offers a
/// recommendations row, so browsing seerr results feels like browsing the
/// library instead of a bare list.
class SeerrMediaDetailScreen extends StatefulWidget {
  const SeerrMediaDetailScreen({super.key, required this.media, this.onStatusChanged, this.libraryDetailRoute});

  /// Builds the library detail route for a matched item. Null uses the app's
  /// own detail page; a test hands in a page it can see without mounting one.
  @visibleForTesting
  final PageRoute<bool> Function(MediaItem match)? libraryDetailRoute;

  /// The search/discover row that was tapped. Its poster/title render instantly
  /// while the full detail loads.
  final SeerrMedia media;

  /// Called when a load finds a status other than the one last reported, so the
  /// card this page was opened from can follow it.
  final ValueChanged<SeerrMediaStatus>? onStatusChanged;

  @override
  State<SeerrMediaDetailScreen> createState() => _SeerrMediaDetailScreenState();
}

class _SeerrMediaDetailScreenState extends State<SeerrMediaDetailScreen> {
  SeerrMediaDetail? _detail;
  List<SeerrMedia> _recommendations = const [];
  bool _loading = true;
  bool _errored = false;
  bool _network = false;

  /// A reload failed while an older answer is on screen. That answer may be
  /// out of date, so it is not acted on: no request, no library route.
  bool _stale = false;

  /// The library item this title resolves to by its TMDB id, when one of the
  /// profile's servers has it. Null is "not proven", never "not there".
  MediaItem? _libraryMatch;

  late SeerrMediaStatus _reportedStatus = widget.media.status;
  bool _reportsStatus = true;
  int _loadGen = 0;

  SeerrMedia get _base => _detail?.media ?? widget.media;

  SeerrClient? _boundClient;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A profile switch swaps the client. What is on screen then describes
    // another account's view of this title, so the page asks again.
    final client = Provider.of<SeerrProvider>(context).client;
    if (_started && identical(client, _boundClient)) return;
    final restart = _started;
    _started = true;
    if (restart) {
      _detail = null;
      _libraryMatch = null;
      _recommendations = const [];
      _stale = false;
      // The card this page was opened from belongs to the previous account's
      // list, so nothing learned from here on is reported back to it.
      _reportsStatus = false;
    }
    unawaited(_load());
  }

  Future<void> _load() async {
    final client = context.read<SeerrProvider>().client;
    _boundClient = client;
    final gen = ++_loadGen;
    if (client == null) {
      setState(() {
        _loading = false;
        _errored = true;
      });
      return;
    }
    setState(() {
      _loading = true;
      _errored = false;
    });
    // An answer for another account, or for a load a newer one has replaced,
    // says nothing about what is on screen now.
    bool current() => mounted && gen == _loadGen && identical(context.read<SeerrProvider>().client, client);
    try {
      final detail = await client.getMediaDetail(tmdbId: widget.media.tmdbId, isMovie: widget.media.isMovie);
      if (!mounted || !current()) return;
      setState(() {
        _detail = detail;
        _loading = false;
        _stale = false;
      });
      final status = detail.media.status;
      if (_reportsStatus && status != _reportedStatus) {
        _reportedStatus = status;
        widget.onStatusChanged?.call(status);
      }
      unawaited(_loadRecommendations(client, gen));
      unawaited(_resolveLibraryMatch(status, gen));
    } catch (e) {
      if (!mounted || !current()) return;
      setState(() {
        _loading = false;
        _errored = true;
        _stale = _detail != null;
        _network = e is SeerrException && e.isNetwork;
      });
    }
  }

  Future<void> _loadRecommendations(SeerrClient client, int gen) async {
    try {
      final page = await client.getRecommendations(tmdbId: widget.media.tmdbId, isMovie: widget.media.isMovie);
      if (!mounted || gen != _loadGen || !identical(context.read<SeerrProvider>().client, client)) return;
      setState(() => _recommendations = page.items);
    } catch (_) {
      // Recommendations are a nicety — silently skip on failure.
    }
  }

  /// Looks the title up on the profile's own servers, by TMDB id only.
  ///
  /// Seerr calling a title available says its own server has it. Whether this
  /// profile can reach it is a second question, and the one identity pipeline
  /// the watchlist already uses answers it. No title is passed, so a match is
  /// an id match and never a lookalike found by name.
  Future<void> _resolveLibraryMatch(SeerrMediaStatus status, int gen) async {
    if (!status.isAvailable && status != SeerrMediaStatus.partiallyAvailable) return;
    final resolver = context.read<WatchlistProvider?>()?.resolver;
    if (resolver == null) return;
    try {
      final result = await resolver.resolveIdentity(
        MediaIdentity(
          externalIds: ExternalIds(tmdb: widget.media.tmdbId),
          kind: widget.media.isMovie ? MediaKind.movie : MediaKind.show,
        ),
        cacheKey: 'seerr:${widget.media.mediaType}:${widget.media.tmdbId}',
      );
      if (!mounted || gen != _loadGen) return;
      setState(() => _libraryMatch = result.match);
    } catch (_) {
      // Not proven is the safe answer: the search route stays.
    }
  }

  Future<void> _openRequest() async {
    // The reload runs the moment the server confirms, so backing out of the
    // confirmation leaves the status as fresh as pressing Sluiten does.
    await SeerrRequestSheet.show(
      context,
      media: _base,
      onRequested: () => unawaited(_load()),
      onOpenMyRequests: _openMyRequests,
    );
  }

  /// The viewer's own request for this title, as the current account's server
  /// lists it: the pending one when there is one, otherwise the newest.
  SeerrRequest? get _ownRequest {
    final ownId = context.read<SeerrProvider>().session?.userId;
    if (ownId == null) return null;
    final own = [
      for (final r in _detail?.requests ?? const <SeerrRequest>[])
        if (r.requestedById == ownId) r,
    ]..sort((a, b) => b.id.compareTo(a.id));
    return own.where((r) => r.isPending).firstOrNull ?? own.firstOrNull;
  }

  /// "Mijn aanvraag" opens the viewer's own list on the request for this
  /// title, not at the top of everything they ever asked for.
  void _openMyRequests() {
    final id = _ownRequest?.id;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => SeerrRequestsScreen(mineOnly: true, focusRequestId: id)));
  }

  /// The existing library detail for a title that was matched by id. Opens the
  /// page, never the player.
  ///
  /// On TV that detail is normally a content route *inside* the shell (PB-1),
  /// while this page is a route on the profile navigator, drawn over the shell.
  /// Sent through the shell from here, the detail would open underneath this
  /// page, where nobody sees it. So from a page that covers the shell the
  /// detail is pushed on the same navigator this page is on: it is on top,
  /// and Back returns here, to the action that opened it.
  ///
  /// Everywhere else, and when this page is itself nested, the shared helper
  /// decides, as it does for every other caller.
  void _openInLibrary(MediaItem match) {
    final coversShell = tvContentRouteRegistry.isAvailable && TvNestedRouteScope.readOf(context) == null;
    if (!coversShell) {
      unawaited(navigateToMediaItemDetails(context, match));
      return;
    }
    final build = widget.libraryDetailRoute ?? _libraryDetailRoute;
    unawaited(Navigator.of(context).push(build(match)));
  }

  PageRoute<bool> _libraryDetailRoute(MediaItem match) {
    final target = mediaDetailNavigationTargetIn(context, match);
    return mediaDetailRoute(
      metadata: target.metadata,
      initialSeasonIndex: target.initialSeasonIndex,
      initialSeasonId: target.initialSeasonId,
      initialEpisodeId: target.initialEpisodeId,
    );
  }

  /// The existing library search, with the title as the query. For a title
  /// Seerr calls available that no reachable server was matched to.
  void _searchInLibrary() {
    final open = CompanionRemoteReceiver.instance.onSearchAction;
    if (open == null) return;
    final title = _base.title;
    Navigator.of(context).popUntil((route) => route.isFirst);
    open(title);
  }

  /// What the buttons under the title offer for the state the page is in.
  List<_DetailAction> _actions() {
    final provider = context.read<SeerrProvider>();
    final refresh = _DetailAction('refresh', t.seerr.refreshStatus, Symbols.refresh_rounded, () => unawaited(_load()));
    // The first answer is still on its way. One button that does nothing yet
    // holds the focus, because a TV page with nothing to focus cannot be left;
    // the real primary action takes its place, and its focus, when it lands.
    if (_loading && _detail == null) {
      return [_DetailAction('loading', t.common.loading, Symbols.hourglass_empty_rounded, () {})];
    }
    // Unknown is not available and not requestable.
    if (_stale) return [refresh];

    final status = _base.status;
    final ownId = provider.session?.userId;
    final requests = _detail?.requests ?? const [];
    final hasOwn = ownId != null && requests.any((r) => r.requestedById == ownId);
    final request = _DetailAction('request', t.seerr.request, Symbols.playlist_add_rounded, _openRequest);
    final mine = _DetailAction('mine', t.seerr.myRequest, Symbols.inbox_rounded, _openMyRequests);
    final match = _libraryMatch;
    final library = match != null
        ? _DetailAction('library', t.seerr.openInLibrary, Symbols.video_library_rounded, () => _openInLibrary(match))
        : (CompanionRemoteReceiver.instance.onSearchAction == null
              ? null
              : _DetailAction('search', t.seerr.searchInLibrary, Symbols.search_rounded, _searchInLibrary));

    return switch (status) {
      SeerrMediaStatus.unknown => [request],
      SeerrMediaStatus.pending => [if (hasOwn) mine, refresh],
      SeerrMediaStatus.processing => [refresh, if (hasOwn) mine],
      SeerrMediaStatus.partiallyAvailable => [
        if (!_base.isMovie)
          _DetailAction('request', t.seerr.requestMoreSeasons, Symbols.playlist_add_rounded, _openRequest),
        ?library,
        refresh,
      ],
      SeerrMediaStatus.available => [?library, refresh],
    };
  }

  /// The viewer's own request for this title was declined and nothing newer
  /// replaced it.
  bool get _ownDeclined {
    final ownId = context.read<SeerrProvider>().session?.userId;
    if (ownId == null || _base.status != SeerrMediaStatus.unknown) return false;
    final own = [
      for (final r in _detail?.requests ?? const <SeerrRequest>[])
        if (r.requestedById == ownId) r,
    ];
    return own.isNotEmpty && own.every((r) => r.status == SeerrRequestStatus.declined);
  }

  void _openMedia(SeerrMedia media) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SeerrMediaDetailScreen(media: media)));
  }

  @override
  Widget build(BuildContext context) {
    // Host so the request sheet gets the TV overlay path (focus trap, D-pad
    // back) instead of the focusless showModalBottomSheet fallback — this
    // screen is pushed straight from search results.
    return OverlaySheetHost(
      // canPop preserves the iOS interactive swipe-back (same as hub detail).
      canPop: PlatformDetector.isHandheldIOS(context),
      onSystemBack: () {
        if (BackKeyCoordinator.consumeIfHandled()) return;
        if (mounted) Navigator.pop(context);
      },
      child: FocusedScrollScaffold(
        title: Text(_base.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        slivers: _buildSlivers(),
      ),
    );
  }

  List<Widget> _buildSlivers() {
    if (_loading && _detail == null) {
      return [
        SliverToBoxAdapter(
          child: _HeroHeader(media: widget.media, detail: null, actions: _actions(), busy: true),
        ),
        const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.all(24), child: _DetailSkeleton()),
        ),
      ];
    }

    if (_errored && _detail == null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: StateView.error(
            title: _network ? t.seerr.errorNetwork : t.seerr.errorGeneric,
            icon: Symbols.cloud_off_rounded,
            onRetry: _load,
            retryLabel: t.common.retry,
          ),
        ),
      ];
    }

    final detail = _detail;
    final inset = PlatformDetector.isTV() ? TvLayoutConstants.horizontalInset : 12.0;
    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: _HeroHeader(
          media: _base,
          detail: detail,
          actions: _actions(),
          note: _stale ? t.seerr.statusNotRefreshed : (_ownDeclined ? t.seerr.requestDeclinedNote : null),
          busy: _loading,
        ),
      ),
    ];

    if ((_base.overview ?? '').isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(inset, 16, inset, 8),
            child: CollapsibleText(text: _base.overview!),
          ),
        ),
      );
    }

    if (detail != null && detail.cast.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: _CastRow(cast: detail.cast, inset: inset),
        ),
      );
    }

    if (_recommendations.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: _PosterRow(
            title: t.seerr.recommendations,
            items: _recommendations,
            inset: inset,
            onTapItem: _openMedia,
          ),
        ),
      );
    }

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));
    return slivers;
  }
}
