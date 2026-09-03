/// Coverage bookkeeping for a [UnifiedMediaGroup]'s sources (hoofdstuk 4.2
/// and 12.8 of docs/tvos-unified-experience.md): did fase 2's
/// `resolveAllSourcesForGroup` ask every server that could plausibly hold
/// this title, and did they all answer.
///
/// The denominator is *expectation*, not what happened to answer — an
/// eligible server that is offline still belongs in [expectedServerIds], or
/// coverage would read as complete precisely when it is not (hoofdstuk 1.2's
/// `WatchlistAvailabilityResolver` establishes this same rule; this type
/// generalizes it for the all-source resolver rather than a single match).
library;

/// Why a server in a group's expected set did not contribute an answer.
enum UncheckedSourceReason {
  /// The server was offline (or not currently visible to the active profile)
  /// when the fan-out ran.
  offline,

  /// The server is reachable but rejected the request with an auth error.
  authError,

  /// The server looked reachable but the lookup itself failed (network
  /// error, timeout) — distinct from [offline] because the server's health
  /// status did not predict the failure.
  lookupFailed,
}

/// Whether every server a title could plausibly be on was actually asked.
///
/// [expectedServerIds] is every server eligible to answer — visible to the
/// active profile and on a backend with catalogue identity at all, online or
/// not. [checkedServerIds] is the subset that actually answered
/// `findAllByIdentity` without error; it is always a subset of
/// [expectedServerIds]. A server in the difference names why it did not
/// answer in [uncheckedReasons].
class SourceCoverageState {
  final Set<String> expectedServerIds;
  final Set<String> checkedServerIds;

  /// One entry per server in [expectedServerIds] that is not in
  /// [checkedServerIds]. A checked server never appears here.
  final Map<String, UncheckedSourceReason> uncheckedReasons;

  SourceCoverageState({
    required Set<String> expectedServerIds,
    required Set<String> checkedServerIds,
    Map<String, UncheckedSourceReason> uncheckedReasons = const {},
  }) : expectedServerIds = Set.unmodifiable(expectedServerIds),
       checkedServerIds = Set.unmodifiable(checkedServerIds),
       uncheckedReasons = Map.unmodifiable(uncheckedReasons) {
    assert(
      this.checkedServerIds.every(this.expectedServerIds.contains),
      'checkedServerIds must be a subset of expectedServerIds',
    );
    assert(
      this.uncheckedReasons.keys.every(
        (id) => this.expectedServerIds.contains(id) && !this.checkedServerIds.contains(id),
      ),
      'uncheckedReasons must only name expected, unchecked servers',
    );
  }

  /// Every expected server answered — the common case, and the only one
  /// [DataAggregationService]-style aggregation could ever produce before
  /// fase 2 (there was no concept of an unreachable *expected* server, only
  /// servers that happened to be online).
  factory SourceCoverageState.complete(Set<String> serverIds) =>
      SourceCoverageState(expectedServerIds: serverIds, checkedServerIds: serverIds);

  /// No server was eligible to be asked at all (e.g. an identity with
  /// nothing searchable). Vacuously complete, same as
  /// `WatchlistAvailabilityResolver` treating an empty eligible set as
  /// complete rather than as an unresolved gap.
  static final SourceCoverageState none = SourceCoverageState(expectedServerIds: const {}, checkedServerIds: const {});

  Set<String> get uncheckedServerIds => expectedServerIds.difference(checkedServerIds);

  int get uncheckedCount => uncheckedServerIds.length;

  bool get isComplete => uncheckedServerIds.isEmpty;

  @override
  String toString() => 'SourceCoverageState(${checkedServerIds.length}/${expectedServerIds.length} checked)';
}
