import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
import '../services/seerr/seerr_request_rights.dart';
import 'app_icon.dart';
import 'bottom_sheet_page_scaffold.dart';
import 'loading_indicator_box.dart';
import 'overlay_sheet.dart';
import 'seerr_request_form_parts.dart';
import 'seerr_request_target.dart';

/// Change a request that is still pending.
///
/// What can change follows Seerr's own `PUT /request/{id}`: the seasons of a
/// series, and for an admin the Radarr/Sonarr target. The quality cannot: the
/// route never reads `is4k`, so the row is shown as a fact with the way around
/// it, and nothing here sends or claims a quality change.
///
/// The sheet reads the request back from the server before it shows anything.
/// The route assigns the target fields from the body whether they are there or
/// not, so an edit has to carry the ones the request holds *now*, and a list
/// row may be a page load old.
class SeerrRequestEditSheet extends StatefulWidget {
  const SeerrRequestEditSheet({super.key, required this.request});

  /// The row the edit was opened from. Used for the title and the id only.
  final SeerrRequest request;

  /// Returns true when the server confirmed a change.
  static Future<bool?> show(BuildContext context, {required SeerrRequest request}) {
    return OverlaySheetController.showAdaptive<bool>(
      context,
      isScrollControlled: true,
      restoreLauncherFocus: true,
      builder: (_) => SeerrRequestEditSheet(request: request),
    );
  }

  @override
  State<SeerrRequestEditSheet> createState() => _SeerrRequestEditSheetState();
}

enum _Blocked { notPending, nothingToEdit, forbidden, loadFailed }

/// What one save asked the server for, frozen when it was sent. Everything
/// that later decides "did it land" is compared against this, never against
/// what the form shows by then.
class _SentEdit {
  const _SentEdit({required this.mediaType, required this.is4k, required this.seasons, required this.target});

  final String mediaType;
  final bool is4k;

  /// Null for a request without seasons to edit.
  final Set<int>? seasons;

  /// The target the request should hold afterwards: the edited one, or the
  /// stored one that was passed back.
  final SeerrRequestTarget target;

  /// Positive proof only: the same request, in the same quality, holding
  /// exactly these seasons and this target.
  bool landedIn(SeerrRequest now, {required int id}) =>
      now.id == id &&
      now.mediaType == mediaType &&
      now.is4k == is4k &&
      (seasons == null || setEquals(seasons, now.seasons.toSet())) &&
      now.serverId == target.serverId &&
      now.profileId == target.profileId &&
      now.rootFolder == target.rootFolder;
}

class _SeerrRequestEditSheetState extends State<SeerrRequestEditSheet> {
  bool _loading = true;
  bool _saving = false;
  bool _checking = false;

  /// A save left without proof of its outcome. The form is locked on what was
  /// sent until a read of the request settles it.
  bool _uncertain = false;
  _SentEdit? _sent;
  _Blocked? _blocked;
  String? _error;

  /// The request as the server last reported it.
  SeerrRequest? _fresh;
  SeerrRequestRights? _rights;
  List<SeerrSeason> _seasons = const [];
  final Set<int> _selected = {};

  late final SeerrTargetController _target = SeerrTargetController(isTv: _isTv);

  /// The client this sheet was opened with. Every send goes through it and
  /// every answer is checked against it: a request id means something else on
  /// another account.
  SeerrClient? _boundClient;
  bool _started = false;

  bool get _isTv => widget.request.mediaType == 'tv';

  SeerrClient? get _client {
    final current = context.read<SeerrProvider>().client;
    return identical(current, _boundClient) ? current : null;
  }

  /// Whether an answer that was asked through [client] still belongs here.
  bool _live(SeerrClient client) => mounted && identical(context.read<SeerrProvider>().client, client);

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
    // Another account is active. This form is about a request of the previous
    // one, so it goes away without a result rather than waiting to be used.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _close();
    });
  }

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  SeerrRequestRights _rightsFor(SeerrRequest request) {
    final provider = context.read<SeerrProvider>();
    return SeerrRequestRights.of(
      request,
      ownUserId: provider.session?.userId,
      canManage: provider.canManageRequests,
      isAdmin: provider.isAdmin,
    );
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) {
      setState(() {
        _loading = false;
        _blocked = _Blocked.loadFailed;
      });
      return;
    }
    setState(() {
      _loading = true;
      _blocked = null;
      _error = null;
    });
    try {
      final fresh = await client.getRequest(widget.request.id);
      if (!mounted || !_live(client)) return;
      // The form is built on this answer and every save passes its target
      // back, so it has to be the whole request: an answer that leaves out the
      // status, the quality or the target keys would have the next save write
      // "nothing" over what the server holds.
      if (fresh == null ||
          fresh.id != widget.request.id ||
          fresh.mediaType != widget.request.mediaType ||
          !fresh.isReliableReadback ||
          !fresh.targetKnown ||
          !fresh.advancedKnown) {
        throw const SeerrException('unreadable request');
      }
      final rights = _rightsFor(fresh);
      _fresh = fresh;
      _rights = rights;
      if (!fresh.isPending) return _block(_Blocked.notPending);
      if (!rights.canEdit) return _block(_Blocked.nothingToEdit);

      if (rights.canEditSeasons) {
        final tmdbId = fresh.tmdbId ?? widget.request.tmdbId;
        if (tmdbId == null) throw const SeerrException('request without a title id');
        final detail = await client.getTv(tmdbId);
        if (!mounted || !_live(client)) return;
        _seasons = SeerrSeason.listFromDetail(detail);
        _selected
          ..clear()
          ..addAll(fresh.seasons);
      }
      if (rights.canEditTarget) {
        await _target.load(
          client,
          is4k: fresh.is4k,
          initial: _storedTarget(fresh),
          // The request already has a target. Options that come back short
          // must not swap it for a default behind the admin's back.
          keepStored: true,
        );
        if (!mounted || !_live(client)) return;
      }
      setState(() => _loading = false);
    } on SeerrException catch (e) {
      if (!mounted || !_live(client)) return;
      _block(e.isForbidden ? _Blocked.forbidden : _Blocked.loadFailed);
    } catch (_) {
      if (!mounted || !_live(client)) return;
      _block(_Blocked.loadFailed);
    }
  }

  static SeerrRequestTarget _storedTarget(SeerrRequest request) =>
      (serverId: request.serverId, profileId: request.profileId, rootFolder: request.rootFolder);

  void _block(_Blocked reason) => setState(() {
    _loading = false;
    _saving = false;
    _checking = false;
    _uncertain = false;
    _sent = null;
    _blocked = reason;
  });

  /// A season can be chosen when this request already holds it, or when
  /// nothing says someone has it in this request's quality.
  bool _selectable(SeerrSeason s) =>
      (_fresh?.seasons.contains(s.seasonNumber) ?? false) || s.requestableIn(is4k: _fresh?.is4k ?? false);

  List<int> get _chosen => _selected.toList()..sort();

  bool get _seasonsChanged => !setEquals(_selected, _fresh?.seasons.toSet() ?? const <int>{});

  bool get _editsTarget => (_rights?.canEditTarget ?? false) && _target.edited;

  /// The target to send, or null to pass the request's own back untouched.
  ///
  /// Only a target the admin actually changed here is sent. Whatever the
  /// option lists filled in or left out on their own is not an edit.
  SeerrRequestTarget? get _targetToSend => _editsTarget ? _target.target : null;

  bool get _targetChanged {
    final target = _targetToSend;
    final fresh = _fresh;
    if (target == null || fresh == null) return false;
    return target.serverId != fresh.serverId ||
        target.profileId != fresh.profileId ||
        target.rootFolder != fresh.rootFolder;
  }

  bool get _editsSeasons => _rights?.canEditSeasons ?? false;

  bool get _locked => _saving || _checking || _uncertain;

  bool get _canSave =>
      !_locked &&
      !_target.detailLoading &&
      // A server was picked whose options are not known: saving now would
      // quietly leave the old target in place.
      !(_editsTarget && _target.target == null) &&
      (!_editsSeasons || _selected.isNotEmpty) &&
      (_seasonsChanged || _targetChanged);

  void _close([bool? result]) => OverlaySheetController.closeAdaptive(context, result);

  Future<void> _save() async {
    final client = _client;
    final fresh = _fresh;
    if (client == null || fresh == null || !_canSave) return;
    final target = _targetToSend;
    final sent = _SentEdit(
      mediaType: fresh.mediaType,
      is4k: fresh.is4k,
      seasons: _editsSeasons ? _selected.toSet() : null,
      target: target ?? _storedTarget(fresh),
    );
    setState(() {
      _saving = true;
      _sent = sent;
      _error = null;
    });
    final bool answeredSaved;
    try {
      answeredSaved = await client.updateRequest(fresh, seasons: sent.seasons?.toList(), target: target);
    } on SeerrException catch (e) {
      if (!mounted || !_live(client)) return;
      if (e.isForbidden || e.isAuth) return _block(_Blocked.forbidden);
      if (e.isConflict) return _block(_Blocked.notPending);
      setState(() {
        _saving = false;
        if (e.outcomeUnknown) {
          _uncertain = true;
        } else {
          // The server answered with an error: nothing was stored.
          _sent = null;
          _error = t.seerr.errorGeneric;
        }
      });
      return;
    } catch (_) {
      if (!mounted || !_live(client)) return;
      setState(() {
        _saving = false;
        _uncertain = true;
      });
      return;
    }
    if (!mounted || !_live(client)) return;
    // A 2xx is an accepted call, not a stored change: the route can keep fewer
    // seasons than it was sent and still answer 200. What it stored is read.
    await _readBack(client, sent, notLanded: answeredSaved ? t.seerr.editNotAllSaved : t.seerr.editNothingSaved);
  }

  /// Reads the request and compares it with [sent]. Closes as saved on proof,
  /// re-opens the form when the server reliably holds something else, and
  /// stays locked when the read itself fails.
  Future<void> _readBack(SeerrClient client, _SentEdit sent, {required String notLanded}) async {
    final SeerrRequest? now;
    try {
      now = await client.getRequest(widget.request.id);
    } on SeerrException catch (e) {
      if (!mounted || !_live(client)) return;
      if (e.isForbidden) return _block(_Blocked.forbidden);
      return _stayUncertain();
    } catch (_) {
      if (!mounted || !_live(client)) return;
      return _stayUncertain();
    }
    if (!mounted || !_live(client)) return;
    // Half a request proves neither outcome, and must not replace the stored
    // one the form echoes its target from.
    if (now == null ||
        now.id != widget.request.id ||
        !now.isReliableReadback ||
        !now.targetKnown ||
        !now.advancedKnown) {
      return _stayUncertain();
    }
    if (sent.landedIn(now, id: widget.request.id)) return _close(true);
    _fresh = now;
    _rights = _rightsFor(now);
    if (!now.isPending) return _block(_Blocked.notPending);
    setState(() {
      _saving = false;
      _checking = false;
      _uncertain = false;
      _sent = null;
      _error = notLanded;
    });
  }

  void _stayUncertain() => setState(() {
    _saving = false;
    _checking = false;
    _uncertain = true;
    _error = t.seerr.statusCheckFailed;
  });

  /// Reads the request back after a save whose outcome is unknown, and only
  /// then decides whether saving again is on offer.
  Future<void> _checkStatus() async {
    final client = _client;
    final sent = _sent;
    if (client == null || sent == null || _checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    await _readBack(client, sent, notLanded: t.seerr.editStillOld);
  }

  void _toggle(int season) {
    if (_locked) return;
    setState(() {
      if (!_selected.remove(season)) _selected.add(season);
      _error = null;
    });
  }

  void _toggleAll() {
    if (_locked) return;
    final selectable = _seasons.where(_selectable).map((s) => s.seasonNumber).toSet();
    setState(() {
      if (_selected.length == selectable.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(selectable);
      }
      _error = null;
    });
  }

  String get _phase {
    if (_loading) return 'loading';
    if (_blocked case final blocked?) return blocked.name;
    if (_saving) return 'saving';
    if (_checking) return 'checking';
    if (_uncertain) return 'uncertain';
    return 'form';
  }

  @override
  Widget build(BuildContext context) {
    return AutomationNode(
      id: AutomationIds.requestsForm,
      instance: 'edit',
      role: 'dialog',
      label: widget.request.mediaTitle,
      state: () => {'phase': _phase, 'seasons': _chosen, 'canSubmit': _canSave, 'is4k': _fresh?.is4k},
      child: BottomSheetPageScaffold(
        title: widget.request.mediaTitle ?? t.seerr.editRequest,
        icon: Symbols.edit_rounded,
        shrinkWrap: true,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: LoadingIndicatorBox()),
              )
            : ListenableBuilder(listenable: _target, builder: (context, _) => _buildBody(context)),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_blocked case final blocked?) return _buildBlocked(blocked);

    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
    final locked = _locked;
    final fresh = _fresh!;
    final keepOne = _editsSeasons && _selected.isEmpty ? t.seerr.editKeepOneSeason : null;
    return LayoutBuilder(
      builder: (context, sheet) {
        // The reason stays beside the button, as it always was, until that line
        // is what overflows the form on a short screen with very large text;
        // then it is the first message of the list instead.
        final room = math.min(maxHeight, sheet.maxHeight);
        final keepOneInList =
            keepOne != null &&
            SeerrFormButtons.hintLinesFor(
                  room,
                  MediaQuery.textScalerOf(context),
                  noLine: _noHintRoom,
                  enlargedNoLine: 0,
                ) ==
                0;
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
                    if (keepOneInList) SeerrFormNotice(kind: 'keepOne', title: keepOne),
                    if (_editsSeasons) ..._seasonRows(theme, enabled: !locked),
                    AutomationNode(
                      id: AutomationIds.requestsFormOption,
                      instance: 'fourK',
                      role: 'list.item',
                      state: () => {'editable': false, 'selected': fresh.is4k},
                      child: ListTile(
                        dense: true,
                        leading: const AppIcon(Symbols.lock_rounded, size: 20),
                        title: Text(fresh.is4k ? t.seerr.qualityFourK : t.seerr.qualityHd),
                        subtitle: Text(t.seerr.editQualityFixed),
                      ),
                    ),
                    if ((_rights?.canEditTarget ?? false) && (_target.hasAnyServer || _target.serversFailed))
                      SeerrTargetSection(controller: _target, enabled: !locked, initiallyOpen: !_editsSeasons),
                  ],
                ),
              ),
              if (_uncertain)
                SeerrFormNotice(
                  kind: 'uncertain',
                  title: t.seerr.editUncertainTitle,
                  body: t.seerr.editUncertainBody,
                  tone: SeerrFormNoticeTone.warning,
                ),
              if (_error case final error?)
                SeerrFormNotice(kind: 'error', title: error, tone: SeerrFormNoticeTone.error),
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
                  : SeerrFormButtons(
                      closeLabel: t.common.cancel,
                      onClose: _close,
                      primaryLabel: _saving ? t.seerr.saving : t.seerr.saveChange,
                      onPrimary: _canSave || _saving ? _save : null,
                      busy: _saving,
                      hint: keepOneInList ? null : keepOne,
                    ),
            ],
          ),
        );
      },
    );
  }

  /// The form height per text size below which the reason leaves the buttons.
  /// Measured on the form as it was: 568x320 fits down to 2.0 (115) and
  /// overflows at 2.35 (98), 667x375 fits at 2.35 (115).
  static const double _noHintRoom = 105;

  List<Widget> _seasonRows(ThemeData theme, {required bool enabled}) {
    final selectable = _seasons.where(_selectable).toList();
    return [
      if (selectable.length > 1)
        SeerrAllSeasonsTile(chosen: _selected.length, total: selectable.length, onToggle: _toggleAll, enabled: enabled),
      for (final s in _seasons)
        SeerrSeasonTile(
          season: s,
          selected: _selected.contains(s.seasonNumber),
          onToggle: () => _toggle(s.seasonNumber),
          locked: _selectable(s)
              ? null
              : seerrSeasonLockLabel(s.statusFor(is4k: _fresh?.is4k ?? false) ?? SeerrMediaStatus.unknown),
          enabled: enabled,
        ),
    ];
  }

  Widget _buildBlocked(_Blocked blocked) {
    final (kind, title, body, tone) = switch (blocked) {
      _Blocked.notPending => (
        'unsupported',
        t.seerr.editNotPendingTitle,
        t.seerr.editNotPendingBody,
        SeerrFormNoticeTone.info,
      ),
      _Blocked.nothingToEdit => (
        'unsupported',
        t.seerr.editNotPendingTitle,
        t.seerr.editNothingToEdit,
        SeerrFormNoticeTone.info,
      ),
      _Blocked.forbidden => (
        'forbidden',
        t.seerr.editForbiddenTitle,
        t.seerr.editForbiddenBody,
        SeerrFormNoticeTone.error,
      ),
      _Blocked.loadFailed => ('error', t.seerr.editLoadFailed, null, SeerrFormNoticeTone.error),
    };
    final retry = blocked == _Blocked.loadFailed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SeerrFormNotice(kind: kind, title: title, body: body, tone: tone),
        SeerrFormButtons(
          closeLabel: t.common.close,
          onClose: _close,
          primaryLabel: retry ? t.common.retry : null,
          primaryIcon: Symbols.refresh_rounded,
          primaryInstance: 'retry',
          onPrimary: retry ? () => unawaited(_load()) : null,
        ),
      ],
    );
  }
}
