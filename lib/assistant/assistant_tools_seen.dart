part of 'assistant_tools.dart';

// What the profile watched or started, read once per ask: the log keys and
// identities of the personal services (my_watching's "seen before") and, for
// a title tool's standing filter (BP-11d), the server's own watch state on the
// row. The filter runs in [_gateTitles] after the age gate: a dropped title
// never reaches the model or a card, and the answer may not name it.

/// The standing "nothing I watched or started" of one ask (BP-11d). Set by
/// the run from the question, the conversation and the saved preference;
/// never by the model.
class AssistantSeenFilter {
  AssistantSeenFilter({this.on = false, this.prompt = ''});

  /// Title tools leave out what the profile watched or started.
  final bool on;

  /// The question as typed: a title the user names there is a lookup, not a
  /// suggestion, and is never dropped.
  final String prompt;

  /// The titles the filter dropped this ask: the answer may not name them.
  final List<({String title, int? year})> dropped = [];

  /// Pleya's line replaced the model's answer: it kept naming a dropped title.
  bool notice = false;

  Future<_SeenLog>? _log;
}

/// The profile's log as one lookup: global keys, identities for a copy on
/// another server, and titles for a row without a library copy.
class _SeenLog {
  _SeenLog(this.keys, List<WatchedIdentity> identities)
    : _identities = _SeenIdentities(identities),
      _titles = [
        for (final w in identities)
          if (w.title case final t?) (key: assistantTitleKey(t), year: w.year, show: w.show),
      ];

  static final empty = _SeenLog(const {}, const []);

  final Set<String> keys;
  final _SeenIdentities _identities;
  final List<({String key, int? year, bool show})> _titles;

  /// [item] is in the log, by key or by identity.
  bool logged(MediaItem item) => keys.contains(item.globalKey) || _identities.contains(item);

  /// Watched or started: in the log, or so marked by its server.
  bool item(MediaItem item) => item.isWatched || item.hasActiveProgress || item.isPartiallyWatched || logged(item);

  /// A row without a library copy: same title and kind, and the year when
  /// both sides know it.
  bool title(String title, int? year, {required bool show}) {
    final key = assistantTitleKey(title);
    return key.isNotEmpty &&
        _titles.any((t) => t.key == key && t.show == show && (t.year == null || year == null || t.year == year));
  }
}

Future<_SeenLog> _readSeenLog(AssistantToolContext ctx) async {
  final personal = ctx.personal;
  if (personal == null) return _SeenLog.empty;
  try {
    final (keys, identities) = await (personal.everSeen(), personal.everSeenIdentities()).wait;
    return _SeenLog(keys, identities);
  } catch (e) {
    // The server's own watch state on each row still counts.
    appLogger.d('Assistant: seen log unavailable', error: e.runtimeType);
    return _SeenLog.empty;
  }
}

/// Whether the user named [title] in the question itself: two words, or one
/// of five letters or more, so "it" or "up" in a sentence is no title.
bool _typedTitle(String prompt, String title) {
  if (prompt.isEmpty) return false;
  final text = ' ${assistantPlainWords(prompt)} ';
  return assistantTitleWords(title).any((w) => (w.contains(' ') || w.length >= 5) && text.contains(' $w '));
}

/// Whether the ask's filter drops [item]: on, in the log or watched or started
/// on its server, and not a title the user typed. The drop is remembered.
bool _dropSeenItem(AssistantToolContext ctx, _SeenLog log, MediaItem item) {
  final filter = ctx.seenFilter;
  if (!filter.on || !log.item(item) || _typedTitle(filter.prompt, item.title ?? '')) return false;
  filter.dropped.add((title: clipText(item.title), year: item.year));
  return true;
}

/// [kept] without what the profile watched or started, when the ask's
/// standing filter is on. Dropped titles are remembered on the filter.
Future<({List<(T, TitleFacts?)> kept, Map<String, Object?> note})> _dropSeen<T>(
  AssistantToolContext ctx,
  List<(T, TitleFacts?)> kept,
  TitleRef Function(T row) refOf,
) async {
  final filter = ctx.seenFilter;
  if (!filter.on || kept.isEmpty) return (kept: kept, note: const <String, Object?>{});
  final log = await (filter._log ??= _readSeenLog(ctx));
  final out = <(T, TitleFacts?)>[];
  for (final entry in kept) {
    final ref = refOf(entry.$1);
    final item = ref.item;
    final seen = item != null ? log.item(item) : log.title(ref.title, ref.year, show: ref.kind == TmdbKind.tv);
    if (seen && !_typedTitle(filter.prompt, ref.title)) {
      filter.dropped.add((title: clipText(ref.title), year: ref.year));
    } else {
      out.add(entry);
    }
  }
  return (kept: out, note: {'filtered_seen': kept.length - out.length});
}

/// The titles of the profile's log by identity. A candidate is seen when it
/// shares a token (guid or external id) with one, or, when neither side
/// contradicts the other with a different external id, has the same kind,
/// title and a year known on both sides: a year that is missing is no match,
/// so "The Office" does not hide its namesake across a year-less log.
class _SeenIdentities {
  _SeenIdentities(List<WatchedIdentity> seen) {
    for (final w in seen) {
      tokens.addAll(w.tokens);
      final title = w.title;
      if (title != null && w.year != null) (byTitle[assistantTitleKey(title)] ??= []).add(w);
    }
  }

  final Set<String> tokens = {};
  final Map<String, List<WatchedIdentity>> byTitle = {};

  bool contains(MediaItem item) {
    final identity = interactionIdentityOf(item);
    if (interactionIdentityProves(identity.tokens, tokens)) return true;
    final title = identity.title;
    // An episode's own year is not its series'.
    final year = item.kind == MediaKind.episode ? null : item.year;
    if (title == null || year == null) return false;
    return (byTitle[assistantTitleKey(title)] ?? const []).any(
      (w) =>
          w.show == item.kind.isShowRelated &&
          w.year == year &&
          !interactionIdentityConflicts(identity.tokens, w.tokens),
    );
  }
}
