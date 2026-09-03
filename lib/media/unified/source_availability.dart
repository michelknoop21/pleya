/// Whether one concrete source can actually be used right now (hoofdstuk 4.2
/// of docs/tvos-unified-experience.md, which names `SourceAvailability` as
/// part of `UnifiedMediaSource`).
///
/// Fase 1 deferred this field because it needs live server state, and fase 2
/// built coverage at the *group* level ([SourceCoverageState]) and
/// reachability at the *resolver* level (`EligibleSourceServer`) instead —
/// neither of which answers "may I offer this row to the user". Fase 4's
/// activation coordinator and source picker both need exactly that per row,
/// so the field lands here.
///
/// [authError] is deliberately not folded into [offline]. Hoofdstuk 14.7
/// requires a different message for the two ("Opnieuw aanmelden vereist"
/// versus an offline state), and a user can fix an auth error in place while
/// an offline server is out of their hands.
library;

enum SourceAvailability {
  /// The owning server is reachable and this source can be played or opened.
  online,

  /// The owning server is not currently reachable.
  offline,

  /// The owning server answered, but rejected the request (401/403).
  authError,

  /// Server state has not been established yet. Distinct from [offline]: a
  /// source built from a catalogue page nobody has re-checked is not known to
  /// be unreachable, it is simply unasked.
  unknown,
}

extension SourceAvailabilityUsability on SourceAvailability {
  /// Whether activation may route to this source without further checks.
  ///
  /// Only [online] qualifies. [unknown] deliberately does not: hoofdstuk 4.4
  /// puts source choice *before* the existing route, so handing the player a
  /// source whose server was never confirmed would move the failure into the
  /// player, which is the one place hoofdstuk 4.4 keeps free of this logic.
  bool get isUsable => this == SourceAvailability.online;

  /// Rank within tier 2 of hoofdstuk 4.7's deterministic order ("online
  /// state"). Lower sorts first.
  ///
  /// 4.7 fixes that online outranks not-online but does not order the
  /// not-online states among themselves; ordering them here rather than
  /// leaving it to map iteration is what keeps the whole comparator total.
  /// [authError] precedes [offline] because it is the one a user can act on
  /// without leaving the room.
  int get rank => switch (this) {
    SourceAvailability.online => 0,
    SourceAvailability.unknown => 1,
    SourceAvailability.authError => 2,
    SourceAvailability.offline => 3,
  };
}
