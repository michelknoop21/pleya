part of 'assistant_tools.dart';

// Title facts on the rows the title tools return, and the age gate for picks
// for children. In kids mode a title passes only when AgeGate allows it for
// the youngest child; the rest never reaches the model or a card.

/// Pleya asks for the children's ages on a card of its own, then submits
/// [prompt] again. Big P never asks for them in text.
class AssistantKidsAgesPrompt extends AssistantDisplay {
  const AssistantKidsAgesPrompt(this.prompt);
  final String prompt;
}

const _forKids = {
  'for_kids': {
    'type': 'boolean',
    'description': 'true when the titles are for children; Pleya then keeps only titles suitable for their age',
  },
};

/// The youngest child's age when this ask picks for children, else null.
/// Throws `kids_ages_unknown` when it does but no ages are saved yet.
Future<int?> _kidsAge(AssistantToolContext ctx, Map<String, Object?> args) async {
  if (!ctx.kidsFilter) return null;
  if (_bool(args, 'for_kids')) ctx.kidsMode = true;
  if (!ctx.kidsMode) return null;
  final ages = await ctx.kidsAges?.call() ?? const <int>[];
  if (ages.isEmpty) throw const AssistantToolError('kids_ages_unknown');
  return ctx.kidsAge = ages.reduce(min);
}

TmdbKind _tmdbKind(MediaKind? kind) => kind == MediaKind.movie ? TmdbKind.movie : TmdbKind.tv;

TitleRef _itemRef(MediaItem item) =>
    TitleRef(kind: _tmdbKind(item.kind), title: item.title ?? '', year: item.year, item: item, serverId: item.serverId);

TitleRef _seerrRef(SeerrMedia m) => TitleRef(
  kind: m.isMovie ? TmdbKind.movie : TmdbKind.tv,
  title: m.title,
  year: int.tryParse(m.year ?? ''),
  tmdbId: m.tmdbId,
);

/// What [_gateTitles] kept, each with its facts (null without a facts
/// service), and the note every tool output gets in kids mode.
typedef _Gated<T> = ({List<(T, TitleFacts?)> kept, Map<String, Object?> note, String Function() region});

/// Looks up facts for [rows] and, with [age], keeps only what AgeGate
/// allows for that age. Turned-down titles are remembered on [ctx] so the
/// run can hold the answer to them.
Future<_Gated<T>> _gateTitles<T>(
  AssistantToolContext ctx,
  List<T> rows,
  TitleRef Function(T row) refOf,
  int? age,
) async {
  final refs = [for (final r in rows) refOf(r)];
  final service = ctx.titleFacts;
  final List<TitleFacts?> facts = service == null || rows.isEmpty
      ? List.filled(rows.length, null)
      : await service.factsFor(refs);
  // Read once, and only when something needs it.
  late final region = ctx.region();
  if (age == null) {
    return (
      kept: [for (final (i, r) in rows.indexed) (r, facts[i])],
      note: const <String, Object?>{},
      region: () => region,
    );
  }
  final kept = <(T, TitleFacts?)>[];
  for (final (i, r) in rows.indexed) {
    final f = facts[i] ?? const TitleFacts();
    if (AgeGate.allows(f, age, region)) {
      kept.add((r, facts[i]));
    } else {
      ctx.ageRejected.add((title: clipText(refs[i].title), year: refs[i].year, reason: AgeGate.reason(f, region)));
    }
  }
  return (kept: kept, note: {'filtered_for_age': rows.length - kept.length, 'kids_age': age}, region: () => region);
}

/// The compact facts for a row, or nothing when there are none.
Map<String, Object?> _factsField(TitleFacts? facts, String Function() region) => switch (facts?.toModelJson(region())) {
  final f? when f.isNotEmpty => {'facts': f},
  _ => const {},
};
