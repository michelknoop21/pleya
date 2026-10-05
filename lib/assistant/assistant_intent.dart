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
const _watch = r'(?:kijk\w*|ke+k\w*|gekeken|gezien|watch\w*|seen)';
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
  r'andere gebruikers|other users)\b',
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
final _movieWord = RegExp(r'\b(films?|movies?)\b');
final _seriesWord = RegExp(r'\b(series|serie|tv-series|tv shows?|shows)\b');
final _daysWord = RegExp(r'\b(\d{1,2})\s*(?:dagen|days)\b');
final _today = RegExp(r'\b(vandaag|today|afgelopen dag|laatste 24 uur|last 24 hours)\b');
// "Last week" and "vorige week" are the week before, not the past seven days.
final _week = RegExp(r'\b(deze week|afgelopen week|laatste week|this week|past week)\b');
final _month = RegExp(r'\b(deze maand|afgelopen maand|laatste maand|this month|past month)\b');

/// What a question is about, fixed by code from what the user wrote, with the
/// source of every field. The model fills only what stays unknown; a field the
/// user stated is enforced on tool arguments ([constrain]).
class AssistantIntent {
  const AssistantIntent({
    this.audience = const IntentField.unknown(),
    this.kind = const IntentField.unknown(),
    this.days = const IntentField.unknown(),
  });

  final IntentField<AssistantAudience> audience;
  final IntentField<MediaKind> kind;

  /// A period in days (1-31), as watch_stats takes it.
  final IntentField<int> days;

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
    final movie = _movieWord.hasMatch(p);
    final show = _seriesWord.hasMatch(p);
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
      audience: audience == null ? const IntentField.unknown() : IntentField(audience, AssistantFieldSource.explicit),
      kind: kind == null ? const IntentField.unknown() : IntentField(kind, AssistantFieldSource.explicit),
      days: days == null || days < 1 || days > 31
          ? const IntentField.unknown()
          : IntentField(days, AssistantFieldSource.explicit),
    );
  }

  /// This intent, with every field the question did not state itself taken
  /// from [parent]'s explicit ones: a task split off a question keeps what that
  /// question fixed, however the model words the task.
  AssistantIntent inheriting(AssistantIntent parent) => AssistantIntent(
    audience: audience.known ? audience : (parent.audience.explicit ? parent.audience : audience),
    kind: kind.known ? kind : (parent.kind.explicit ? parent.kind : kind),
    days: days.known ? days : (parent.days.explicit ? parent.days : days),
  );

  bool get any => audience.known || kind.known || days.known;

  /// Tool arguments with what the user said laid over what the model chose, or
  /// the error code when the tool does not fit the question. Fields the user
  /// did not state are left to the model.
  ({Map<String, Object?> args, String? error}) constrain(String tool, Map<String, Object?> args) {
    final out = {...args};
    switch (tool) {
      case 'watch_stats':
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
        if (days.explicit && out['scope'] == 'period') out['days'] = days.value;
      case 'my_watching':
        if (audience.explicit && audience.value != AssistantAudience.me) return (args: out, error: 'use_watch_stats');
        if (kind.explicit) out['kind'] = kind.value == MediaKind.movie ? 'movie' : 'show';
    }
    return (args: out, error: null);
  }

  /// A system note for the model: what is already fixed, so it neither asks nor
  /// widens. Null when nothing is.
  String? describe() {
    if (!any) return null;
    return 'Fixed by Pleya from the user\'s words (do not change or ask again): '
        '${[if (audience.explicit) 'audience ${audience.value!.name}', if (kind.explicit) 'only ${kind.value == MediaKind.movie ? 'films' : 'series'}', if (days.explicit) 'last ${days.value} days'].join(', ')}.';
  }
}
