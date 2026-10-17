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

/// A question about the household's children came before any child was
/// entered: the run ends with Pleya's own line and no title, and a card asks
/// for the children (45 G). Pleya then submits [prompt] again.
class AssistantHouseholdKidsPrompt extends AssistantDisplay {
  const AssistantHouseholdKidsPrompt(this.prompt);
  final String prompt;
}

/// How a tool behaves on a children's profile.
enum KidsTool {
  /// Its titles pass the age gate.
  gated,

  /// It returns no titles (servers, jobs, users, a confirmed action).
  neutral,

  /// It returns titles the age gate never sees; kids mode refuses it.
  blocked,
}

/// Every tool's place in kids mode (a children's profile). A new tool must be added here: a test
/// walks the whole tool list, so a title tool cannot slip past the gate.
const kidsToolPolicy = <String, KidsTool>{
  'find_media': KidsTool.gated,
  'search_catalog': KidsTool.gated,
  'find_title': KidsTool.gated,
  'trending_titles': KidsTool.gated,
  'similar_titles': KidsTool.gated,
  'find_request_title': KidsTool.gated,
  'discover_request_titles': KidsTool.gated,
  'list_servers': KidsTool.neutral,
  'list_libraries': KidsTool.neutral,
  'list_users': KidsTool.neutral,
  'scan_library': KidsTool.neutral,
  'refresh_metadata': KidsTool.neutral,
  'cancel_job': KidsTool.neutral,
  'retry_job': KidsTool.neutral,
  'create_user': KidsTool.neutral,
  'set_user_library_access': KidsTool.neutral,
  'remove_user': KidsTool.neutral,
  // Only a seerr_id a gated tool showed can be requested.
  'request_title': KidsTool.neutral,
  'change_playback': KidsTool.neutral,
  'download_subtitle': KidsTool.neutral,
  // A saved search_catalog query holds every title, not only those that passed.
  'create_home_row': KidsTool.blocked,
  'create_collection': KidsTool.blocked,
  'recommend_together': KidsTool.blocked,
  'spoiler_context': KidsTool.blocked,
  'my_watching': KidsTool.blocked,
  'trakt_watchlist': KidsTool.blocked,
  'watch_stats': KidsTool.blocked,
  'compare_servers': KidsTool.blocked,
  'request_status': KidsTool.blocked,
  'diagnose_library': KidsTool.blocked,
  'diagnose_playback': KidsTool.blocked,
  'download_next': KidsTool.blocked,
  'find_subtitles': KidsTool.blocked,
  // Plex job titles name the items they work on.
  'list_jobs': KidsTool.blocked,
  // The memory holds what an adult of the household told Pleya: a children's
  // profile neither reads nor writes it.
  'recall_memory': KidsTool.blocked,
  'remember_fact': KidsTool.blocked,
  'forget_fact': KidsTool.blocked,
};

/// What a refused tool returns in kids mode.
const assistantKidsRefusal = <String, Object?>{
  'error': 'kids_mode_unsupported',
  'hint': 'For children Pleya only searches titles, trending titles and similar titles.',
};

/// The tools that stay open under [AssistantAgeGate.kidAudience] although
/// kids mode refuses them: they return no titles.
const kidAudienceOpenTools = {'recall_memory', 'remember_fact', 'forget_fact'};

/// The age every title must suit: the youngest child's on a children's
/// profile, else the youngest intended household child's when the question is
/// about the children, else null. Throws `kids_ages_unknown` when a children's
/// profile has no ages yet, `household_kids_unknown` when the household has
/// no valid child.
Future<int?> _kidsAge(AssistantToolContext ctx) async {
  if (ctx.ageGate == AssistantAgeGate.none) return null;
  if (ctx.ageGate == AssistantAgeGate.kidAudience) {
    // The question is about the household's children, on any profile.
    final age = ctx.audienceAge;
    if (age == null) throw const AssistantToolError('household_kids_unknown');
    return ctx.kidsAge = age;
  }
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
/// run can hold the answer to them. After the age gate, and only then, the
/// ask's standing filter drops what the profile watched or started (BP-11d).
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
  final List<(T, TitleFacts?)> passed;
  final Map<String, Object?> note;
  if (age == null) {
    passed = [for (final (i, r) in rows.indexed) (r, facts[i])];
    note = const <String, Object?>{};
  } else {
    passed = <(T, TitleFacts?)>[];
    for (final (i, r) in rows.indexed) {
      final f = facts[i] ?? const TitleFacts();
      if (AgeGate.allows(f, age, region)) {
        passed.add((r, facts[i]));
        ctx.ageAllowed.add((title: refs[i].title, year: refs[i].year));
      } else {
        ctx.ageRejected.add((title: clipText(refs[i].title), year: refs[i].year, reason: AgeGate.reason(f, region)));
      }
    }
    note = {'filtered_for_age': rows.length - passed.length, 'kids_age': age};
  }
  final unseen = await _dropSeen(ctx, passed, refOf);
  return (kept: unseen.kept, note: {...note, ...unseen.note}, region: () => region);
}

/// The compact facts for a row, or nothing when there are none.
Map<String, Object?> _factsField(TitleFacts? facts, String Function() region) => switch (facts?.toModelJson(region())) {
  final f? when f.isNotEmpty => {'facts': f},
  _ => const {},
};
