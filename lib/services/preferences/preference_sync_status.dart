/// What the engine is doing at this moment. Transient by definition.
enum PreferenceSyncActivity { idle, syncing }

/// Whether the engine can run at all. Changes only when the user or the system
/// changes it: the toggle, or iCloud being signed out.
enum PreferenceSyncAvailability { disabled, unavailable, ready }

/// What the last pass left unresolved. Persists across activity.
///
/// Severity is ordered, and raising a condition takes the maximum. A quota stop
/// will not resolve by trying again, so it outranks a failed write, which in
/// turn outranks a value that did not fit.
enum PreferenceSyncHealth { healthy, warning, error, quota }

int _severity(PreferenceSyncHealth health) => switch (health) {
  PreferenceSyncHealth.healthy => 0,
  PreferenceSyncHealth.warning => 1,
  PreferenceSyncHealth.error => 2,
  PreferenceSyncHealth.quota => 3,
};

/// The eight states the plan asks for, derived from the three axes rather than
/// stored. Nothing writes this directly, so nothing can overwrite a condition
/// by setting a state.
enum PreferenceSyncState { disabled, unavailable, idle, syncing, success, warning, error, quota }

/// Observable sync health.
///
/// Deliberately says nothing about other devices: a successful write to the
/// key-value store means the value left this device, not that anything received
/// it. There is no "all devices in sync", because the transport cannot know it.
///
/// The three axes are separate for one concrete reason. With a single `state`
/// field, a successful single write set `state = success` and the quota stop,
/// the transport error and the legacy-peer warning that were true a moment
/// earlier simply disappeared from the UI while still being true. Activity is
/// what the engine is doing, health is what the last pass left behind, and
/// compatibility is a property of the account, not of this run.
class PreferenceSyncStatus {
  const PreferenceSyncStatus({
    this.availability = PreferenceSyncAvailability.disabled,
    this.activity = PreferenceSyncActivity.idle,
    this.health = PreferenceSyncHealth.healthy,
    this.legacyPeerDetected = false,
    this.lastAttempt,
    this.lastSuccess,
    this.lastRemoteChange,
    this.pushed = 0,
    this.applied = 0,
    this.skipped = 0,
    this.oversize = 0,
    this.errorCategory,
  });

  final PreferenceSyncAvailability availability;
  final PreferenceSyncActivity activity;
  final PreferenceSyncHealth health;

  /// Another device on this iCloud account is still writing the v1 format.
  ///
  /// After the cutover the two formats no longer meet: this client neither
  /// writes v1 nor merges it, so an older Apple device keeps working but stops
  /// exchanging settings with this one. That boundary is deliberate, and this
  /// flag is what makes it visible instead of silent. It is a fact about the
  /// account, so it survives every success; it clears when the engine is torn
  /// down, not when a write happens to go well.
  final bool legacyPeerDetected;

  final DateTime? lastAttempt;
  final DateTime? lastSuccess;
  final DateTime? lastRemoteChange;
  final int pushed;
  final int applied;
  final int skipped;
  final int oversize;

  /// A category, never a message: an exception string can carry a URL or a
  /// token.
  final String? errorCategory;

  /// The single state the UI shows, derived from the axes above.
  PreferenceSyncState get state {
    switch (availability) {
      case PreferenceSyncAvailability.disabled:
        return PreferenceSyncState.disabled;
      case PreferenceSyncAvailability.unavailable:
        return PreferenceSyncState.unavailable;
      case PreferenceSyncAvailability.ready:
        break;
    }
    if (activity == PreferenceSyncActivity.syncing) return PreferenceSyncState.syncing;
    return switch (health) {
      PreferenceSyncHealth.quota => PreferenceSyncState.quota,
      PreferenceSyncHealth.error => PreferenceSyncState.error,
      PreferenceSyncHealth.warning => PreferenceSyncState.warning,
      PreferenceSyncHealth.healthy =>
        legacyPeerDetected
            ? PreferenceSyncState.warning
            : (lastSuccess == null ? PreferenceSyncState.idle : PreferenceSyncState.success),
    };
  }

  /// Whether anything is worth showing beyond "on".
  bool get needsAttention =>
      state == PreferenceSyncState.warning || state == PreferenceSyncState.error || state == PreferenceSyncState.quota;

  PreferenceSyncStatus copyWith({
    PreferenceSyncAvailability? availability,
    PreferenceSyncActivity? activity,
    PreferenceSyncHealth? health,
    bool? legacyPeerDetected,
    DateTime? lastAttempt,
    DateTime? lastSuccess,
    DateTime? lastRemoteChange,
    int? pushed,
    int? applied,
    int? skipped,
    int? oversize,
    String? errorCategory,
  }) => PreferenceSyncStatus(
    availability: availability ?? this.availability,
    activity: activity ?? this.activity,
    health: health ?? this.health,
    legacyPeerDetected: legacyPeerDetected ?? this.legacyPeerDetected,
    lastAttempt: lastAttempt ?? this.lastAttempt,
    lastSuccess: lastSuccess ?? this.lastSuccess,
    lastRemoteChange: lastRemoteChange ?? this.lastRemoteChange,
    pushed: pushed ?? this.pushed,
    applied: applied ?? this.applied,
    skipped: skipped ?? this.skipped,
    oversize: oversize ?? this.oversize,
    errorCategory: errorCategory ?? this.errorCategory,
  );

  /// A pass started.
  PreferenceSyncStatus starting(DateTime at) => copyWith(
    activity: PreferenceSyncActivity.syncing,
    lastAttempt: at,
    availability: PreferenceSyncAvailability.ready,
  );

  /// One value left the device. Says nothing about health: a single write
  /// succeeding does not mean the quota stop or the failed reconcile before it
  /// went away.
  PreferenceSyncStatus writeSucceeded(DateTime at) => copyWith(
    availability: PreferenceSyncAvailability.ready,
    activity: PreferenceSyncActivity.idle,
    lastSuccess: at,
    pushed: pushed + 1,
  );

  /// A full pass finished. This is the only thing entitled to clear health: it
  /// looked at everything, so what it did not find is genuinely gone.
  PreferenceSyncStatus reconcileSucceeded(
    DateTime at, {
    required int pushedCount,
    required int skippedCount,
    required int oversizeCount,
  }) => PreferenceSyncStatus(
    availability: PreferenceSyncAvailability.ready,
    activity: PreferenceSyncActivity.idle,
    health: oversizeCount > 0 ? PreferenceSyncHealth.warning : PreferenceSyncHealth.healthy,
    legacyPeerDetected: legacyPeerDetected,
    lastAttempt: lastAttempt,
    lastSuccess: at,
    lastRemoteChange: lastRemoteChange,
    pushed: pushed + pushedCount,
    applied: applied,
    skipped: skipped + skippedCount,
    oversize: oversize + oversizeCount,
    errorCategory: oversizeCount > 0 ? errorCategory : null,
  );

  /// A batch of remote records landed.
  PreferenceSyncStatus appliedRemote(DateTime at, {required int changed, required int skippedCount}) => copyWith(
    availability: PreferenceSyncAvailability.ready,
    activity: PreferenceSyncActivity.idle,
    lastSuccess: at,
    applied: applied + changed,
    skipped: skipped + skippedCount,
  );

  /// Raise a condition. Never lowers one: see [PreferenceSyncHealth].
  PreferenceSyncStatus raise(PreferenceSyncHealth condition, {String? errorCategory}) => copyWith(
    activity: PreferenceSyncActivity.idle,
    health: _severity(condition) > _severity(health) ? condition : health,
    errorCategory: errorCategory ?? this.errorCategory,
  );

  PreferenceSyncStatus sawLegacyPeer() => copyWith(legacyPeerDetected: true);

  /// The store spoke to us, so it is neither switched off nor signed out.
  PreferenceSyncStatus sawRemoteChange(DateTime at) =>
      copyWith(lastRemoteChange: at, availability: PreferenceSyncAvailability.ready);

  PreferenceSyncStatus countingSkipped(int n) => copyWith(skipped: skipped + n);
}
