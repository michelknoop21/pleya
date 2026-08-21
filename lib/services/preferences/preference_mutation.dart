/// What happened to a preference key.
enum PreferenceOperation { set, remove }

/// Who caused it. The source decides three separate things that the old
/// key-only hook could not tell apart: whether the change may leave the device,
/// whether it counts as a deliberate user change for conflict resolution, and
/// whether it may echo back to the transport it came from.
enum PreferenceSource {
  /// The user changed something in the app.
  local,

  /// Applying a change that arrived from a transport. Never echoes back.
  remote,

  /// Moving a value from an old key or an old shape to a new one. A migration
  /// is bookkeeping, not a choice: it must not push, and it must not stamp a
  /// fresh user timestamp, or a device that upgrades later would look like the
  /// most recent editor of every setting it touches.
  migration,

  /// Restoring a settings export. Deliberate, so it stamps and it syncs, but it
  /// arrives as one batch to reconcile rather than as a burst of single writes.
  import,

  /// Resetting to defaults. Deliberate removal, so it must reach other devices
  /// as a removal instead of quietly reappearing on the next reconcile.
  reset,
}

/// One preference change, with everything the sync layer needs to route it.
class PreferenceMutation {
  const PreferenceMutation({required this.key, required this.operation, required this.source, this.value})
    : assert(operation == PreferenceOperation.remove || value != null, 'a set carries a value');

  const PreferenceMutation.set(this.key, this.value, {this.source = PreferenceSource.local})
    : operation = PreferenceOperation.set;

  const PreferenceMutation.remove(this.key, {this.source = PreferenceSource.local})
    : operation = PreferenceOperation.remove,
      value = null;

  /// The full SharedPreferences key, user prefix included.
  final String key;

  final PreferenceOperation operation;

  final PreferenceSource source;

  /// The written value, or null for a removal.
  final Object? value;

  /// Whether this counts as a deliberate user change, and therefore carries a
  /// fresh conflict timestamp. See [PreferenceSource.migration] for why the
  /// distinction is not cosmetic.
  bool get stampsUserChange => switch (source) {
    PreferenceSource.local || PreferenceSource.import || PreferenceSource.reset => true,
    PreferenceSource.migration || PreferenceSource.remote => false,
  };

  /// Whether this may be sent to a transport at all. A remote change is
  /// already there; a migration invented nothing new.
  bool get mayTravel => switch (source) {
    PreferenceSource.local || PreferenceSource.import || PreferenceSource.reset => true,
    PreferenceSource.migration || PreferenceSource.remote => false,
  };

  @override
  String toString() => 'PreferenceMutation(${operation.name} $key, ${source.name})';
}
