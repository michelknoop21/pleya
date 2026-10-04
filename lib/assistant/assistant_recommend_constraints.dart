import '../media/media_item.dart';
import '../media/media_kind.dart';
import 'assistant_tools.dart';

const _kidsGenres = {'kids', 'children', 'family', 'kinderen', 'familie', 'jeugd'};

/// Genres my_watching leaves out of `likes` when kids titles are excluded.
const assistantKidsTasteGenres = {..._kidsGenres, 'animation'};
const _kidsRatings = {'G', 'TV-Y', 'TV-Y7', 'TV-G', 'AL', '6'};

final _movieWord = RegExp(r'\b(films?|movies?)\b');
final _seriesWord = RegExp(r'\b(series?|shows?)\b');
final _kidsWord = RegExp(r'kinder|\bkids?\b|children');
final _dropWord = RegExp(r'\b(vergeet|negeer|zonder|geen|forget|ignore|without)\b');
final _sharedAccount = RegExp(r'\b(deel|share)\b.*\baccount');
final _adviceWord = RegExp(r'voorstel|\btips?\b|aanrader|recommend');

/// What the user's question demands of every recommendation, enforced on the
/// data the model reads and on the cards Pleya shows, so text and cards
/// cannot disagree.
class AssistantRecommendConstraints {
  const AssistantRecommendConstraints({this.kind, this.excludeKids = false, this.excludeWatched = false});

  final MediaKind? kind;
  final bool excludeKids;
  final bool excludeWatched;

  bool get active => kind != null || excludeKids || excludeWatched;

  /// ponytail: keyword heuristic over the prompt (Dutch and English); replace
  /// by the model's own arguments once those prove reliable.
  factory AssistantRecommendConstraints.fromPrompt(String prompt) {
    final p = prompt.toLowerCase();
    return AssistantRecommendConstraints(
      kind: _movieWord.hasMatch(p) && !_seriesWord.hasMatch(p) ? MediaKind.movie : null,
      excludeKids: _kidsWord.hasMatch(p) && (_dropWord.hasMatch(p) || _sharedAccount.hasMatch(p)),
      excludeWatched: _adviceWord.hasMatch(p),
    );
  }

  AssistantRecommendConstraints merge(AssistantRecommendConstraints other) => AssistantRecommendConstraints(
    kind: other.kind ?? kind,
    excludeKids: excludeKids || other.excludeKids,
    excludeWatched: excludeWatched || other.excludeWatched,
  );

  static bool isKids(MediaItem item) =>
      (item.genres ?? const []).any((g) => _kidsGenres.contains(g.toLowerCase())) ||
      _kidsRatings.contains(item.contentRating?.trim().toUpperCase());

  bool admitsItem(MediaItem item) =>
      (kind == null || _kindOf(item.kind) == kind) &&
      !(excludeKids && isKids(item)) &&
      !(excludeWatched && item.isWatched);

  static MediaKind _kindOf(MediaKind k) => k == MediaKind.episode ? MediaKind.show : k;

  /// The display with only what the constraints admit; null when nothing is
  /// left. The same instance when nothing was dropped. Other displays pass.
  AssistantDisplay? admit(AssistantDisplay display) {
    if (!active) return display;
    switch (display) {
      case AssistantMediaGrid(:final entries):
        final kept = [
          for (final e in entries)
            if (admitsItem(e.item)) e,
        ];
        if (kept.isEmpty) return null;
        return kept.length == entries.length ? display : AssistantMediaGrid(kept);
      case AssistantTitleMatches(:final context, :final matches):
        final kept = [
          for (final m in matches)
            if (_admitsMatch(m)) m,
        ];
        if (kept.isEmpty) return null;
        return kept.length == matches.length ? display : AssistantTitleMatches(context, kept);
      default:
        return display;
    }
  }

  bool _admitsMatch(AssistantTitleMatch m) {
    if (kind != null && (m.kind == 'movie' ? MediaKind.movie : MediaKind.show) != kind) return false;
    final items = [for (final t in m.targets) t.item];
    // A request-only match shows nothing that proves it is not a kids title.
    if (excludeKids && (items.isEmpty || items.any(isKids))) return false;
    return !(excludeWatched && items.any((i) => i.isWatched));
  }

  /// For the model, in plain words, or null without constraints.
  String? describe() {
    if (!active) return null;
    return 'The user asks for ${kind == MediaKind.movie
            ? 'films only'
            : kind == MediaKind.show
            ? 'series only'
            : 'any title'}'
        '${excludeKids ? ', no kids titles' : ''}${excludeWatched ? ', nothing they already watched' : ''}. '
        'Pleya does not show cards that do not meet this: name only titles that do.';
  }
}

final _count = RegExp(
  r'\b(een paar|a few|a couple of|\d+|een|één|twee|drie|vier|vijf|zes|one|two|three|four|five|six|an?)\s+(?:\w+\s+)?'
  r'(?:films?|movies?|series|shows?|opties|options|tips?|voorstel(?:len)?|suggest\w*|aanraders?|recommendations?)',
);
const _countWords = {
  'een paar': 3,
  'a few': 3,
  'a couple of': 2,
  'een': 1,
  'één': 1,
  'a': 1,
  'an': 1,
  'one': 1,
  'twee': 2,
  'two': 2,
  'drie': 3,
  'three': 3,
  'vier': 4,
  'four': 4,
  'vijf': 5,
  'five': 5,
  'zes': 6,
  'six': 6,
};

/// How many titles the question asks for ("twee films", "een paar opties",
/// "een film voor vanavond"), or null when it names no number.
int? assistantAskedCount(String prompt) {
  final w = _count.firstMatch(prompt.toLowerCase())?[1];
  return w == null ? null : int.tryParse(w) ?? _countWords[w];
}
