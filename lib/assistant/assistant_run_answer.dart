part of 'assistant_run.dart';

// The closing answer: cards for the titles it names, and in kids mode the
// age gate on them. A title the gate turned down never gets a card, and the
// model gets one correction round that Pleya itself words.

/// Tool errors that are no failure of the task.
const _kidsCodes = {'kids_ages_unknown', 'kids_mode_unsupported', 'household_kids_unknown'};

extension _AssistantAnswer on AssistantRun {
  /// A children's profile without saved ages, while no title tool has read
  /// them yet.
  Future<bool> _kidsAgesMissing() async =>
      _ctx.kidsMode && _ctx.kidsAge == null && (await _ctx.kidsAges?.call() ?? const <int>[]).isEmpty;

  /// A question about the children, with no valid child entered yet.
  bool get _householdMissing => _ctx.ageGate == AssistantAgeGate.kidAudience && _ctx.audienceAge == null;

  /// Marks that the ask needs the household's children, once per ask.
  void _askHousehold() {
    if (!_displays.any((d) => d is AssistantHouseholdKidsPrompt)) _displays.add(const AssistantHouseholdKidsPrompt());
  }

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
    if (clean) _keepTheOneNamed(answer);
    if (clean) _namedFirst(answer);
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
    if (!_ctx.gated) return const [];
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
    if (!_ctx.gated || _ctx.ageRejected.isEmpty) return const [];
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

  /// How [answer] names the title, for ranking its card, or null when it does
  /// not: tier 0 when it is marked (between « and », or with its year), tier 1
  /// when only its plain words appear and the title is distinctive (two words or
  /// eight letters). A watched title named without a mark is the reason or the
  /// one left out, not the pick. [at] is the earliest position in the plain
  /// words, [length] how much of the answer the match covers, so "Toy Story 2"
  /// outranks "Toy Story" where both match.
  ({int tier, int at, int length})? _mentionOf(String answer, String? title, int? year) {
    final name = (title ?? '').toLowerCase();
    if (name.isEmpty) return null;
    final lower = answer.toLowerCase();
    final marked =
        lower.contains('«$name»') || lower.contains('«$name (') || (year != null && lower.contains('$name ($year)'));
    final plain = ' ${assistantPlainWords(answer)} ';
    int? at;
    var length = 0;
    for (final w in assistantTitleWords(title!)) {
      if (!marked && !w.contains(' ') && w.length < 8) continue;
      final found = plain.indexOf(' $w ');
      if (found < 0) continue;
      if (at == null || found < at) at = found;
      if (w.length > length) length = w.length;
    }
    if (at == null) return null;
    final watched = _history.any((h) => assistantSameTitle((key: h.key, year: h.year), assistantTitleKey(title), year));
    if (!marked && watched) return null;
    return (tier: marked ? 0 : 1, at: at, length: length);
  }

  /// A list of cards starts with the titles the answer names, marked ones
  /// first, in the order it names them, then the rest as they were. Only
  /// reorders: the recommendation is not the last of five. After an action the
  /// action is the answer.
  void _namedFirst(String answer) {
    if (_actions.isNotEmpty || _spoilerQuestion != null || _ctx.libraryDoctorMode) return;
    List<T> sorted<T>(List<T> all, ({int tier, int at, int length})? Function(T) mention) {
      final named = <(({int tier, int at, int length}), int, T)>[];
      final rest = <T>[];
      for (final (index, e) in all.indexed) {
        final m = mention(e);
        if (m == null) {
          rest.add(e);
        } else {
          named.add((m, index, e));
        }
      }
      named.sort((a, b) {
        final x = a.$1;
        final y = b.$1;
        final byTier = x.tier.compareTo(y.tier);
        if (byTier != 0) return byTier;
        final byAt = x.at.compareTo(y.at);
        if (byAt != 0) return byAt;
        final byLength = y.length.compareTo(x.length);
        return byLength != 0 ? byLength : a.$2.compareTo(b.$2);
      });
      return [for (final n in named) n.$3, ...rest];
    }

    // In place: the lookups and the shown-title bookkeeping know a display by
    // its identity, so it is not replaced.
    void reorder<T>(List<T> list, ({int tier, int at, int length})? Function(T) mention) {
      final next = sorted(list, mention);
      try {
        list.setAll(0, next);
      } on UnsupportedError {
        // An unmodifiable list stays as it is.
      }
    }

    for (final display in _displays) {
      switch (display) {
        case AssistantMediaGrid(:final entries):
          reorder(entries, (e) => _mentionOf(answer, e.item.title, e.item.year));
        case AssistantTitleMatches(:final matches):
          reorder(matches, (m) => _mentionOf(answer, m.title, m.year));
        default:
      }
    }
  }

  /// The titles [answer] recommends, for a personal answer: those it names
  /// except a title named as the reason ("omdat je Reacher keek"), which is
  /// history and not a pick.
  List<({String title, int? year})> _namedRecommendations(String answer) => [
    for (final t in assistantNamedTitles(answer))
      // Dune (2021) is not the Dune (1984) the user watched.
      // A pick named with its year is a pick, whatever shares its name
      // in the history (the series Fargo next to the film from 1996).
      if (_isPick(t) ||
          !_history.any((h) => assistantSameTitle((key: h.key, year: h.year), assistantTitleKey(t.title), t.year)))
        t,
  ];

  /// The answer as shown. In a personal answer every title it recommends has a
  /// card: a sentence that names one without a card (past the asked number,
  /// not in the results, not in the library) is left out, and when nothing that
  /// names a card is left, Pleya's own short line stands in. Text and cards
  /// are then the same set. Only removes words, line by line so a list keeps
  /// its shape; the cards are untouched. After an action the action is the
  /// answer and its subject is no recommendation.
  String _presentedAnswer(String text) {
    if (!_personal ||
        _actions.isNotEmpty ||
        _ctx.libraryDoctorMode ||
        _spoilerQuestion != null ||
        text.trim().isEmpty) {
      return text;
    }
    final named = _namedRecommendations(text);
    if (named.isEmpty) return text;
    final shown = assistantShownTitles(_displays);
    bool carded(({String title, int? year}) t) =>
        shown.any((c) => assistantSameTitle(c, assistantTitleKey(t.title), t.year));
    final missing = [
      for (final t in named)
        if (!carded(t)) t,
    ];
    if (missing.isEmpty) return text;
    final cards = named.where(carded).toList();
    final lines = <String>[];
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) {
        // A paragraph break stays; one never leads the answer or doubles.
        if (lines.isNotEmpty && lines.last.isNotEmpty) lines.add('');
        continue;
      }
      final kept = [
        for (final s in _sentencesOf(line))
          if (!missing.any((t) => _namesTitle(s, t))) s,
      ];
      if (kept.isNotEmpty) lines.add(kept.join(' '));
    }
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    final stillNamesCard = lines.any((l) => cards.any((t) => _namesTitle(l, t)));
    if (lines.isNotEmpty && stillNamesCard) return lines.join('\n');
    final dutch = languageName == 'Dutch';
    return cards.isEmpty
        ? (dutch ? 'Ik kon hier geen titel voor controleren.' : 'I could not check a title for this.')
        : (dutch ? 'Dit zijn de titels die ik kon controleren.' : 'These are the titles I could check.');
  }

  /// The sentences of one line. A title between « and » is never cut, and a
  /// list marker ("1.") or an abbreviation ("Mr.") before a capital is not an
  /// end: a sentence ends at . ! or ? followed by a space and a capital, « or
  /// digit, and not after a list marker, an initialism ("U.S.") or a few abbreviations.
  List<String> _sentencesOf(String line) {
    final quoted = <String>[];
    final masked = line.replaceAllMapped(RegExp('«[^»]*»'), (m) {
      quoted.add(m[0]!);
      return '\u0001${quoted.length - 1}\u0001';
    });
    final parts = <String>[];
    var start = 0;
    for (final m in RegExp(r'([.!?])\s+(?=[A-ZÀ-Ý«\u0001\d])').allMatches(masked)) {
      final head = masked.substring(start, m.start);
      final lastWord = head.split(RegExp(r'\s+')).last;
      // A list marker is the whole head ("1."); a number or a letter at the end
      // of a sentence ("uit 2000.", "plan A.") is an ordinary end.
      final abbreviation =
          m[1] == '.' &&
          (RegExp(r'^\d{1,2}$').hasMatch(head.trim()) ||
              RegExp(r'^(mrs?|ms|dr|st|jr|sr|vs|nr)$', caseSensitive: false).hasMatch(lastWord) ||
              RegExp(r'^(?:[A-Za-z]\.)+[A-Za-z]$').hasMatch(lastWord));
      if (abbreviation) continue;
      parts.add(masked.substring(start, m.end).trim());
      start = m.end;
    }
    parts.add(masked.substring(start).trim());
    return [
      for (final p in parts)
        if (p.isNotEmpty) p.replaceAllMapped(RegExp('\u0001(\\d+)\u0001'), (m) => quoted[int.parse(m[1]!)]),
    ];
  }

  /// Whether [sentence] names [t]: its title between « and », or with its year,
  /// or in plain words when the title is distinctive (two words or eight
  /// letters). A short single word ("Her", "It", "Heat") is plain prose and
  /// only counts when marked.
  bool _namesTitle(String sentence, ({String title, int? year}) t) {
    final lower = sentence.toLowerCase();
    final title = t.title.toLowerCase();
    if (lower.contains('«$title')) return true;
    if (t.year != null && lower.contains('$title (${t.year})')) return true;
    final words = ' ${assistantPlainWords(sentence)} ';
    return assistantTitleWords(t.title).any((w) => (w.contains(' ') || w.length >= 8) && words.contains(' $w '));
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
      all = _namedRecommendations(answer);
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
      final stamp = _beginRead();
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
      if (e.code == 'household_kids_unknown') _askHousehold();
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
