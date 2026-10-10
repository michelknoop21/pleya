part of 'assistant_run.dart';

// The closing answer: cards for the titles it names, and in kids mode the
// age gate on them. A title the gate turned down never gets a card, and the
// model gets one correction round that Pleya itself words.

/// Tool errors that are no failure of the task.
const _kidsCodes = {'kids_ages_unknown', 'kids_mode_unsupported'};

extension _AssistantAnswer on AssistantRun {
  /// A children's profile without saved ages, while no title tool has read
  /// them yet.
  Future<bool> _kidsAgesMissing() async =>
      _ctx.kidsMode && _ctx.kidsAge == null && (await _ctx.kidsAges?.call() ?? const <int>[]).isEmpty;

  /// The ages card, once per ask.
  void _askKidsAges() {
    if (!_displays.any((d) => d is AssistantKidsAgesPrompt)) _displays.add(AssistantKidsAgesPrompt(_prompt));
  }

  /// Settles [answer]: returns the correction for the model when it names a
  /// title the age filter did not pass and [mayCorrect]; otherwise adds the
  /// cards for its titles and returns null. Still naming one after the
  /// correction round sets [_ageNotice]: Pleya's own line replaces the
  /// model's text and the named titles get no card.
  Future<String?> _settleAnswer(String answer, {required bool mayCorrect}) async {
    final step = await _lookupNamedTitles(answer);
    final rejected = _rejectedNamed(answer);
    final unvetted = _unvettedNamed(answer, rejected);
    final clean = rejected.isEmpty && unvetted.isEmpty;
    if (clean && step?.display != null) _displays.add(step!.display!);
    if (step != null) {
      onStep?.call(
        AssistantStep(
          index: step.index,
          tool: 'find_title',
          phase: AssistantStepPhase.done,
          display: clean ? step.display : null,
          evidenceCurrent: step.current,
        ),
      );
    }
    if (clean) return null;
    if (!mayCorrect) {
      _ageNotice = true;
      return null;
    }
    return [
      if (rejected.isNotEmpty)
        'Not suitable for the youngest child (${_ctx.kidsAge} years): '
            '${[for (final r in rejected) '«${r.title}» (${r.reason})'].join(', ')}.',
      if (unvetted.isNotEmpty) 'Not checked by the age filter: ${unvetted.join(', ')}.',
      'Name only titles from tool results that passed the age filter, or say that none fits.',
    ].join(' ');
  }

  /// In kids mode, the titles the answer names that the age gate did not let
  /// through this ask, as quoted for the correction. Only a title in « » or
  /// one followed by a year counts, so ordinary prose is left alone. The
  /// [rejected] ones are already reported.
  List<String> _unvettedNamed(String answer, List<({String title, int? year, String reason})> rejected) {
    if (!_ctx.kidsMode) return const [];
    final allowed = [for (final a in _ctx.ageAllowed) (key: assistantTitleKey(a.title), year: a.year)];
    final skip = {for (final r in rejected) assistantTitleKey(r.title)};
    final found = <String>[];
    void check(String title, String key, int? year, {required bool suffix}) {
      if (key.isEmpty || skip.contains(key) || found.contains(title)) return;
      final ok = allowed.any(
        (a) =>
            a.key.isNotEmpty &&
            (suffix ? key.endsWith(a.key) : key == a.key) &&
            (year == null || a.year == null || a.year == year),
      );
      if (!ok) found.add(title);
    }

    for (final m in RegExp(r'«([^»\n]{1,80})»').allMatches(answer)) {
      check('«${m[1]!.trim()}»', assistantTitleKey(m[1]!), null, suffix: false);
    }
    // "Shrek (2001)" in prose: the words before the year must end in a title
    // that passed.
    for (final m in RegExp(r'([^\n«»()]{1,80}?)[ \t]*\(((?:19|20)\d{2})\)').allMatches(answer)) {
      if (m.start > 0 && answer[m.start - 1] == '»') continue;
      final before = m[1]!.trim();
      final quote = before.length > 40 ? '...${before.substring(before.length - 40)}' : before;
      check('"$quote (${m[2]})"', assistantTitleKey(before), int.parse(m[2]!), suffix: true);
    }
    return found;
  }

  /// The titles the age gate turned down this ask that the answer names
  /// anywhere in its text, with or without « » or a year. A title of which
  /// another year passed (Dune 1984, not Dune 2021) only counts when named
  /// with its own year.
  List<({String title, int? year, String reason})> _rejectedNamed(String answer) {
    if (!_ctx.kidsMode || _ctx.ageRejected.isEmpty) return const [];
    final text = ' ${assistantPlainWords(answer)} ';
    final named = assistantNamedTitles(answer);
    final passed = {for (final a in _ctx.ageAllowed) assistantTitleKey(a.title)};
    final seen = <String>{};
    return [
      for (final r in _ctx.ageRejected)
        if (passed.contains(assistantTitleKey(r.title))
            ? named.any(
                (t) => assistantSameTitle(
                  (key: assistantTitleKey(r.title), year: r.year),
                  assistantTitleKey(t.title),
                  t.year,
                ),
              )
            : assistantTitleWords(r.title).any((words) => text.contains(' $words ')))
          if (seen.add(assistantTitleKey(r.title))) r,
    ];
  }

  /// Whether [named] is a pick the user has not watched: in a pick grid under
  /// that title and year, and not the watched title itself. A watched series
  /// and a film of that name are two titles; the same film or series is not.
  bool _isPick(({String title, int? year}) named) {
    final key = assistantTitleKey(named.title);
    return named.year != null &&
        _pickGrids.any(
          (g) => g.entries.any(
            (e) =>
                e.item.year == named.year &&
                assistantTitleKey(e.item.title ?? '') == key &&
                !_history.any(
                  (h) =>
                      h.key == key &&
                      h.series == e.item.kind.isShowRelated &&
                      (h.year == null || h.year == e.item.year),
                ),
          ),
        );
  }

  /// Whether a closing answer names titles the way Pleya can tell: in « »,
  /// or followed by a year, also on a list line.
  bool _namesTitles(String answer) => answer.contains('«') || RegExp(r'\((?:18|19|20)\d{2}\)').hasMatch(answer);

  /// Titles the answer names without a card get one: Pleya looks them up
  /// itself with find_title and keeps the exact titles that can be opened
  /// from a library or requested. Never left to the model alone. After an
  /// action the action is the answer, and a named title is its subject. In
  /// kids mode find_title applies the age gate, so a turned-down title has
  /// no card. Returns the started step with its cards, not yet added, and
  /// whether its sources are still current.
  Future<({int index, AssistantDisplay? display, bool Function() current})?> _lookupNamedTitles(String answer) async {
    if (_actions.isNotEmpty || _cancelled || _spoilerQuestion != null || _ctx.libraryDoctorMode) return null;
    final evidenceContext = _ctx;
    // The client object itself, online or not: a connectivity flip must not
    // discard a valid answer, a replaced client or hidden server still does.
    final clients = {for (final id in evidenceContext.userServers) id: evidenceContext.servers.getClient(id)};
    final requestClient = evidenceContext.requests?.client();
    final requestUser = requestClient?.session.userId;
    // Match findTitles' own source roots, read live from Home's loader. Client
    // identity alone cannot detect a library being removed or hidden.
    Set<(ServerId, String, MediaKind)> visibleLibraryScope() => switch (evidenceContext.catalog?.rowLoader) {
      final CatalogHomeCustomRowLoader loader => {
        for (final kind in const [MediaKind.movie, MediaKind.show])
          for (final library in loader.librariesFor(kind))
            if (evidenceContext.servers.getClient(library.serverId) != null)
              (library.serverId, library.libraryId, kind),
      },
      _ => const {},
    };
    final libraryScope = visibleLibraryScope();
    bool librariesCurrent() {
      final live = visibleLibraryScope();
      return live.length == libraryScope.length && live.containsAll(libraryScope);
    }

    bool current() =>
        !_cancelled &&
        evidenceContext.playbackEvidenceCurrent &&
        evidenceContext.libraryDoctorError == null &&
        evidenceContext.recommendationError == null &&
        identical(evidenceContext.requests?.client(), requestClient) &&
        requestClient?.session.userId == requestUser &&
        librariesCurrent() &&
        (evidenceContext.catalog == null ||
            evidenceContext.catalog!.activeProfileId() == evidenceContext.catalog!.profileId) &&
        clients.length == evidenceContext.userServers.length &&
        clients.entries.every(
          (entry) =>
              evidenceContext.userServers.contains(entry.key) &&
              identical(evidenceContext.servers.getClient(entry.key), entry.value),
        );
    if (!current()) return null;
    var all = assistantNamedTitles(answer);
    var kept = 0;
    if (_personal) {
      // A title named as the reason ("omdat je Reacher keek") is history, not a pick.
      all = [
        for (final t in all)
          // Dune (2021) is not the Dune (1984) the user watched.
          // A pick named with its year is a pick, whatever shares its name
          // in the history (the series Fargo next to the film from 1996).
          if (_isPick(t) ||
              !_history.any((h) => assistantSameTitle((key: h.key, year: h.year), assistantTitleKey(t.title), t.year)))
            t,
      ];
      kept = _narrowPicks(all);
    }
    final shown = assistantShownTitles(_displays);
    final room = _personal ? (_wanted ?? 5) - kept : 5;
    final named = [
      for (final t in all)
        if (!shown.any((c) => assistantSameTitle(c, assistantTitleKey(t.title), t.year))) t,
    ].take(room < 0 ? 0 : room).toList();
    if (named.isEmpty) return null;
    final tool = _available().keys.where((t) => t.name == 'find_title').firstOrNull;
    if (tool == null || tool.risk != AssistantToolRisk.read) return null;
    if (budget != null && !budget!.reserveTool()) return null;
    _namedTitlesCurrent = current;
    final index = _stepIndex++;
    onStep?.call(AssistantStep(index: index, tool: tool.name, phase: AssistantStepPhase.started));
    AssistantDisplay? display;
    try {
      final titles = {for (final t in named) t.title}.toList();
      // The same stamp as every other read: rights that moved while it ran
      // leave no card.
      final stamp = rightsEpoch?.call();
      final operation = _operation(() async {
        if (!current() || !tool.serves(_ctx, AssistantRun._noServer)) throw const AssistantToolError('cancelled');
        return tool.run(_ctx, null, {
          'candidates': [
            for (final t in named) {'title': t.title, 'year': ?t.year},
          ],
          'variants': [...titles, if (titles.length == 1) titles.single.toLowerCase()],
        });
      });
      final outcome = await Future.any<AssistantToolOutcome>([
        operation,
        if (cancel != null)
          cancel!.trigger.then<AssistantToolOutcome>((_) => throw const AssistantToolError('cancelled')),
      ]);
      if (!current()) return null;
      final rightsMoved = stamp != null && rightsEpoch!() != stamp;
      if (rightsMoved) _ctx.forgetReads();
      final readOutcome = rightsMoved ? null : outcome;
      if (readOutcome case AssistantToolResult(display: AssistantTitleMatches(:final context, :final matches))) {
        final exact = [
          for (final m in matches)
            if ((m.targets.isNotEmpty || m.request != null) &&
                named.any(
                  (t) => assistantSameTitle(
                    (key: assistantTitleKey(m.title), year: m.year),
                    assistantTitleKey(t.title),
                    t.year,
                  ),
                ))
              m,
        ];
        if (exact.isNotEmpty) display = _ctx.recommend.admit(AssistantTitleMatches(context, exact));
      }
    } on AssistantToolError catch (e) {
      if (e.code == 'kids_ages_unknown') _askKidsAges();
    } catch (e) {
      appLogger.d('Assistant: named titles lookup failed', error: e.runtimeType);
    }
    if (!current()) return null;
    return (index: index, display: display, current: current);
  }

  /// Narrows the pick grids to the named titles; returns how many cards stay.
  /// A grid not narrowed by the end of the run is dropped in [_end].
  int _narrowPicks(List<({String title, int? year})> named) {
    final used = <String>{};
    var total = 0;
    for (final grid in _pickGrids.toList()) {
      _pickGrids.remove(grid);
      final at = _displays.indexOf(grid);
      if (at < 0) continue;
      final kept = <AssistantMediaGridEntry>[];
      for (final t in named) {
        for (final e in grid.entries) {
          if (assistantSameTitle(
            (key: assistantTitleKey(e.item.title ?? ''), year: e.item.year),
            assistantTitleKey(t.title),
            t.year,
          )) {
            // One card per title, also across grids and for a title named twice.
            if (used.add(e.item.globalKey)) kept.add(e);
            break;
          }
        }
      }
      final room = (_wanted ?? 5) - total;
      kept.removeRange(kept.length.clamp(0, room < 0 ? 0 : room), kept.length);
      total += kept.length;
      if (kept.isEmpty) {
        _displays.removeAt(at);
      } else {
        _displays[at] = AssistantMediaGrid(kept);
      }
    }
    return total;
  }
}
