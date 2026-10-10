import '../media/media_kind.dart';

/// Where a fact about the question comes from. Higher wins: a lower source
/// never overrides a higher one (contract: security, then what the user said
/// now, then the conversation, then memory, then defaults, then the model).
enum AssistantFieldSource { explicit, conversation, memory, defaults, unknown }

/// One fact about the question and where it came from.
class IntentField<T> {
  const IntentField(this.value, this.source);
  const IntentField.unknown() : value = null, source = AssistantFieldSource.unknown;

  final T? value;
  final AssistantFieldSource source;

  bool get known => value != null;

  /// The user said it in this question. Only that may overrule the model.
  bool get explicit => known && source == AssistantFieldSource.explicit;
}

/// Whose data a question is about.
enum AssistantAudience { me, others, everyone }

// A watch verb, the anchor for every audience word: "others" or "everyone" on
// its own also appear in recommendation sentences ("a film everyone likes").
const _watch = r'(?:kijk\w*|ke+k\w*|gekeken|bekeken|gezien|watch\w*|seen)';
final _meWatch = RegExp(
  r'\b(heb ik|keek ik|zag ik|ik heb (?:\w+\s+){0,2}(?:gekeken|gezien)|ik (?:\w+\s+){0,2}(?:gekeken|gezien) heb|mijn (?:kijk|geschiedenis|historie|laatst)|'
  r'have i|did i watch|i (?:have )?watched|my (?:watch|history))',
);
final _othersWatch = RegExp(
  r'\b(?:anderen|others)\s+(?:\w+\s+){0,3}' + _watch + r'|\b' + _watch + r'\s+(?:\w+\s+){0,2}(?:anderen|others)\b',
);
// Unmistakable without a verb: the asker is named out.
final _othersFixed = RegExp(
  r'\b(zonder mij|behalve mij|iedereen behalve (?:mij|ik|me)\b|everyone else|everybody else|without me|except me|'
  r'andere gebruikers|other users|(?:everyone|everybody)\s+(?:but|besides|other than)\s+(?:me|myself|i))\b',
);
// "Not the others": the others are what the user does not want.
final _notOthers = RegExp(r'\b(niet|geen|not)\s+(?:wat\s+)?(?:de\s+|the\s+)?(?:anderen|others)\b');
final _everyoneWatch = RegExp(
  r'\b(?:iedereen|everybody|everyone)\s+(?:\w+\s+){0,3}' +
      _watch +
      r'|\b' +
      _watch +
      r'\s+(?:\w+\s+){0,2}(?:iedereen|everybody|everyone)\b|\b(?:alle gebruikers|all users|alle accounts|all accounts|het hele huishouden|the whole household)\b',
);
// "Everyone except Sam": a group minus someone else, not "the others".
final _exceptName = RegExp(
  r'\b(?:iedereen|everyone|everybody)\s+(?:behalve|except|but)\s+(?!mij\b|ik\b|me\b|myself\b)',
);
// A bare "show" is the verb ("show me"); only the plural or "tv show" is a series.
// Compounds count too ("kerstfilm", "docuserie"): a half-seen kind would narrow.
final _movieWord = RegExp(r'\b(?:\w*films?|movies?)\b');
final _seriesWord = RegExp(r'\b(?:\w*series?|tv-series|tv shows?|shows)\b');
// A kind word that only names something else ("de acteur uit de serie Friends",
// "bekend van de film Cast Away") is a reference, not the kind asked for.
final _kindReference = RegExp(
  r'\b(?:van|uit|als|zoals|from|like|in)\s+(?:de|het|een|the|a|die|dat)\s+(?:\w*films?|\w*series?|movies?)\b',
);
final _daysWord = RegExp(r'\b(\d{1,2})\s*(?:dagen|days)\b');
final _today = RegExp(r'\b(vandaag|today|afgelopen dag|laatste 24 uur|last 24 hours)\b');
// "Last week" and "vorige week" are the week before, not the past seven days.
final _week = RegExp(r'\b(deze week|afgelopen week|laatste week|this week|past week)\b');
// "What was added to the libraries", not "what I added to my list".
final _added = RegExp(
  r'\b(toegevoegde?|(?:er\s?)?bij\s?gekomen|nieuwe toevoegingen|(?:newly|recently|just) added|added (?:this|last|in the)|new additions|recent additions|was added|got added|been added)\b',
);
final _addedElsewhere = RegExp(
  r'\b(radarr|sonarr|requests?|aanvragen?|verzoeken|toegevoegde waarde|added value|kijklijst|watchlist|lijstje|mijn lijst|my list|favorieten|favourites?|afspeellijst|playlist|collectie|collection|wachtrij|queue|downloads?)\b',
);
// A period the parser cannot turn into days ("3 maanden", "2 weken"): the window is not guessed.
final _longPeriod = RegExp(r'\b\d{1,3}\s*(maanden|maand|weken|week|months?|weeks?)\b');
// "everyone else watched": a named group with its own verb, a clause of its own.
final _othersElseWatch = RegExp(
  r'\b(?:everyone else|everybody else|other users|andere gebruikers)\s+(?:\w+\s+){0,2}' + _watch,
);
// Words that make the two halves one relational question, not two lists.
final _relational = RegExp(
  r'\b(samen|together|both|allebei|beiden|ook|also|niet|not|nog niet|never|nooit|geen|but|except|behalve|same|zelfde|'
  r'die|dat|that|waar|where)\b',
);
// A second sentence inside one half.
final _sentenceBreak = RegExp(r'[.?!]\s*\S');
// A pronoun or demonstrative that points back at an earlier turn.
final _refersBack = RegExp(
  r'\b(daarvan|daarvoor|daarbij|daarin|hiervan|ervan|die|dat|deze|dit|ze|zij|hij|hun|that|those|these|them|they|their|it|its|this)\b',
);
// The word between two clauses of one sentence.
final _clauseJoin = RegExp(r'\s*(?:[,;]\s*\b(?:en|and|maar|but|plus)\b|[,;]|\b(?:en|and|maar|but|plus)\b)\s*');
final _previousWeek = RegExp(r'\b(vorige week|(?<!\b(?:in|within|over|during|for|of)\s+the\s+)last week)\b');
final _month = RegExp(r'\b(deze maand|afgelopen maand|laatste maand|this month|past month)\b');

/// What a question is about, fixed by code from what the user wrote, with the
/// source of every field. The model fills only what stays unknown; a field the
/// user stated is enforced on tool arguments ([constrain]).
class AssistantIntent {
  const AssistantIntent({
    this.audience = const IntentField.unknown(),
    this.kind = const IntentField.unknown(),
    this.days = const IntentField.unknown(),
    this.previousWeek = false,
    this.mixedAudience = false,
    this.addedToLibraries = false,
    this.longPeriodAsked = false,
  });

  final IntentField<AssistantAudience> audience;
  final IntentField<MediaKind> kind;

  /// A period in days (1-31), as watch_stats takes it.
  final IntentField<int> days;

  /// The question names the calendar week before this one, which watch_stats
  /// (a window of the last N days) cannot express.
  final bool previousWeek;

  /// The question asks about more than one audience at once; neither is fixed,
  /// and the model must not answer only one of them.
  final bool mixedAudience;

  /// The question is about what was added to the libraries, so watch history
  /// and server lists are the wrong tools and the period belongs to the catalog.
  /// Not inherited: a child task decides by its own words.
  final bool addedToLibraries;

  /// A period in weeks or months that days cannot express.
  final bool longPeriodAsked;

  static const unknown = AssistantIntent();

  /// ponytail: keyword rules over Dutch and English; a classifier for what
  /// these miss comes in a later step.
  factory AssistantIntent.fromPrompt(String prompt) {
    final p = prompt.toLowerCase();
    // What the question can mean for the audience. Two readings at once ("what
    // did I watch and what did the others") or a group minus a named person is
    // not decided here: unknown, so nothing is narrowed or widened by a guess.
    final others = !_notOthers.hasMatch(p) && (_othersWatch.hasMatch(p) || _othersFixed.hasMatch(p));
    final me = _meWatch.hasMatch(p);
    final everyone = !_exceptName.hasMatch(p) && !_othersFixed.hasMatch(p) && _everyoneWatch.hasMatch(p);
    final readings = [
      if (others) AssistantAudience.others,
      if (me) AssistantAudience.me,
      if (everyone) AssistantAudience.everyone,
    ];
    final AssistantAudience? audience = readings.length == 1 ? readings.single : null;
    final named = p.replaceAll(_kindReference, ' ');
    final movie = _movieWord.hasMatch(named);
    final show = _seriesWord.hasMatch(named);
    final kind = movie == show ? null : (movie ? MediaKind.movie : MediaKind.show);
    // Two different periods in one question: none is fixed.
    final periods = {
      for (final m in _daysWord.allMatches(p)) int.parse(m.group(1)!),
      if (_today.hasMatch(p)) 1,
      if (_week.hasMatch(p)) 7,
      if (_month.hasMatch(p)) 30,
    };
    final days = periods.length == 1 ? periods.single : null;
    return AssistantIntent(
      previousWeek: _previousWeek.hasMatch(p),
      mixedAudience: readings.length > 1,
      addedToLibraries: _added.hasMatch(p) && !_addedElsewhere.hasMatch(p),
      longPeriodAsked: _longPeriod.hasMatch(p),
      audience: audience == null ? const IntentField.unknown() : IntentField(audience, AssistantFieldSource.explicit),
      kind: kind == null ? const IntentField.unknown() : IntentField(kind, AssistantFieldSource.explicit),
      days: days == null || days < 1 || days > 31
          ? const IntentField.unknown()
          : IntentField(days, AssistantFieldSource.explicit),
    );
  }

  /// The two clauses of a question that asks about two audiences at once ("what
  /// did I watch and what did the others"), or null. Cut only when it is plainly
  /// two separate questions: two different audiences, each clause with its own
  /// watch verb, one joiner between them and none left inside a clause, no
  /// relational or negating word ("together", "not yet seen"), and a stated kind
  /// that both clauses carry. Anything less is left to the model, never cut by a
  /// guess.
  /// True when [prompt] points back at an earlier answer ("daarvan", "those").
  static bool refersBack(String prompt) => _refersBack.hasMatch(prompt.toLowerCase());

  static List<String>? splitMixedAudience(String prompt) {
    final p = prompt.toLowerCase();
    // Offsets are used on [prompt]: a lowercase that changed the length is no cut.
    if (p.length != prompt.length || _relational.hasMatch(p)) return null;
    final spans = <(int, int, AssistantAudience)>[];
    void add(RegExp re, AssistantAudience a) {
      final m = re.firstMatch(p);
      if (m != null) spans.add((m.start, m.end, a));
    }

    // A verbless "others" ("everyone else", "without me") is no clause of its own.
    if (_notOthers.hasMatch(p) || _exceptName.hasMatch(p)) return null;
    final elseWatch = _othersElseWatch.firstMatch(p);
    if (_othersFixed.hasMatch(p) && elseWatch == null) return null;
    add(_othersWatch, AssistantAudience.others);
    if (elseWatch != null && spans.isEmpty) spans.add((elseWatch.start, elseWatch.end, AssistantAudience.others));
    add(_meWatch, AssistantAudience.me);
    if (elseWatch == null) add(_everyoneWatch, AssistantAudience.everyone);
    if (spans.length != 2 || spans[0].$3 == spans[1].$3) return null;
    spans.sort((a, b) => a.$1.compareTo(b.$1));
    if (spans[1].$1 < spans[0].$2) return null;
    final gap = p.substring(spans[0].$2, spans[1].$1);
    final joins = _clauseJoin.allMatches(gap).toList();
    if (joins.length != 1) return null;
    final cut = joins.single;
    String tidy(String s) => s.replaceAll(RegExp(r'^[\s,;]+|[\s,;]+$'), '');
    final first = tidy(prompt.substring(0, spans[0].$2 + cut.start));
    final second = tidy(prompt.substring(spans[0].$2 + cut.end));
    if (first.isEmpty || second.isEmpty) return null;
    // Both halves are one question each: a verb of their own, no joiner inside,
    // and the same kind (a kind named in one half only would widen the other).
    for (final clause in [first, second]) {
      final lower = clause.toLowerCase();
      if (!RegExp(_watch).hasMatch(lower) || _clauseJoin.hasMatch(lower) || _sentenceBreak.hasMatch(lower)) {
        return null;
      }
    }
    final whole = AssistantIntent.fromPrompt(prompt).kind;
    if (whole.explicit &&
        !(AssistantIntent.fromPrompt(first).kind.explicit && AssistantIntent.fromPrompt(second).kind.explicit)) {
      return null;
    }
    return [first, second];
  }

  /// This intent, with the audience and period the question did not state itself
  /// taken from [parent]'s explicit ones: a task split off a question keeps whose
  /// data and which period it was about, however the model words the task. The
  /// kind is not inherited: in "what did I watch and tip a series" the kind word
  /// belongs to the tip, and a child must not narrow the history with it.
  AssistantIntent inheriting(AssistantIntent parent) => AssistantIntent(
    audience: audience.known ? audience : (parent.audience.explicit ? parent.audience : audience),
    kind: kind,
    days: days.known ? days : (parent.days.explicit ? parent.days : days),
    previousWeek: previousWeek || parent.previousWeek,
    mixedAudience: mixedAudience,
    addedToLibraries: addedToLibraries,
    longPeriodAsked: longPeriodAsked,
  );

  bool get any => audience.known || kind.known || days.known;

  /// Tool arguments with what the user said laid over what the model chose, or
  /// the error code when the tool does not fit the question. Fields the user
  /// did not state are left to the model.
  ({Map<String, Object?> args, String? error}) constrain(String tool, Map<String, Object?> args) {
    final out = {...args};
    switch (tool) {
      case 'list_servers':
        if (addedToLibraries) return (args: out, error: 'use_search_catalog');
      case 'search_catalog':
        if (addedToLibraries && previousWeek) return (args: out, error: 'previous_week_not_supported');
        if (addedToLibraries) {
          if (longPeriodAsked && !mixedAudience && !audience.known) return (args: out, error: 'window_not_supported');
          // The period is the additions' only when no other clause (a watch
          // question) could own it.
          if (days.explicit && !mixedAudience && !audience.known) out['added_within_days'] = days.value;
        }
        if (kind.explicit) out['kind'] = kind.value == MediaKind.movie ? 'movie' : 'show';
      case 'recommend_together':
        // The cohort query has its own kind: a question for films gets films,
        // whatever the model passed.
        if (kind.explicit) out['kind'] = kind.value == MediaKind.movie ? 'movie' : 'show';
      case 'watch_stats':
        if (addedToLibraries && !audience.known) return (args: out, error: 'use_search_catalog');
        // "What did I watch" is the asker's own log, never the server's account list.
        if (audience.explicit && audience.value == AssistantAudience.me) {
          return (args: out, error: 'use_my_watching');
        }
        if (audience.explicit) {
          out['audience'] = audience.value == AssistantAudience.others ? 'others' : 'all';
        }
        if (kind.explicit) {
          // Current streams cannot be filtered by kind: no list that mixes films and series.
          if (out['scope'] == 'now') return (args: out, error: 'media_needs_period');
          out['media'] = kind.value == MediaKind.movie ? 'movie' : 'show';
        }
        if (previousWeek) return (args: out, error: 'previous_week_not_supported');
        if (days.explicit && out['scope'] == 'period') out['days'] = days.value;
      case 'my_watching':
        // Also the tip tool, so no refusal here: the describe() note stops its
        // unwindowed history from passing as "last week".
        if (audience.explicit && audience.value != AssistantAudience.me) return (args: out, error: 'use_watch_stats');
        if (kind.explicit) out['kind'] = kind.value == MediaKind.movie ? 'movie' : 'show';
    }
    return (args: out, error: null);
  }

  /// A system note for the model: what is already fixed, so it neither asks nor
  /// widens. Null when nothing is.
  String? describe() {
    final fixed = [
      if (audience.explicit) 'audience ${audience.value!.name}',
      if (kind.explicit) 'only ${kind.value == MediaKind.movie ? 'films' : 'series'}',
      if (days.explicit) 'last ${days.value} days',
    ];
    final notes = [
      if (fixed.isNotEmpty) 'Fixed by Pleya from the user\'s words (do not change or ask again): ${fixed.join(', ')}.',
      if (mixedAudience)
        'The question covers more than one audience (for example the asker and the others): '
            'answer each part with its own tool call and say so, never only one part.',
      if (addedToLibraries)
        'The question is about what was added to the libraries: use search_catalog with added_within_days, '
            'never watch history or the server list.',
      if (previousWeek)
        'The question is about the calendar week before this one, which the tools cannot give: '
            'say so and offer the last 7 days instead; do not present another window as that week.',
    ];
    return notes.isEmpty ? null : notes.join(' ');
  }
}
