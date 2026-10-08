part of 'seerr_request_sheet.dart';

/// What the form is made of, apart from what it does: the rows, the limit
/// line and the two end states.
extension _SeerrRequestSheetRows on _SeerrRequestSheetState {
  /// A form with nothing to fill in: one message and the way out.
  Widget _terminal(Widget notice, {bool offerMine = false}) {
    final mine = offerMine && widget.onOpenMyRequests != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        notice,
        SeerrFormButtons(
          closeLabel: t.common.close,
          onClose: _close,
          primaryLabel: mine ? t.seerr.myRequests : null,
          primaryIcon: Symbols.inbox_rounded,
          primaryInstance: 'mine',
          onPrimary: mine ? _openMyRequests : null,
        ),
      ],
    );
  }

  Widget _buildDone() {
    final seasons = (_sent?.seasons ?? _selectedSeasons).toList()..sort();
    final range = seerrSeasonRanges(seasons);
    final seasonsLine = !_isTv || seasons.isEmpty
        ? null
        : t.seerr.requestDoneSeasons(
            seasons: seasons.length == 1
                ? t.seerr.season(number: seasons.first)
                : (range == null ? t.seerr.seasonsCount(count: seasons.length) : t.seerr.seasonsRange(range: range)),
          );
    return _terminal(
      SeerrFormNotice(
        kind: 'done',
        title: t.seerr.requestSuccess,
        body: [?seasonsLine, t.seerr.requestDoneBody].join(' '),
      ),
      offerMine: true,
    );
  }

  /// The button names what it sends, so a partial selection is not a surprise.
  String get _submitLabel {
    if (_target.serversFailed || _target.detailFailed) return t.seerr.requestWithServerDefault;
    if (!_isTv) return t.seerr.requestMovie;
    final chosen = _selectedSeasons.length;
    if (chosen == 1) return t.seerr.requestSeason(number: _selectedSeasons.first);
    if (chosen > 1) return t.seerr.requestSeasons(count: chosen);
    return t.seerr.request;
  }

  Widget _quotaLine(ThemeData theme) {
    final q = _quotaForType;
    final limit = q.limit;
    final remaining = q.remaining;
    // Three different facts. No limit set is unlimited; a limit with what is
    // left is known; everything else, including a lookup that failed, is not.
    final text = _quota != null && (limit == null || limit == 0)
        ? t.seerr.quotaUnlimited
        : (limit != null && remaining != null
              ? t.seerr.quotaRemaining(remaining: '$remaining', limit: '$limit')
              : t.seerr.quotaUnknown);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: tokens(context).textMuted)),
    );
  }

  bool _canOffer4k(SeerrProvider provider) => provider.canRequest4kFor(isMovie: !_isTv);

  Widget _fourKRow(SeerrProvider provider, {required bool enabled}) {
    if (!_canOffer4k(provider)) {
      // The right is per media type, so the line says which one is missing
      // instead of leaving a gap where the switch is on the other type.
      return AutomationNode(
        id: AutomationIds.requestsFormOption,
        instance: 'fourK',
        role: 'list.item',
        state: () => const {'allowed': false},
        child: ListTile(
          dense: true,
          leading: const AppIcon(Symbols.lock_rounded, size: 20),
          title: Text(_isTv ? t.seerr.fourKNotAllowedShow : t.seerr.fourKNotAllowedMovie),
        ),
      );
    }
    return SeerrFocusNode(
      id: AutomationIds.requestsFormOption,
      instance: 'fourK',
      role: 'list.item',
      state: () => {'allowed': true, 'selected': _is4k},
      builder: (_, node) => FocusableListTile(
        focusNode: node,
        enabled: enabled,
        leading: const AppIcon(Symbols.high_quality_rounded, fill: 1),
        title: Text(t.seerr.fourK),
        subtitle: Text(_is4k ? t.seerr.qualityFourK : t.seerr.qualityHd),
        trailing: Switch(value: _is4k, onChanged: enabled ? _setIs4k : null),
        onTap: () => _setIs4k(!_is4k),
      ),
    );
  }

  List<Widget> _buildSeasonList(ThemeData theme, {required bool enabled}) {
    final requestable = _requestable;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(t.seerr.selectSeasons, style: theme.textTheme.titleSmall),
      ),
      if (requestable.length > 1)
        SeerrAllSeasonsTile(
          chosen: _selectedSeasons.length,
          total: requestable.length,
          onToggle: _toggleAll,
          enabled: enabled,
        ),
      for (final s in _seasons)
        SeerrSeasonTile(
          season: s,
          selected: _selectedSeasons.contains(s.seasonNumber),
          onToggle: () => _toggleSeason(s.seasonNumber),
          locked: _isSeasonRequestable(s)
              ? null
              : seerrSeasonLockLabel(s.statusFor(is4k: _is4k) ?? SeerrMediaStatus.unknown),
          enabled: enabled,
        ),
    ];
  }
}
