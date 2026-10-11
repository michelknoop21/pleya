import '../../database/app_database.dart';

/// Most facts one profile can hold.
const int kMemoryFactLimit = 200;

/// Longest fact, counted in Unicode code points.
const int kMemoryValueMaxLength = 200;

/// Budgets of [MemoryService.relevantFor]: the facts that ride along with one
/// question.
const int kMemoryRelevantMaxFacts = 8;

/// Counted in Unicode code points, not UTF-16 units: an emoji costs one. A
/// fact costs its reference, a space, its text and a line break. Whoever
/// builds the context line has to count the same way (`String.runes.length`,
/// not `String.length`).
const int kMemoryRelevantMaxChars = 600;

/// Largest body of a written overview, in UTF-8 bytes.
const int kMemoryOverviewMaxBytes = 16 * 1024;

/// Length of [MemoryFact.ref], the short handle the assistant refers to a fact
/// by.
const int kMemoryRefLength = 8;

/// Part of the overview hash. Raise it when the stored overview format
/// changes, so every saved overview counts as stale after the update.
const int kMemoryOverviewFormatVersion = 1;

enum MemoryCategory {
  preference('preference'),
  dislike('dislike'),
  household('household'),
  habit('habit'),
  other('other');

  const MemoryCategory(this.id);

  /// Stored form. Keep stable across renames.
  final String id;

  static MemoryCategory fromId(String id) =>
      MemoryCategory.values.firstWhere((c) => c.id == id, orElse: () => MemoryCategory.other);
}

enum MemorySource {
  userExplicit('user_explicit'),
  assistantConfirmed('assistant_confirmed'),
  settingsManual('settings_manual');

  const MemorySource(this.id);

  /// Stored form. Keep stable across renames.
  final String id;

  static MemorySource fromId(String id) =>
      MemorySource.values.firstWhere((s) => s.id == id, orElse: () => MemorySource.settingsManual);
}

/// Every outcome of a memory call. Callers branch on the code; the service
/// never returns free text.
enum MemoryCode {
  ok,

  /// `add` of a sentence this profile already holds; the existing fact comes
  /// back and no second row is written.
  exists,

  /// `update` to a sentence another fact of this profile already holds.
  duplicate,
  empty,
  tooLong,
  notSingleLine,
  controlCharacters,

  /// Children's ages have an owner already: the children's profile settings.
  ownedKidsAges,

  /// Audio and subtitle language have an owner already: the language settings.
  ownedLanguage,
  limitReached,

  /// No fact of this profile has that id or reference.
  notFound,

  /// A reference that matches more than one fact of this profile.
  ambiguous,

  /// The service was made without an active profile.
  noProfile,

  /// The profile of this service was deleted after the service was made.
  /// Nothing is written for it any more.
  profileGone,

  /// `saveOverview` with a hash this service did not hand out since the facts
  /// were last wiped: the overview was written from facts that are gone.
  staleHash,

  /// `saveOverview` with a body that is not a JSON object or is larger than
  /// [kMemoryOverviewMaxBytes].
  invalidOverview,

  /// The database refused the call. Nothing about the fact is logged or
  /// returned, only this code.
  storageFailed,
}

class MemoryFact {
  const MemoryFact({
    required this.id,
    required this.category,
    required this.value,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MemoryFact.fromRow(AssistantMemoryRow row) => MemoryFact(
    id: row.id,
    category: MemoryCategory.fromId(row.category),
    value: row.value,
    source: MemorySource.fromId(row.source),
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt, isUtc: true),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt, isUtc: true),
  );

  final String id;
  final MemoryCategory category;
  final String value;
  final MemorySource source;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The first [kMemoryRefLength] characters of [id].
  String get ref => id.length <= kMemoryRefLength ? id : id.substring(0, kMemoryRefLength);
}

class MemoryResult {
  const MemoryResult(this.code, [this.fact]);

  final MemoryCode code;

  /// The stored fact for [MemoryCode.ok] and [MemoryCode.exists], the deleted
  /// one after a delete, otherwise null.
  final MemoryFact? fact;

  bool get ok => code == MemoryCode.ok;
}

enum MemoryOverviewStatus {
  ok('ok'),
  failed('failed');

  const MemoryOverviewStatus(this.id);

  final String id;

  static MemoryOverviewStatus fromId(String id) => id == 'ok' ? MemoryOverviewStatus.ok : MemoryOverviewStatus.failed;
}

/// The stored overview of a profile's facts. Derived text: the facts stay the
/// truth.
class MemoryOverview {
  const MemoryOverview({
    required this.factsHash,
    required this.locale,
    required this.status,
    required this.body,
    required this.generatedAt,
  });

  factory MemoryOverview.fromRow(AssistantMemoryOverviewRow row) => MemoryOverview(
    factsHash: row.factsHash,
    locale: row.locale,
    status: MemoryOverviewStatus.fromId(row.status),
    body: row.body,
    generatedAt: DateTime.fromMillisecondsSinceEpoch(row.generatedAt, isUtc: true),
  );

  final String factsHash;
  final String locale;
  final MemoryOverviewStatus status;

  /// JSON with the sections and follow-up questions; empty for a failed
  /// attempt.
  final String body;
  final DateTime generatedAt;
}
