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
  /// title the age filter turned down and [mayCorrect]; otherwise adds the
  /// cards for its titles and returns null.
  Future<String?> _settleAnswer(String answer, {required bool mayCorrect}) async {
    final step = await _lookupNamedTitles(answer);
    final rejected = _rejectedNamed(answer);
    final unvetted = _unvettedNamed(answer, rejected);
    final keep = (rejected.isEmpty && unvetted.isEmpty) || !mayCorrect;
    if (keep && step?.display != null) _displays.add(step!.display!);
    if (step != null) {
      onStep?.call(
        AssistantStep(
          index: step.index,
          tool: 'find_title',
          phase: AssistantStepPhase.done,
          display: keep ? step.display : null,
          evidenceCurrent: step.current,
        ),
      );
    }
    if (rejected.isEmpty && unvetted.isEmpty) return null;
    if (keep) {
      // The model kept it: no card, no silent edit, a notice from Pleya.
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

  /// Named titles the age gate turned down this ask and no card shows.
  List<({String title, int? year, String reason})> _rejectedNamed(String answer) {
    if (!_ctx.kidsMode || _ctx.ageRejected.isEmpty) return const [];
    final shown = assistantShownTitles(_displays);
    return [
      for (final t in assistantNamedTitles(answer))
        if (!shown.any((c) => assistantSameTitle(c, assistantTitleKey(t.title), t.year)))
          ?_ctx.ageRejected
              .where(
                (r) => assistantSameTitle(
                  (key: assistantTitleKey(r.title), year: r.year),
                  assistantTitleKey(t.title),
                  t.year,
                ),
              )
              .firstOrNull,
    ];
  }

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
    final clients = {for (final id in evidenceContext.userServers) id: evidenceContext.userClient(id)};
    final requestClient = evidenceContext.requests?.client();
    final requestUser = requestClient?.session.userId;
    // Match findTitles' own source roots, read live from Home's loader. Client
    // identity alone cannot detect a library being removed or hidden.
    Set<(ServerId, String, MediaKind)> visibleLibraryScope() => switch (evidenceContext.catalog?.rowLoader) {
      final CatalogHomeCustomRowLoader loader => {
        for (final kind in const [MediaKind.movie, MediaKind.show])
          for (final library in loader.librariesFor(kind))
            if (evidenceContext.userClient(library.serverId) != null) (library.serverId, library.libraryId, kind),
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
              identical(evidenceContext.userClient(entry.key), entry.value),
        );
    if (!current()) return null;
    final shown = assistantShownTitles(_displays);
    final named = [
      for (final t in assistantNamedTitles(answer))
        if (!shown.any((c) => assistantSameTitle(c, assistantTitleKey(t.title), t.year))) t,
    ];
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
      if (outcome case AssistantToolResult(display: AssistantTitleMatches(:final context, :final matches))) {
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
        if (exact.isNotEmpty) display = AssistantTitleMatches(context, exact);
      }
    } on AssistantToolError catch (e) {
      if (e.code == 'kids_ages_unknown') _askKidsAges();
    } catch (e) {
      appLogger.d('Assistant: named titles lookup failed', error: e.runtimeType);
    }
    if (!current()) return null;
    return (index: index, display: display, current: current);
  }
}
