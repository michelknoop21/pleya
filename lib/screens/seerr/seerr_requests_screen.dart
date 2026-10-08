import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../models/seerr/seerr_media.dart';
import '../../models/seerr/seerr_request.dart';
import '../../navigation/main_screen_scope.dart';
import '../../providers/seerr_provider.dart';
import '../../services/seerr/seerr_client.dart';
import '../../services/seerr/seerr_constants.dart';
import '../../services/seerr/seerr_request_rights.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/dialogs.dart';
import '../../utils/platform_detector.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/focusable_tab_chip.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/overlay_sheet.dart';
import '../../widgets/segmented_tab_group.dart';
import '../../widgets/seerr_request_actions_sheet.dart';
import '../../widgets/seerr_request_edit_sheet.dart';
import '../../widgets/seerr_request_row.dart';
import '../../widgets/state_view.dart';
import '../tv/tv_seerr_requests_view.dart';
import 'seerr_discover_screen.dart';
import 'seerr_media_detail_screen.dart';
import 'seerr_requests_list_parts.dart';

export 'seerr_requests_list_parts.dart' show SeerrAutoLoadMoreListTile;

part 'seerr_requests_screen_body.dart';

/// Jellyseerr / Overseerr requests-management screen.
///
/// Lists the current profile's requests (or every request for managers) with
/// a status filter, page-append pagination, and the actions a request allows:
/// approve, decline, edit, cancel. Off TV those sit on the row; on TV they are
/// behind the card's context menu (DEC-108).
///
/// Three things here are about not saying more than the server said:
///
/// * **Scope.** A list scoped to the viewer shows no counts, because
///   `/request/count` counts everyone's. A viewer whose Seerr user id is not
///   known gets an explanation, never an unscoped list.
/// * **Filter.** Seerr's list route has no `declined` case and answers with
///   every status. The rows that come back are checked, and a mixed answer is
///   shown as a filter this server cannot do rather than as Afgewezen.
/// * **Session.** Every answer is dropped when the profile's Seerr client was
///   swapped while it was on the wire.
class SeerrRequestsScreen extends StatefulWidget {
  /// [mineOnly] scopes the list to the viewer's own requests, also for a manager. The
  /// phone's "Mijn aanvragen" header opens it that way; the header must not promise the
  /// viewer's own requests and then show everyone's.
  const SeerrRequestsScreen({super.key, this.mineOnly = false, this.focusRequestId});

  final bool mineOnly;

  /// The viewer's own request this page was opened for ("Mijn aanvraag" on a
  /// title page). The list lands on it instead of on its first row. Only used
  /// with [mineOnly], and only for the account the page opened under.
  final int? focusRequestId;

  @override
  State<SeerrRequestsScreen> createState() => _SeerrRequestsScreenState();
}

class _SeerrRequestsScreenState extends State<SeerrRequestsScreen> {
  static const double _hInset = 16;
  static const int _pageSize = 20;

  TvSeerrRequestFilter _filter = TvSeerrRequestFilter.all;
  List<SeerrRequest> _items = const [];
  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  bool _initialized = false;
  String? _error;

  /// The viewer's list was asked for and their Seerr user id is not known.
  bool _ownScopeUnknown = false;

  /// The server answered the chosen filter with rows of another status.
  bool _filterUnsupported = false;

  // Bumped on each load so a filter switch (reset load) can invalidate an
  // in-flight load-more, preventing stale-filter items from being appended.
  int _loadGen = 0;
  int _countsGen = 0;

  /// The Seerr client every piece of state above was loaded with.
  SeerrClient? _boundClient;

  /// Requests with an action on the wire. A second action on the same request
  /// is refused until the first has an answer.
  final Set<int> _busy = {};

  /// Requests whose last action was sent without a readable answer, and whose
  /// state could not be read back either. They stay locked, in [_busy], until
  /// a list read succeeds: offering the action again would be a blind resend.
  final Set<int> _unresolved = {};
  final Map<int, int?> _unresolvedOwners = {};

  /// A manager's choice between everyone's requests and their own. Starts at
  /// what the page was opened as; a viewer who cannot manage has no choice and
  /// is on their own list whatever this says (see [_ownOnly]).
  late bool _mine = widget.mineOnly;

  /// The request this page was opened for, for as long as it is the viewer's
  /// own and this is their own list. It stays first and keeps one key and one
  /// focus node through every reload, so the focus that landed on it is still
  /// on it after an action, a refresh or another page.
  late int? _chosenId = widget.mineOnly ? widget.focusRequestId : null;

  /// Whether the focus has been put on [_chosenId] once. Landing happens one
  /// time; the identity above outlives it.
  bool _landed = false;
  final FocusNode _focusTargetNode = FocusNode(debugLabel: 'SeerrRequestFocusTarget');
  final GlobalKey _focusTargetKey = GlobalKey(debugLabel: 'SeerrRequestFocusTarget');

  final ScrollController _filterScrollController = ScrollController();
  static const _filterKeys = ['all', 'pending', 'approved', 'available', 'declined'];
  final Map<String, GlobalKey> _filterChipKeys = {for (final k in _filterKeys) k: GlobalKey()};

  /// The TV presentation. It owns the rail, the grid and the focus traversal;
  /// this state owns the fetches, the actions and the counts.
  final GlobalKey<TvSeerrRequestsViewState> _tvKey = GlobalKey<TvSeerrRequestsViewState>();

  /// Null while not known. [_countsFailed] tells "not asked or not answered
  /// yet" from "asked and no answer".
  SeerrRequestCounts? _counts;
  bool _countsFailed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Registers the dependency, so a profile switch that swaps the client
    // lands here and the page starts over for the new account.
    final client = Provider.of<SeerrProvider>(context).client;
    final first = !_initialized;
    if (!first && identical(client, _boundClient)) return;
    _initialized = true;
    _boundClient = client;
    // A request id from the previous account names nothing on this one.
    if (!first) _chosenId = null;
    _items = const [];
    _counts = null;
    _countsFailed = false;
    // Another account: its requests are other requests, whatever their ids.
    _busy.clear();
    _unresolved.clear();
    _unresolvedOwners.clear();
    _page = 1;
    _hasMore = false;
    unawaited(_load(reset: true));
    unawaited(_loadCounts());
    if (first) {
      _revealSelectedFilter();
      _requestTvEntryFocus();
    }
  }

  /// The focus this page lands on when it opens, on TV.
  ///
  /// Off TV `FocusedScrollScaffold` does this itself: it owns a scope and calls
  /// `nextFocus()` on it once, in keyboard mode. The TV branch does not go
  /// through that scaffold any more (DEC-108), so nothing asked, and a pushed
  /// Alle aanvragen came up with the page focused and no item on it. On tvOS
  /// that is a page you cannot leave, because the engine claims every press
  /// before UIKit's responder chain sees it.
  ///
  /// The view answers it rather than this state: it knows whether the rail is
  /// open, and it keeps asking until the first page has actually arrived —
  /// at this point the grid is still a skeleton with nothing focusable in it.
  void _requestTvEntryFocus() {
    if (!PlatformDetector.isTV()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tvKey.currentState?.focusContent();
    });
  }

  @override
  void dispose() {
    _filterScrollController.dispose();
    _focusTargetNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  /// A non-manager may only see their own requests, and "Mijn aanvragen" is
  /// the viewer's own list for a manager too.
  bool _ownOnly(SeerrProvider provider) => _mine || !provider.canManageRequests;

  /// Switches a manager between all requests and their own.
  ///
  /// Rows and counts belong to the scope they were loaded for, so they go. The
  /// load that follows bumps the generation, which is what makes an answer
  /// still on its way for the old scope land nowhere.
  ///
  /// The locks stay. A scope is a way of looking at the same account's
  /// requests, not a different set of them: an approve that is still on the
  /// wire is on the wire in both views, and a request that turns up again in
  /// the other one must not offer the action a second time.
  void _setScope(bool mine) {
    if (!context.read<SeerrProvider>().canManageRequests || mine == _mine) return;
    setState(() {
      _mine = mine;
      _items = const [];
      _counts = null;
      _countsFailed = false;
      _page = 1;
      _hasMore = false;
      _chosenId = null;
    });
    _reload();
  }

  bool _isCurrent(SeerrClient client, int gen) =>
      mounted && gen == _loadGen && identical(context.read<SeerrProvider>().client, client);

  /// [reset] starts the filter over at page one. [inPlace] reloads everything
  /// that is already on screen in one call, so a card the viewer is standing on
  /// deep in the list is still there after an action.
  ///
  /// Answers whether the list on screen is now what the server holds.
  Future<bool> _load({bool reset = false, bool inPlace = false}) async {
    if (!mounted) return false;
    final provider = context.read<SeerrProvider>();
    final client = provider.client;
    if (client == null) {
      setState(() => _loading = false);
      return false;
    }
    // Seerr's list route has no `declined` case and answers such a filter with
    // every status. No page it could send proves otherwise: an empty one and
    // one that happens to hold only declined rows look exactly like a filter
    // that worked. So nothing is asked for, and nothing is shown under the name.
    if (_filter == TvSeerrRequestFilter.declined) {
      _loadGen++;
      setState(() {
        _items = const [];
        _loading = false;
        _loadingMore = false;
        _hasMore = false;
        _error = null;
        _filterUnsupported = true;
      });
      return false;
    }
    // Without a known userId a null requestedBy would return everyone's
    // requests (privacy leak), so the list is not asked for at all.
    final ownOnly = _ownOnly(provider);
    final requestedBy = ownOnly ? provider.session?.userId : null;
    if (ownOnly && requestedBy == null) {
      _loadGen++;
      setState(() {
        _items = const [];
        _loading = false;
        _loadingMore = false;
        _hasMore = false;
        _ownScopeUnknown = true;
      });
      return false;
    }
    final gen = ++_loadGen;
    final filter = _filter;
    final fresh = reset || inPlace;
    final pages = inPlace ? _page : 1;
    setState(() {
      _ownScopeUnknown = false;
      if (fresh) {
        _loading = true;
        _error = null;
        _loadMoreFailed = false;
      } else {
        _loadingMore = true;
        _loadMoreFailed = false;
      }
    });
    try {
      final result = fresh
          ? await client.getRequests(filter: filter.wire, take: _pageSize * pages, requestedBy: requestedBy)
          : await client.getRequests(filter: filter.wire, page: _page + 1, take: _pageSize, requestedBy: requestedBy);
      if (!mounted || !_isCurrent(client, gen)) return false;
      // A filter this route does have a case for is still checked against the
      // rows that came back: a server that ignored it must not have its answer
      // shown under the filter's name.
      final honoured = result.items.every((r) => _matches(filter, r));
      setState(() {
        if (fresh && honoured) {
          final more = result.totalPages > 1;
          _settleUnresolved(
            result.items,
            complete: filter == TvSeerrRequestFilter.all && !more,
            requestedBy: requestedBy,
          );
        }
        _filterUnsupported = !honoured;
        // A row that was put in by hand (the request the page was opened for)
        // must not appear a second time when its own page arrives.
        final known = {for (final r in _items) r.id};
        _items = !honoured
            ? const []
            : (fresh ? result.items : [..._items, ...result.items.where((r) => !known.contains(r.id))]);
        _page = fresh ? pages : _page + 1;
        _hasMore = honoured && result.totalPages > (fresh ? 1 : _page);
        _loading = false;
        _loadingMore = false;
        _loadMoreFailed = false;
        _error = null;
      });
      if (!honoured) return false;

      // Titles and artwork are not part of the request payload and have to be
      // resolved per title, so the rows land first and fill themselves in. The
      // alternative is holding a page of twenty back on a metadata round trip
      // that may never come.
      final hydrated = await client.hydrateRequests(result.items);
      if (!mounted || !_isCurrent(client, gen)) return true;
      final byId = {for (final r in hydrated) r.id: r};
      setState(() {
        _items = [for (final r in _items) byId[r.id] ?? r];
      });
      if (fresh) await _keepChosenFirst(client, gen);
      return true;
    } on SeerrException catch (e) {
      if (!mounted || !_isCurrent(client, gen)) return false;
      _loadFailed(fresh, _errorText(e));
      return false;
    } catch (_) {
      if (!mounted || !_isCurrent(client, gen)) return false;
      _loadFailed(fresh, t.seerr.errorGeneric);
      return false;
    }
  }

  /// Releases the requests whose last action had no readable answer, one by
  /// one, on evidence about that request.
  ///
  /// A row that says its status settles it. So does its absence from a list
  /// that is known to be everything in scope (no filter, no further page):
  /// that is what a cancel that went through looks like. A row without a
  /// status, or a page that may simply not contain it, settles nothing.
  void _settleUnresolved(List<SeerrRequest> rows, {required bool complete, required int? requestedBy}) {
    final settled = <int>{};
    for (final id in _unresolved) {
      final row = rows.where((r) => r.id == id).firstOrNull;
      final inScope = requestedBy == null || _unresolvedOwners[id] == requestedBy;
      if (row != null ? row.statusKnown : complete && inScope) settled.add(id);
    }
    _unresolved.removeAll(settled);
    for (final id in settled) {
      _unresolvedOwners.remove(id);
    }
    _busy.removeAll(settled);
  }

  /// Keeps the request the page was opened for at the top, and lands on it the
  /// first time.
  ///
  /// When it is on the page that just loaded it moves to the top. When it is
  /// not, it is read by id, which is one bounded call the server supports, and
  /// shown first only if it is still this viewer's own request. Anything else
  /// (gone, someone else's, unreadable) is said once, and the list stays what
  /// the server sent.
  Future<void> _keepChosenFirst(SeerrClient client, int gen) async {
    final id = _chosenId;
    final provider = context.read<SeerrProvider>();
    final ownId = provider.session?.userId;
    if (id == null || !_ownOnly(provider) || _filter != TvSeerrRequestFilter.all) return;
    if (_items.any((r) => r.id == id)) {
      // Shown first, above the rest in their own order. A list builds its rows
      // as they scroll into view, so a row further down has nothing to put the
      // focus on yet; first is where it can always be found.
      final row = _items.firstWhere((r) => r.id == id);
      setState(() => _items = [row, ..._items.where((r) => r.id != id)]);
    } else {
      SeerrRequest? found;
      try {
        final request = await client.getRequest(id);
        final hydrated = request == null ? const <SeerrRequest>[] : await client.hydrateRequests([request]);
        found = hydrated.firstOrNull;
      } catch (_) {
        found = null;
      }
      if (!mounted || !_isCurrent(client, gen)) return;
      if (found == null || found.id != id || ownId == null || found.requestedById != ownId) {
        final wasShown = _landed;
        setState(() => _chosenId = null);
        // Said when the page could not open on it. Once it has been shown, its
        // going away is the viewer's own doing (a cancel) or already reported.
        if (!wasShown) showAppSnackBar(context, t.seerr.requestNotInOwnList);
        return;
      }
      final row = found;
      setState(() => _items = [row, ..._items.where((r) => r.id != id)]);
    }
    if (_landed) return;
    _landed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _chosenId != id) return;
      if (PlatformDetector.isTV()) {
        _tvKey.currentState?.focusRequest(id);
        return;
      }
      final row = _focusTargetKey.currentContext;
      if (row != null) unawaited(Scrollable.ensureVisible(row, alignment: 0.2));
      if (_focusTargetNode.canRequestFocus) _focusTargetNode.requestFocus();
    });
  }

  void _loadFailed(bool fresh, String message) => setState(() {
    _loading = false;
    _loadingMore = false;
    _loadMoreFailed = !fresh;
    _error = message;
  });

  /// Whether [request] can be an answer to [filter], judged on the one thing
  /// each filter is unambiguous about: the request's own status.
  static bool _matches(TvSeerrRequestFilter filter, SeerrRequest request) => switch (filter) {
    TvSeerrRequestFilter.all => true,
    // A row that does not say its status has not been shown to match anything.
    TvSeerrRequestFilter.pending => request.statusKnown && request.status == SeerrRequestStatus.pending,
    TvSeerrRequestFilter.approved => request.statusKnown && request.status == SeerrRequestStatus.approved,
    // Seerr answers this one with completed requests and older builds with
    // approved ones, and in both the media has arrived in the quality that was
    // asked for. An approved request still waiting for its file is not it.
    TvSeerrRequestFilter.available =>
      request.statusKnown &&
          request.isFulfilled &&
          (request.status == SeerrRequestStatus.completed || request.status == SeerrRequestStatus.approved),
    // Never shown as a list; see [_load].
    TvSeerrRequestFilter.declined => false,
  };

  Future<void> _loadCounts() async {
    final provider = context.read<SeerrProvider>();
    final client = provider.client;
    final gen = ++_countsGen;
    // The counts endpoint has no requester filter: next to the viewer's own
    // list they would be everyone's, so that list is not counted at all.
    if (client == null || _ownOnly(provider)) {
      if (mounted) {
        setState(() {
          _counts = null;
          _countsFailed = false;
        });
      }
      return;
    }
    final counts = await client.getRequestCounts();
    if (!mounted || gen != _countsGen || !identical(context.read<SeerrProvider>().client, client)) return;
    setState(() {
      _counts = counts;
      _countsFailed = counts == null;
    });
  }

  /// The number to show beside [filter], or null when there is none to show.
  ///
  /// `available` and `declined` get none on purpose. The count route calls a
  /// request available when it is approved and its media has arrived, the list
  /// route when it is completed, so the two numbers are about different sets;
  /// and the count route has no declined figure at all.
  int? _countFor(TvSeerrRequestFilter filter) => switch (filter) {
    TvSeerrRequestFilter.all => _counts?.total,
    TvSeerrRequestFilter.pending => _counts?.pending,
    TvSeerrRequestFilter.approved => _counts?.approved,
    TvSeerrRequestFilter.available || TvSeerrRequestFilter.declined => null,
  };

  void _onFilter(TvSeerrRequestFilter filter) {
    if (filter == _filter) return;
    setState(() {
      _filter = filter;
      _filterUnsupported = false;
    });
    _revealSelectedFilter();
    unawaited(_load(reset: true));
  }

  void _reload() {
    unawaited(_loadCounts());
    unawaited(_load(reset: true));
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  SeerrRequestRights _rightsFor(SeerrRequest request) {
    final provider = context.read<SeerrProvider>();
    return SeerrRequestRights.of(
      request,
      ownUserId: provider.session?.userId,
      canManage: provider.canManageRequests,
      isAdmin: provider.isAdmin,
    );
  }

  bool _isOwn(SeerrRequest request) {
    final own = context.read<SeerrProvider>().session?.userId;
    return own != null && request.requestedById == own;
  }

  /// Whether [client] is the one this list was loaded with *and* the one that
  /// is active now. A request id only means something on the account it came
  /// from: after a profile switch the same id is somebody else's request.
  bool _owns(SeerrClient? client) =>
      client != null &&
      mounted &&
      identical(client, _boundClient) &&
      identical(context.read<SeerrProvider>().client, client);

  /// Sends one action for [request], once, through the client the intent
  /// started under, and then re-reads the list whatever the answer was: a
  /// refusal usually means the list was out of date, and a lost connection
  /// means the outcome is not known until it is read back.
  ///
  /// [client] is captured by the caller *before* any menu or confirmation it
  /// awaited. [allowed] is asked again here, against the row as the list holds
  /// it now, so an intent that outlived its account or its right sends nothing.
  Future<void> _runAction(
    SeerrRequest request,
    SeerrClient? client,
    bool Function(SeerrRequestRights rights) allowed,
    Future<void> Function(SeerrClient client) action, {
    required String success,
  }) async {
    if (client == null || !_owns(client) || _busy.contains(request.id)) return;
    final current = _items.where((r) => r.id == request.id).firstOrNull;
    if (current == null || !allowed(_rightsFor(current))) return;
    setState(() => _busy.add(request.id));
    String? failure;
    var uncertain = false;
    try {
      await action(client);
    } on SeerrException catch (e) {
      uncertain = e.outcomeUnknown;
      failure = uncertain
          ? t.seerr.actionUncertain
          : (e.isForbidden || e.isAuth ? t.seerr.errorForbidden : t.seerr.actionFailed);
    } catch (_) {
      uncertain = true;
      failure = t.seerr.actionUncertain;
    }
    if (!mounted || !_owns(client)) return;
    // The counts come from a separate endpoint, so approving or cancelling
    // leaves them a page behind unless they are asked for again. Not awaited:
    // the list refresh below is what the user is waiting for.
    if (uncertain) {
      // Register the intent before the first recovery read. Readability alone
      // is not proof about this request; _settleUnresolved owns every unlock.
      setState(() {
        _unresolved.add(request.id);
        _unresolvedOwners[request.id] = current.requestedById;
      });
    }
    unawaited(_loadCounts());
    await _load(inPlace: true);
    if (!mounted || !_owns(client)) return;
    if (!uncertain) setState(() => _busy.remove(request.id));
    if (failure != null) {
      showErrorSnackBar(context, failure);
    } else {
      showSuccessSnackBar(context, success);
    }
  }

  /// Reads the list again for a request whose state is open. The only thing a
  /// locked request offers.
  void _resolve() {
    unawaited(_loadCounts());
    unawaited(_load(inPlace: true));
  }

  void _approve(SeerrRequest request) => unawaited(
    _runAction(
      request,
      _boundClient,
      (rights) => rights.canApprove,
      (c) => c.approveRequest(request.id),
      success: t.seerr.approved,
    ),
  );

  void _decline(SeerrRequest request) => unawaited(
    _runAction(
      request,
      _boundClient,
      (rights) => rights.canDecline,
      (c) => c.declineRequest(request.id),
      success: t.seerr.declined,
    ),
  );

  Future<void> _cancel(SeerrRequest request, {SeerrClient? origin}) async {
    // The account the question is asked under. The answer may come after a
    // profile switch, and then it is an answer about someone else's list.
    final client = origin ?? _boundClient;
    if (!_owns(client) || _busy.contains(request.id)) return;
    final confirmed = await showConfirmDialog(
      context,
      title: t.seerr.cancelRequest,
      message: t.seerr.cancelRequestConfirm,
      confirmText: t.seerr.cancelRequest,
      cancelText: t.common.cancel,
      isDestructive: true,
    );
    if (!confirmed || !_owns(client)) return;
    await _runAction(
      request,
      client,
      (rights) => rights.canCancel,
      (c) => c.deleteRequest(request.id),
      success: t.seerr.requestCancelled,
    );
  }

  Future<void> _edit(SeerrRequest request, {SeerrClient? origin}) async {
    final client = origin ?? _boundClient;
    if (!_owns(client) || _busy.contains(request.id)) return;
    final saved = await SeerrRequestEditSheet.show(context, request: request);
    if (!_owns(client)) return;
    // Also after a close without a save: the sheet read the request back, and
    // what it found (approved meanwhile, refused) is news for the list too.
    unawaited(_loadCounts());
    unawaited(_load(inPlace: true));
    if (saved == true) showSuccessSnackBar(context, t.seerr.editSaved);
  }

  /// The menu behind a request: the TV card's context menu and the row's
  /// "more" button.
  Future<void> _openActions(SeerrRequest request) async {
    final client = _boundClient;
    if (!_owns(client)) return;
    if (_unresolved.contains(request.id)) return _resolve();
    if (_busy.contains(request.id)) return;
    final action = await showSeerrRequestActionsSheet(
      context,
      request: request,
      rights: _rightsFor(request),
      isOwn: _isOwn(request),
    );
    // A choice made in a menu that was opened under another account is dropped.
    if (action == null || !_owns(client)) return;
    switch (action) {
      case SeerrRequestAction.open:
        _openDetail(request);
      case SeerrRequestAction.approve:
        _approve(request);
      case SeerrRequestAction.decline:
        _decline(request);
      case SeerrRequestAction.edit:
        await _edit(request, origin: client);
      case SeerrRequestAction.cancel:
        await _cancel(request, origin: client);
    }
  }

  /// Why the chosen status shows no list: the route has no such filter, or the
  /// server answered one it does have with other rows.
  String get _unsupportedBody =>
      _filter == TvSeerrRequestFilter.declined ? t.seerr.filterUnsupportedBySource : t.seerr.filterUnsupportedBody;

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
    final ownOnly = _ownOnly(provider);
    final title = ownOnly ? t.seerr.myRequests : t.seerr.allRequests;

    // Host so the action menu and the edit form get the overlay path (focus
    // trap, D-pad back) instead of the focusless modal-route fallback.
    return OverlaySheetHost(
      child: PlatformDetector.isTV()
          ? _buildTv(title, ownOnly)
          : FocusedScrollScaffold(
              title: Text(title),
              slivers: [
                if (provider.canManageRequests) SliverToBoxAdapter(child: _scopeRow(ownOnly)),
                SliverToBoxAdapter(child: _filterRow(ownOnly)),
                SliverToBoxAdapter(child: SeerrRequestsDiscoverBar(onOpen: _openDiscover)),
                ..._contentSlivers(),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
    );
  }

  /// Alle aanvragen on TV (DEC-108 (3) and (4), mockup 35 C1 and 35 D).
  ///
  /// The discover bar is gone here: on TV this page is reached *from* Ontdekken,
  /// so a row that offers to go back there is a loop, and the rail is where a
  /// catalog-language page keeps its controls.
  Widget _buildTv(String title, bool ownOnly) {
    return TvSeerrRequestsView(
      key: _tvKey,
      title: title,
      requests: _items,
      filter: _filter,
      onFilterChanged: _onFilter,
      onActivate: _openDetail,
      onContextMenu: (request) => unawaited(_openActions(request)),
      busyIds: _busy,
      unresolvedIds: _unresolved,
      isLoading: _loading,
      hasMore: _hasMore && !_loading,
      isLoadingMore: _loadingMore,
      loadMoreFailed: _loadMoreFailed,
      onLoadMore: () => unawaited(_load()),
      onReload: _reload,
      onDiscover: _openDiscover,
      countFor: _countFor,
      countsScope: ownOnly
          ? TvSeerrCountsScope.own
          : (_countsFailed ? TvSeerrCountsScope.failed : TvSeerrCountsScope.all),
      error: _ownScopeUnknown ? t.seerr.ownScopeUnknown : _error,
      filterUnsupported: _filterUnsupported,
      filterUnsupportedBody: _unsupportedBody,
      ownScope: ownOnly,
      // Only a manager has a second scope to choose. Without the callback the
      // rail has no Bereik row.
      onScopeChanged: context.read<SeerrProvider>().canManageRequests ? _setScope : null,
      initialFocusedId: _chosenId == null ? null : '$_chosenId',
      onExitTop: () => MainScreenFocusScope.of(context, listen: false)?.focusSidebar(),
    );
  }

  /// Select on a request card: the title it is about.
  ///
  /// Not the approve/decline actions the mobile row carries. On TV those go
  /// through the unified context menu (PB-5), which is the reasoning DEC-108
  /// used to choose the grid over the list in the first place — a card with
  /// buttons on it would be the exception rather than the rule.
  void _openDetail(SeerrRequest request) {
    final tmdbId = request.tmdbId;
    if (tmdbId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SeerrMediaDetailScreen(
          media: SeerrMedia(
            tmdbId: tmdbId,
            mediaType: request.mediaType,
            title: request.mediaTitle ?? '',
            year: request.mediaYear,
            posterPath: request.posterPath,
            backdropPath: request.backdropPath,
            status: request.mediaStatus,
          ),
          // Coming back from the title, the request it belongs to may have
          // moved on; the card under the focus follows.
          onStatusChanged: (_) => unawaited(_load(inPlace: true)),
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
      final context = _filterChipKeys[_filter.wire]?.currentContext;
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

  void _openDiscover() {
    SeerrDiscoverScreen.open(context);
  }
}
