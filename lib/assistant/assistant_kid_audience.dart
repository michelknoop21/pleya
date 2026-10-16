import '../profiles/household_kids_store.dart';

// Whether a question is about the household's children. Code decides, from
// the user's words: a false positive only makes the answer stricter, a false
// negative lets titles through unfiltered, so the words lean wide.

const _start = r'(?<![\p{L}\p{N}])';
const _end = r'(?![\p{L}\p{N}])';

RegExp _re(String body) => RegExp('$_start(?:$body)$_end', unicode: true);

final _direct = _re(
  r'(?:mijn|onze|ons|de|my|our|the|voor|for|met|with)\s+(?:(?:kleine|jonge|little)\s+)?'
  r'(?:kinderen|kids|children(?! of men)|kleintjes|peuters?|kleuters?|toddlers?)'
  r'|(?:mijn|onze|ons|my|our)\s+(?:kleine|jongste|oudste|youngest|oldest|eldest|zoon|zoontje|dochter|dochtertje|'
  r'baby|peuter|kleuter|son|daughter|toddler|kids?|children|kind(?!-)|kleinkinderen|kleinkind(?!-)|jongens?|meisjes?|'
  r'little ones?)'
  r'|(?:de|the)\s+(?:jongste|youngest|little ones)'
  r'|(?:\d{1,2}|een|a)[ -]?(?:year[ -]?old|jarige?|jaar oud)'
  r'|de kleine(?:n)?|kinder(?:film|films|serie|series|programma\w*|voorstelling)|'
  r'(?:kids?|children\W?s?)\s+(?:movies?|films?|shows?|series|programs?|programmes?)'
  r'|kinderen|kids|peuters|kleuters|zoontje|dochtertje',
);

// "Kindvriendelijk" names a title only next to a title word ("een
// kindvriendelijke film"), not a restaurant or a hotel.
final _friendly = _re(r'kindvriendelijke?|kid[- ]friendly|child[- ]friendly');
final _titleWord = _re(r'films?|series?|shows?|titels?|titles?|movies?|programma\w*|tekenfilms?|cartoons?');

final _group = _re(r'gezin(?:snacht|sfilm|sfilms|savond)?|familie\w*|family\w*');

// An explicit "this is for me": ends the children's audience.
final _self = _re(r'voor mij|voor mezelf|voor mijzelf|alleen voor mij|for me|for myself|just for me');

/// What a question says about the children: [on], and the [ids] of the
/// household children it names (empty: all of them).
typedef KidAudience = ({bool on, Set<String> ids});

const noKidAudience = (on: false, ids: <String>{});

// Kids named only to be left out ("vergeet de kinderfilms", "geen kids
// movies") or as who shares the account ("mijn account met mijn kinderen"):
// the asker is not asking for them. Stripped before the words are read, and
// only these two shapes, so "voor mij en mijn kinderen" still counts.
final _leftOut = _re(
  r'(?:vergeet\w*|geen|niet|zonder|behalve|forget|no|not|without|except|exclude|skip)\s+(?:even\s+|de\s+|the\s+)?'
  r'(?:\w+\s+){0,1}(?:kinder\w+|kids?|children\w*)(?:\s+(?:movies?|films?|shows?|series))?',
);
final _sharedAccount = _re(
  r'(?:account|profiel|profile|abonnement|login)\s+(?:\w+\s+){0,2}?(?:met|with)\s+(?:mijn|onze|my|our)\s+'
  r'(?:kinderen|kids|children|zoon|dochter)',
);

/// The audience of [prompt] alone. "Gezin" and "familie" only count once
/// [household] holds children.
({bool direct, bool general, bool cleared, Set<String> ids}) _read(String prompt, List<HouseholdKid> household) {
  final lower = prompt.toLowerCase();
  final p = lower.replaceAll(_leftOut, ' ').replaceAll(_sharedAccount, ' ');
  final named = {
    for (final k in household)
      if (k.name.trim().length >= 2 &&
          RegExp('$_start${RegExp.escape(k.name.trim().toLowerCase())}$_end', unicode: true).hasMatch(p))
        k.id,
  };
  final general =
      _direct.hasMatch(p) ||
      (_friendly.hasMatch(p) && _titleWord.hasMatch(p)) ||
      (household.isNotEmpty && _group.hasMatch(p));
  return (direct: general || named.isNotEmpty, general: general, cleared: _self.hasMatch(p), ids: named);
}

/// The audience of the ask [prompt] after the earlier [turns] of the
/// conversation (oldest first, questions only) and, for a task split off a
/// question, the [initial] audience of that question. Once a question is
/// about the children, the follow-ups stay so until "voor mij" or a new
/// conversation. A name alone narrows to that child only when nothing wider
/// came before and no general word stands beside it: the youngest wins.
KidAudience kidAudienceOf(
  String prompt,
  List<String> turns,
  List<HouseholdKid> household, {
  KidAudience initial = noKidAudience,
}) {
  var on = initial.on;
  var all = initial.on && initial.ids.isEmpty;
  var ids = {...initial.ids};
  for (final q in [...turns, prompt]) {
    final r = _read(q, household);
    if (r.direct) {
      if (r.general || (on && all)) {
        all = true;
        ids = {};
      } else {
        ids = {...ids, ...r.ids};
      }
      on = true;
    } else if (r.cleared) {
      on = false;
      all = false;
      ids = {};
    }
  }
  // Fail closed: what a split task inherited cannot be cleared by its own words.
  if (!on) return initial;
  return (on: true, ids: all ? <String>{} : ids);
}
