import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../automation/automation_ids.dart';
import '../automation/automation_node.dart';
import '../i18n/strings.g.dart';
import '../models/seerr/seerr_media.dart';
import '../models/seerr/seerr_request.dart';
import '../providers/seerr_provider.dart';
import '../services/seerr/seerr_client.dart';
import '../services/seerr/seerr_constants.dart';
import '../theme/mono_tokens.dart';
import '../utils/app_logger.dart';
import 'app_icon.dart';
import 'bottom_sheet_page_scaffold.dart';
import 'focusable_list_tile.dart';
import 'loading_indicator_box.dart';
import 'overlay_sheet.dart';
import 'seerr_request_form_parts.dart';
import 'seerr_request_target.dart';

part 'seerr_request_sheet_rows.dart';

/// Request a movie or show from the seerr server.
///
/// Movie = single confirm. TV = per-season multi-select (already
/// available/requested seasons shown with their status, not selectable). The
/// 4K switch shows when the user holds the 4K right for this media type, and a
/// line says so when they do not. Admins get the target section (server,
/// quality profile, root folder). Returns `true` from [show] when a request
/// was filed.
///
/// What it never does is send the same request twice on a guess. A connection
/// that drops after the POST leaves the outcome unknown, so the sheet reads the
/// title's status back before it offers Aanvragen again; a 403 or 409 is the
/// server's answer and is shown as one.
class SeerrRequestSheet extends StatefulWidget {
  final SeerrMedia media;

  /// Called the moment the server confirms the request, before the sheet is
  /// closed. A caller that shows a status reloads here, so backing out of the
  /// confirmation instead of pressing Sluiten still leaves it up to date.
  final VoidCallback? onRequested;

  /// Opens the viewer's own requests. The sheet closes first. Null hides the
  /// route, for a caller that has nowhere to send it.
  final VoidCallback? onOpenMyRequests;

  /// Opens the form on 4K, for a caller whose button said so. Ignored for a
  /// profile without the 4K right for this media type.
  final bool initialIs4k;

  const SeerrRequestSheet({
    super.key,
    required this.media,
    this.onRequested,
    this.onOpenMyRequests,
    this.initialIs4k = false,
  });

  static Future<bool?> show(
    BuildContext context, {
    required SeerrMedia media,
    VoidCallback? onRequested,
    VoidCallback? onOpenMyRequests,
    bool initialIs4k = false,
  }) {
    return OverlaySheetController.showAdaptive<bool>(
      context,
      isScrollControlled: true,
      builder: (_) => SeerrRequestSheet(
        media: media,
        onRequested: onRequested,
        onOpenMyRequests: onOpenMyRequests,
        initialIs4k: initialIs4k,
      ),
    );
  }

  @override
  State<SeerrRequestSheet> createState() => _SeerrRequestSheetState();
}

enum _Refusal { forbidden, duplicate }

class _SeerrRequestSheetState extends State<SeerrRequestSheet> {
  bool _loading = true;
  bool _submitting = false;
  bool _checking = false;
  bool _done = false;
  String? _error;

  /// The POST left without a readable answer. The form is locked on what was
  /// sent until a read of the title proves it arrived or proves it did not.
  bool _uncertain = false;

  /// What the last POST asked for, frozen when it was sent. The status check
  /// and the confirmation are about this, not about what the form shows later.
  ({bool is4k, Set<int> seasons})? _sent;

  /// The server said no. Cleared when a choice changes, because 4K and the
  /// season selection are both things a refusal can be about.
  _Refusal? _refusal;

  List<SeerrSeason> _seasons = const [];
  final Set<int> _selectedSeasons = {};
  bool _is4k = false;

  SeerrQuota? _quota;
  SeerrMediaStatus _status = SeerrMediaStatus.unknown;

  /// The title's 4K status, null while Seerr has not said what it is.
  SeerrMediaStatus? _status4k;
  late final SeerrTargetController _target = SeerrTargetController(isTv: _isTv);

  /// The client this sheet loaded with. A profile switch swaps it, and from
  /// then on nothing this sheet holds describes the active account.
  SeerrClient? _boundClient;
  bool _started = false;

  bool get _isTv => widget.media.mediaType == 'tv';

  SeerrClient? get _client {
    final current = context.read<SeerrProvider>().client;
    return identical(current, _boundClient) ? current : null;
  }

  /// Whether an answer that was asked through [client] still belongs here.
  bool _live(SeerrClient client) => mounted && identical(context.read<SeerrProvider>().client, client);

  bool get _locked => _submitting || _checking || _uncertain;

  @override
  void initState() {
    super.initState();
    _status = widget.media.status;
    _status4k = widget.media.status4k;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = Provider.of<SeerrProvider>(context).client;
    if (!_started) {
      _started = true;
      _boundClient = client;
      unawaited(_load());
      return;
    }
    if (identical(client, _boundClient)) return;
    // Another account is active. Quota, seasons, target and any request in
    // flight belong to the previous one, so the form goes away with no result
    // instead of confirming or reloading anything for the new account.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) OverlaySheetController.closeAdaptive(context);
    });
  }

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final provider = context.read<SeerrProvider>();
    final client = _client;
    if (client == null) {
      setState(() {
        _loading = false;
        _error = t.seerr.errorGeneric;
      });
      return;
    }
    if (!provider.canRequest) {
      setState(() => _loading = false);
      return;
    }
    _is4k = widget.initialIs4k && provider.canRequest4kFor(isMovie: !_isTv);
    try {
      if (_isTv) {
        final detail = await client.getTv(widget.media.tmdbId);
        if (!mounted || !_live(client)) return;
        _seasons = SeerrSeason.listFromDetail(detail);
        _selectAllRequestable();
      }
      // The limit is a line of context, not a condition for requesting: the
      // server enforces it either way, so a failed lookup reads as unknown.
      final userId = provider.session?.userId;
      if (userId != null) {
        SeerrQuota? quota;
        try {
          quota = await client.getQuota(userId);
        } catch (_) {
          quota = null;
        }
        if (!mounted || !_live(client)) return;
        _quota = quota;
      }
      if (provider.isAdmin) {
        await _target.load(client, is4k: _is4k);
        if (!mounted || !_live(client)) return;
      }
      setState(() => _loading = false);
    } on SeerrException catch (e) {
      if (!mounted || !_live(client)) return;
      setState(() {
        _loading = false;
        _error = _mapError(e);
      });
    } catch (_) {
      // Never leave the sheet stuck on the spinner: a non-Seerr error (e.g. an
      // unexpected detail-payload shape) still resolves to a visible message.
      if (!mounted || !_live(client)) return;
      setState(() {
        _loading = false;
        _error = t.seerr.errorGeneric;
      });
    }
  }

  /// Not pending, processing or available in the quality being requested.
  bool _isSeasonRequestable(SeerrSeason s) => s.requestableIn(is4k: _is4k);

  List<SeerrSeason> get _requestable => _seasons.where(_isSeasonRequestable).toList();

  void _selectAllRequestable() {
    _selectedSeasons
      ..clear()
      ..addAll(_requestable.map((s) => s.seasonNumber));
  }

  // Movies: block a duplicate request the server would reject with 409. HD and
  // 4K are separate requests, so each is judged on its own status. No 4K
  // status at all leaves 4K on offer, and the server decides.
  bool _isMovieRequestableIn({required bool is4k}) {
    final status = is4k ? _status4k : _status;
    return status == null || (!status.isAvailable && !status.isRequested);
  }

  bool get _isMovieRequestable => _isMovieRequestableIn(is4k: _is4k);

  /// A film whose chosen quality is already asked for, on a form that only
  /// stands for the other quality: the button that could not send anyway is
  /// the way to the request that exists, as it is on the end state.
  bool get _offersMineInsteadOfSubmit =>
      !_isTv &&
      !_locked &&
      _refusal == null &&
      widget.onOpenMyRequests != null &&
      ((_is4k ? _status4k : _status)?.isRequested ?? false);

  ({int? remaining, int? limit}) get _quotaForType {
    final q = _quota;
    if (q == null) return (remaining: null, limit: null);
    return _isTv ? (remaining: q.tvRemaining, limit: q.tvLimit) : (remaining: q.movieRemaining, limit: q.movieLimit);
  }

  /// The server reports a limit and says none of it is left. A limit without a
  /// remaining figure is not this: that is unknown, and unknown does not block.
  bool get _quotaExhausted {
    final q = _quotaForType;
    final limit = q.limit;
    final remaining = q.remaining;
    return limit != null && limit > 0 && remaining != null && remaining <= 0;
  }

  bool get _canSubmit =>
      !_locked &&
      _refusal == null &&
      widget.media.tmdbId > 0 &&
      !_quotaExhausted &&
      !_target.missingServerForQuality &&
      !_target.detailLoading &&
      (_isTv ? _selectedSeasons.isNotEmpty : _isMovieRequestable);

  String _mapError(SeerrException e) {
    if (e.isForbidden) return t.seerr.errorForbidden;
    if (e.isNetwork) return t.seerr.errorNetwork;
    return t.seerr.errorGeneric;
  }

  void _close([bool? result]) => OverlaySheetController.closeAdaptive(context, result ?? (_done ? true : null));

  void _openMyRequests() {
    final open = widget.onOpenMyRequests;
    _close();
    open?.call();
  }

  Future<void> _submit() async {
    final client = _client;
    if (client == null || !_canSubmit) return;
    final sent = (is4k: _is4k, seasons: _isTv ? _selectedSeasons.toSet() : const <int>{});
    final target = _target.target;
    setState(() {
      _submitting = true;
      _sent = sent;
      _error = null;
    });
    try {
      await client.createRequest(
        mediaType: widget.media.mediaType,
        tmdbId: widget.media.tmdbId,
        seasons: _isTv ? (sent.seasons.toList()..sort()) : null,
        is4k: sent.is4k,
        serverId: target?.serverId,
        profileId: target?.profileId,
        rootFolder: target?.rootFolder,
      );
      if (!mounted || !_live(client)) return;
    } on SeerrException catch (e) {
      if (!mounted || !_live(client)) return;
      setState(() {
        _submitting = false;
        if (e.outcomeUnknown) {
          _uncertain = true;
        } else if (e.isForbidden || e.isAuth) {
          _refusal = _Refusal.forbidden;
        } else if (e.isConflict) {
          _refusal = _Refusal.duplicate;
        } else {
          _error = e.message.startsWith('HTTP') ? t.seerr.requestFailed : e.message;
        }
      });
      return;
    } catch (_) {
      // Something broke after the request left. That is not proof it failed.
      if (!mounted || !_live(client)) return;
      setState(() {
        _submitting = false;
        _uncertain = true;
      });
      return;
    }
    // Outside the try: the server has confirmed, and a caller whose callback
    // throws must not turn that into an open outcome.
    _confirm();
  }

  void _confirm() {
    setState(() {
      _submitting = false;
      _checking = false;
      _uncertain = false;
      _done = true;
    });
    // The request is confirmed whatever the caller does with the news.
    try {
      widget.onRequested?.call();
    } catch (e, stack) {
      appLogger.w('Seerr request confirmed, but the onRequested callback threw', error: e, stackTrace: stack);
    }
  }

  /// Reads the title back after a request whose outcome is unknown.
  ///
  /// Only positive proof counts as arrived: Seerr lists a live request in the
  /// quality that was sent, by this user where the user is known, holding
  /// every season that was sent. A title that merely stopped being requestable
  /// proves nothing (someone else's request, or the HD copy, does that too),
  /// and neither does an answer without a request list. Then the form stays
  /// locked, because sending again could be a second request.
  Future<void> _checkStatus() async {
    final client = _client;
    final sent = _sent;
    if (client == null || sent == null || _checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    final SeerrMediaDetail detail;
    final List<SeerrSeason> seasons;
    try {
      final json = _isTv ? await client.getTv(widget.media.tmdbId) : await client.getMovie(widget.media.tmdbId);
      detail = SeerrMediaDetail.fromJson(json, mediaType: widget.media.mediaType);
      seasons = _isTv ? SeerrSeason.listFromDetail(json) : const [];
    } catch (_) {
      if (!mounted || !_live(client)) return;
      return _stayUncertain(t.seerr.statusCheckFailed);
    }
    if (!mounted || !_live(client)) return;
    if (detail.media.tmdbId != widget.media.tmdbId || !detail.requestsKnown) {
      return _stayUncertain(t.seerr.statusNotProven);
    }

    // A listed request that does not say its status, its quality, whose it is
    // or (for a series) its seasons could be the one that was sent, or not.
    // It can neither confirm nor rule out, so the outcome stays open.
    if (detail.requests.any((r) => !r.isReliableReadback)) return _stayUncertain(t.seerr.statusNotProven);

    final ownId = context.read<SeerrProvider>().session?.userId;
    final live = detail.requests.where(
      (r) =>
          r.is4k == sent.is4k &&
          r.status != SeerrRequestStatus.declined &&
          r.status != SeerrRequestStatus.failed &&
          (ownId == null || r.requestedById == ownId),
    );
    final arrived = _isTv
        ? sent.seasons.isNotEmpty && live.expand((r) => r.seasons).toSet().containsAll(sent.seasons)
        : live.isNotEmpty;
    if (arrived) return _confirm();

    // The server answered with its full request list and this one is not on
    // it. That is proof too, of the other outcome, and sending is back.
    setState(() {
      _checking = false;
      _uncertain = false;
      _sent = null;
      _status = detail.media.status;
      _status4k = detail.media.status4k;
      if (_isTv) {
        _seasons = seasons;
        _selectedSeasons.removeWhere((n) => !_requestable.any((s) => s.seasonNumber == n));
      }
      _error = t.seerr.requestStillAbsent;
    });
  }

  void _stayUncertain(String message) => setState(() {
    _checking = false;
    _uncertain = true;
    _error = message;
  });

  void _changed(VoidCallback change) {
    if (_locked) return;
    setState(() {
      change();
      _refusal = null;
      _error = null;
    });
  }

  /// Flip the 4K request and re-point the target at an instance of that kind.
  ///
  /// 4K lives on its own Radarr/Sonarr instance, so the flag and the server are
  /// one choice, not two. Which seasons can still be asked for depends on the
  /// quality as well, so the selection starts over.
  void _setIs4k(bool value) {
    if (_is4k == value || _locked) return;
    _changed(() {
      _is4k = value;
      if (_isTv) _selectAllRequestable();
    });
    _target.setIs4k(value);
  }

  void _toggleSeason(int n) => _changed(() {
    if (!_selectedSeasons.remove(n)) _selectedSeasons.add(n);
  });

  void _toggleAll() => _changed(() {
    final requestable = _requestable;
    if (_selectedSeasons.length == requestable.length) {
      _selectedSeasons.clear();
    } else {
      _selectAllRequestable();
    }
  });

  String _phase(SeerrProvider provider) {
    if (_loading) return 'loading';
    if (_done) return 'done';
    if (!provider.canRequest) return 'forbidden';
    if (_submitting) return 'submitting';
    if (_checking) return 'checking';
    if (_uncertain) return 'uncertain';
    if (_refusal != null) return 'refused';
    return 'form';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SeerrProvider>();
    return AutomationNode(
      id: AutomationIds.requestsForm,
      instance: 'create',
      role: 'dialog',
      label: widget.media.title,
      state: () => {
        'phase': _phase(provider),
        'is4k': _is4k,
        'seasons': _selectedSeasons.toList()..sort(),
        'canSubmit': _canSubmit,
      },
      child: BottomSheetPageScaffold(
        title: widget.media.title,
        icon: Symbols.playlist_add_rounded,
        shrinkWrap: true,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: LoadingIndicatorBox()),
              )
            : ListenableBuilder(listenable: _target, builder: (context, _) => _buildBody(context, provider)),
      ),
    );
  }

  Widget _buildBody(BuildContext context, SeerrProvider provider) {
    if (_done) return _buildDone();
    if (!provider.canRequest) {
      return _terminal(
        SeerrFormNotice(kind: 'forbidden', title: t.seerr.noRequestRight, tone: SeerrFormNoticeTone.warning),
      );
    }
    // Nothing requestable (already available/requested): show a clear message
    // instead of a dead-end sheet with a permanently disabled button.
    final nothingRequestable = _isTv
        ? !_seasons.any(_isSeasonRequestable) && !_canOffer4k(provider)
        : !_isMovieRequestableIn(is4k: false) && !(_canOffer4k(provider) && _isMovieRequestableIn(is4k: true));
    if (nothingRequestable && _error == null) {
      final available = _status.isAvailable;
      return _terminal(
        SeerrFormNotice(kind: 'duplicate', title: available ? t.seerr.available : t.seerr.alreadyRequested),
        offerMine: !available,
      );
    }

    final theme = Theme.of(context);
    // Cap the sheet so a long season list (20+ seasons) scrolls inside the sheet
    // instead of pushing the Request button off-screen. The messages and the
    // buttons stay pinned below the scroll area so they're always reachable.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
    final locked = _locked;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                _quotaLine(theme),
                if (_isTv) ..._buildSeasonList(theme, enabled: !locked),
                _fourKRow(provider, enabled: !locked),
                if (provider.isAdmin && (_target.hasAnyServer || _target.serversFailed))
                  SeerrTargetSection(controller: _target, enabled: !locked),
              ],
            ),
          ),
          if (_quotaExhausted)
            SeerrFormNotice(kind: 'quota', title: t.seerr.quotaReached, tone: SeerrFormNoticeTone.warning),
          // A film whose chosen quality is taken while the other one is open:
          // the form stays for the 4K switch, and says why it cannot send yet.
          if (!_isTv && !_isMovieRequestable && _refusal == null && !_uncertain)
            SeerrFormNotice(
              kind: 'duplicate',
              title: (_is4k ? _status4k : _status)?.isAvailable ?? false ? t.seerr.available : t.seerr.alreadyRequested,
            ),
          if (_uncertain)
            SeerrFormNotice(
              kind: 'uncertain',
              title: t.seerr.requestUncertainTitle,
              body: t.seerr.requestUncertainBody,
              tone: SeerrFormNoticeTone.warning,
            ),
          if (_refusal case final refusal?)
            SeerrFormNotice(
              kind: 'refused',
              title: t.seerr.requestRefusedTitle,
              body: refusal == _Refusal.duplicate ? t.seerr.requestRefusedDuplicate : t.seerr.requestRefusedForbidden,
              tone: SeerrFormNoticeTone.error,
            ),
          if (_error case final error?) SeerrFormNotice(kind: 'error', title: error, tone: SeerrFormNoticeTone.error),
          _uncertain
              ? SeerrFormButtons(
                  closeLabel: t.common.close,
                  onClose: _close,
                  primaryLabel: t.seerr.checkStatus,
                  primaryIcon: Symbols.refresh_rounded,
                  primaryInstance: 'status',
                  onPrimary: _checkStatus,
                  busy: _checking,
                )
              : _offersMineInsteadOfSubmit
              ? SeerrFormButtons(
                  closeLabel: t.common.close,
                  onClose: _close,
                  primaryLabel: t.seerr.myRequests,
                  primaryIcon: Symbols.inbox_rounded,
                  primaryInstance: 'mine',
                  onPrimary: _openMyRequests,
                )
              : SeerrFormButtons(
                  closeLabel: t.common.cancel,
                  onClose: _close,
                  primaryLabel: _submitLabel,
                  primaryIcon: Symbols.download_rounded,
                  onPrimary: _canSubmit || _submitting ? _submit : null,
                  busy: _submitting,
                ),
        ],
      ),
    );
  }
}
