import '../services/memory/memory_service.dart';
import 'assistant_memory_intent.dart';

export '../services/memory/memory_models.dart';

/// The memory of one profile as an ask sees it: the service of the profile
/// session and a live look at which profile is active. A card that outlives a
/// profile switch writes nothing ([profileCurrent]), and neither does one that
/// waited while the profile became a children's profile ([kidsNow]).
class AssistantMemoryServices {
  const AssistantMemoryServices({required this.service, required this.activeProfileId, this.kidsProfile});

  final MemoryService service;

  /// The profile that is active right now, read live.
  final String? Function() activeProfileId;

  /// Whether the active profile is a children's profile, read live. Null is
  /// an adult profile.
  final Future<bool> Function()? kidsProfile;

  /// A children's profile right now: Big P reads and writes no memory.
  Future<bool> get kidsNow async => await kidsProfile?.call() ?? false;

  /// Whether the profile [service] belongs to is still the active one.
  bool get profileCurrent => service.profileId.isNotEmpty && activeProfileId() == service.profileId;
}

enum AssistantMemoryProposalKind { remember, replace, forget }

/// A write the model asked for that waits for the user's yes on a Pleya card.
/// Nothing is stored, replaced or removed before [applyMemoryProposal] runs.
/// [value] is the sentence as it would be stored, already checked by the
/// service's own validation; [target] is the fact that disappears.
class AssistantMemoryProposal {
  const AssistantMemoryProposal({
    required this.kind,
    required this.memory,
    this.value,
    this.category,
    this.target,
    this.excludeSeen = false,
  });

  final AssistantMemoryProposalKind kind;

  /// The memory of the profile the proposal was made for.
  final AssistantMemoryServices memory;
  final String? value;
  final MemoryCategory? category;
  final MemoryFact? target;

  /// Pleya's own card for the standing "nothing I watched or started"
  /// (BP-11d): a yes also turns the preference on.
  final bool excludeSeen;

  bool sameAs(AssistantMemoryProposal other) =>
      kind == other.kind &&
      value == other.value &&
      category == other.category &&
      target?.id == other.target?.id &&
      excludeSeen == other.excludeSeen;
}

/// What became of a proposal or a direct save. [code] is `ok` or the fixed
/// reason nothing changed; never text from a fact or an error.
class AssistantMemoryOutcome {
  const AssistantMemoryOutcome(this.kind, this.code, [this.fact]);

  final AssistantMemoryProposalKind kind;
  final String code;

  /// The stored fact, or the removed one after a forget.
  final MemoryFact? fact;

  bool get ok => code == 'ok';
}

/// The memory state of one ask. Made by the run before the first model call,
/// never copied to another ask.
class AssistantMemoryTurn {
  AssistantMemoryTurn({this.enabled = false, this.typedFact, this.typedKnown = false, this.kidsTyped = false});

  /// The memory is on for this profile and it is no children's profile: the
  /// tools are offered.
  final bool enabled;

  /// The user's own typed words after "onthoud dat", as a sentence
  /// ([assistantMemoryTypedFact]), or null when the question was no such
  /// request, was not typed, named no fact or runs fenced. Decided by code
  /// from the user's words.
  final String? typedFact;

  /// A typed "onthoud dat ..." on a children's profile, which keeps no memory:
  /// Pleya says so itself, the model's words never reach the user (BP-11h).
  final bool kidsTyped;

  /// [typedFact] was in the memory of this profile before this ask stored
  /// anything: read when the ask began, or reported by the save itself.
  bool typedKnown;

  /// Tool calls of this ask so far, the one in progress included. The run
  /// counts them.
  int calls = 0;

  /// The model asked to remember a fact in this ask, whatever came of it.
  bool asked = false;

  /// The one direct save of this ask was spent, stored or not.
  bool directUsed = false;

  /// The sentence to store at once, or null when the write waits for a yes on
  /// a card. It is always [typedFact], the user's own typed words, and never
  /// the model's wording: the `value` the model passes is not read for a
  /// direct save. A sentence is stored at once when all of these hold:
  ///
  /// * the typed question was an explicit request that names a fact
  ///   ([typedFact]);
  /// * this is the first tool call of the ask, so no tool result (a web
  ///   page, a title description) was in the model's context;
  /// * no direct save was spent yet.
  ///
  /// Known limit: the category of a fact stored at once is the model's choice.
  String? get directFact => calls == 1 && !directUsed ? typedFact : null;

  /// Writes waiting for a yes, in the order the model asked for them.
  final List<AssistantMemoryProposal> proposals = [];

  /// What this ask stored directly: at most one fact.
  final List<MemoryFact> stored = [];

  /// Why the typed words were not stored at once, or null: an age, a language
  /// preference, too long, the memory full. Pleya says so in its own line.
  MemoryCode? refused;

  /// Pleya itself stored or proposed the standing "nothing I watched or
  /// started" this ask (BP-11d): a remember_fact of the model is not a second
  /// card for the same wish.
  bool standingHandled = false;

  static const int maxProposals = 3;
}

/// The fixed code a tool or a card reports for [code].
String assistantMemoryCode(MemoryCode code) => switch (code) {
  MemoryCode.ok => 'ok',
  MemoryCode.exists => 'already_known',
  MemoryCode.duplicate => 'duplicate',
  MemoryCode.empty => 'empty',
  MemoryCode.tooLong => 'too_long',
  MemoryCode.notSingleLine => 'not_single_line',
  MemoryCode.controlCharacters => 'control_characters',
  MemoryCode.ownedKidsAges => 'owned_by_kids_ages_setting',
  MemoryCode.ownedLanguage => 'owned_by_language_setting',
  MemoryCode.limitReached => 'memory_full',
  MemoryCode.notFound => 'unknown_ref',
  MemoryCode.ambiguous => 'ambiguous_ref',
  MemoryCode.noProfile => 'no_profile',
  MemoryCode.profileGone => 'profile_changed',
  MemoryCode.staleHash || MemoryCode.invalidOverview || MemoryCode.storageFailed => 'storage_failed',
};

/// Carries out [proposal] after the user's yes. The profile the proposal was
/// made for must still be the active one, its memory still on and it must be
/// no children's profile; the fact that disappears must still be the one the
/// card showed (same text, category and change time). Otherwise nothing is
/// written and the code says why.
Future<AssistantMemoryOutcome> applyMemoryProposal(AssistantMemoryProposal proposal) async {
  final memory = proposal.memory;
  final kind = proposal.kind;
  if (!await memory.service.enabled) return AssistantMemoryOutcome(kind, 'memory_off');
  if (await memory.kidsNow) return AssistantMemoryOutcome(kind, 'kids_mode_unsupported');
  final target = proposal.target;
  if (target != null) {
    // The card is a snapshot: read what is there now.
    final now = await memory.service.resolve(target.id);
    final fact = now.fact;
    final same =
        fact != null &&
        fact.value == target.value &&
        fact.category == target.category &&
        fact.updatedAt == target.updatedAt;
    if (now.code == MemoryCode.notFound || (now.ok && !same)) return AssistantMemoryOutcome(kind, 'target_changed');
    if (!now.ok) return AssistantMemoryOutcome(kind, assistantMemoryCode(now.code));
  }
  // After the last await before the write: a card can outlive a profile switch.
  if (!memory.profileCurrent) return AssistantMemoryOutcome(kind, 'profile_changed');
  final value = proposal.value;
  final category = proposal.category;
  final MemoryResult result;
  switch (kind) {
    case AssistantMemoryProposalKind.remember:
      if (value == null || category == null) return AssistantMemoryOutcome(kind, 'invalid');
      result = await memory.service.add(value: value, category: category, source: MemorySource.assistantConfirmed);
    case AssistantMemoryProposalKind.replace:
      if (target == null || value == null) return AssistantMemoryOutcome(kind, 'invalid');
      result = await memory.service.update(
        target.id,
        value: value,
        category: category,
        source: MemorySource.assistantConfirmed,
      );
    case AssistantMemoryProposalKind.forget:
      if (target == null) return AssistantMemoryOutcome(kind, 'invalid');
      result = await memory.service.delete(target.id);
  }
  // The same sentence was stored in the meantime: it is remembered.
  final done = result.ok || (kind == AssistantMemoryProposalKind.remember && result.code == MemoryCode.exists);
  if (done && proposal.excludeSeen) await memory.service.setExcludeSeen(true);
  return AssistantMemoryOutcome(kind, done ? 'ok' : assistantMemoryCode(result.code), result.fact);
}

final RegExp _hidden = RegExp(r'[\p{Cc}\p{Cf}︀-️\u{E0100}-\u{E01EF}]', unicode: true);

/// [value] as the model gets it: without control characters, format
/// characters (zero width, direction marks, the tag block U+E0000 to U+E007F)
/// and variation selectors. The stored fact keeps what the user typed; what
/// leaves for the model shows exactly what the user sees.
String assistantMemoryText(String value) => value.replaceAll(_hidden, '').replaceAll(RegExp(r'\s+'), ' ').trim();
