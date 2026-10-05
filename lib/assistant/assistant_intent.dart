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

// "Me" only on a first-person watch phrase: "ik" alone also appears in "ik wil
// weten wat Sam kijkt".
final _meWatch = RegExp(
  r'\b(heb ik|keek ik|zag ik|ik heb (?:\w+\s+){0,2}(?:gekeken|gezien)|mijn (?:kijk|geschiedenis|historie|laatst)|'
  r'have i|did i watch|i (?:have )?watched|i watched|my (?:watch|history))',
);
final _others = RegExp(
  r'\b(anderen|andere gebruikers|andere mensen|de rest|zonder mij|behalve mij|iedereen behalve|'
  r'others|everyone else|everybody else|without me|except me|my friends|mijn vrienden|mijn gezin|my family)\b',
);
final _everyone = RegExp(
  r'\b(iedereen|alle gebruikers|alle accounts|het hele huishouden|everybody|everyone|all users|all accounts|the whole household)\b',
);
final _movieWord = RegExp(r'\b(films?|movies?)\b');
final _seriesWord = RegExp(r'\b(series?|shows?|tv-series)\b');
final _daysWord = RegExp(r'\b(\d{1,2})\s*(?:dagen|days)\b');
final _today = RegExp(r'\b(vandaag|today|afgelopen dag|laatste 24 uur|last 24 hours)\b');
final _week = RegExp(r'\b(deze week|afgelopen week|laatste week|vorige week|this week|past week|last week)\b');
final _month = RegExp(r'\b(deze maand|afgelopen maand|laatste maand|this month|past month|last month)\b');

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
    // "Others" wins over a first-person word: "what do the others watch, not me".
    final AssistantAudience? audience = _others.hasMatch(p)
        ? AssistantAudience.others
        : _meWatch.hasMatch(p)
        ? AssistantAudience.me
        : _everyone.hasMatch(p)
        ? AssistantAudience.everyone
        : null;
    final movie = _movieWord.hasMatch(p);
    final show = _seriesWord.hasMatch(p);
    final kind = movie == show ? null : (movie ? MediaKind.movie : MediaKind.show);
    final days = _daysWord.firstMatch(p) != null
        ? int.parse(_daysWord.firstMatch(p)!.group(1)!)
        : _today.hasMatch(p)
        ? 1
        : _week.hasMatch(p)
        ? 7
        : _month.hasMatch(p)
        ? 30
        : null;
    return AssistantIntent(
      audience: audience == null ? const IntentField.unknown() : IntentField(audience, AssistantFieldSource.explicit),
      kind: kind == null ? const IntentField.unknown() : IntentField(kind, AssistantFieldSource.explicit),
      days: days == null || days < 1 || days > 31
          ? const IntentField.unknown()
          : IntentField(days, AssistantFieldSource.explicit),
    );
  }

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
        if (kind.explicit && out['scope'] == 'period') out['media'] = kind.value == MediaKind.movie ? 'movie' : 'show';
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
