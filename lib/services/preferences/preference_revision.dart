/// A synced preference value plus the metadata needed to settle a conflict.
///
/// v1 carried the bare value, so reconcile could only pick by arrival order:
/// change a setting on a laptop while it is offline, and whichever device
/// happened to write to iCloud last won, regardless of who changed it more
/// recently. That is a race, not a rule.
///
/// The envelope makes `replace` deterministic. [updatedAt] is the moment of the
/// last deliberate user change, [deviceId] breaks a tie so two devices reach
/// the same verdict rather than overwriting each other back and forth, and
/// [deleted] is a tombstone so a removal is not resurrected by an older
/// snapshot that still holds the value.
///
/// The limit is stated rather than papered over: this is client-side
/// last-writer-wins, so it trusts the device clock. A TV with a wrong clock
/// wins or loses unfairly. A server-ordered revision needs a server, which is
/// the Pleya Server transport, not this one.
///
/// The wire format itself lives in `PreferenceSyncCoordinator` (DEC-133); this
/// class holds the comparison both sides of it share.
class PreferenceRevision {
  const PreferenceRevision({required this.value, required this.updatedAt, required this.deviceId, this.deleted = false})
    : assert(deleted || value != null, 'a live revision carries a value');

  /// The stored preference value: bool, int, double, String or List&lt;String&gt;.
  /// Null exactly when [deleted].
  final Object? value;

  /// Milliseconds since epoch, UTC, of the last deliberate user change.
  final int updatedAt;

  /// Stable per-installation identifier of the device that made that change.
  final String deviceId;

  /// This key was removed. The record stays so the removal can travel.
  final bool deleted;

  PreferenceRevision asTombstone({required int at, required String by}) =>
      PreferenceRevision(value: null, updatedAt: at, deviceId: by, deleted: true);

  /// Deterministic last-writer-wins.
  ///
  /// Newer [updatedAt] wins. On an exact tie the higher [deviceId] wins, which
  /// is arbitrary but identical on both devices, so they converge instead of
  /// ping-ponging. A tombstone does not get special treatment beyond its
  /// timestamp: deleting at 10:00 and re-adding at 10:05 keeps the value.
  bool winsOver(PreferenceRevision other) => stampWins(
    at: updatedAt,
    device: deviceId,
    deleted: deleted,
    overAt: other.updatedAt,
    overDevice: other.deviceId,
    overDeleted: other.deleted,
  );

  /// The rule behind [winsOver], on bare stamps. The coordinator compares a
  /// wire record against a stored stamp without having a value for either side
  /// at hand, and a live [PreferenceRevision] insists on one.
  static bool stampWins({
    required int at,
    required String device,
    required bool deleted,
    required int overAt,
    required String overDevice,
    required bool overDeleted,
  }) {
    if (at != overAt) return at > overAt;
    if (device != overDevice) return device.compareTo(overDevice) > 0;
    // Same instant, same device: prefer the tombstone, so a remove that
    // arrives alongside its own set does not leave the value behind.
    return deleted && !overDeleted;
  }

  /// Pick the surviving revision. Returns [b] only when it strictly wins, so
  /// resolving is stable when called repeatedly.
  static PreferenceRevision resolve(PreferenceRevision a, PreferenceRevision b) => b.winsOver(a) ? b : a;

  @override
  bool operator ==(Object other) =>
      other is PreferenceRevision &&
      other.updatedAt == updatedAt &&
      other.deviceId == deviceId &&
      other.deleted == deleted &&
      _sameValue(other.value, value);

  static bool _sameValue(Object? a, Object? b) {
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }
    return a == b;
  }

  @override
  int get hashCode => Object.hash(updatedAt, deviceId, deleted, value is List ? Object.hashAll(value as List) : value);

  @override
  String toString() => 'PreferenceRevision(${deleted ? 'deleted' : value}, t: $updatedAt, d: $deviceId)';
}
