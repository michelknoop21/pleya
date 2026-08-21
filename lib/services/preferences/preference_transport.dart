/// A remote change seen by a transport.
class RemotePreferenceChange {
  const RemotePreferenceChange({required this.reason, this.changedKeys = const []});

  final RemoteChangeReason reason;

  /// Cloud keys that changed. Empty for [RemoteChangeReason.accountChanged] and
  /// [RemoteChangeReason.quotaExceeded], which say nothing about individual
  /// keys.
  final List<String> changedKeys;
}

enum RemoteChangeReason { serverChange, initialSync, quotaExceeded, accountChanged }

/// The seam between the preference engine and whatever carries the bytes.
///
/// Everything above this line is transport-agnostic: policy, scope, conflict
/// resolution, status. Everything below it is plumbing. There was no such seam
/// before: `ICloudSyncService` reached straight for a `MethodChannel`, so a
/// second transport had nothing to plug into.
///
/// A transport knows about keys and encoded strings. It does not know what a
/// profile is, which key may sync, or how to settle a conflict.
abstract class PreferenceTransport {
  String get name;

  /// Whether the backing store can be used right now. False when iCloud is
  /// signed out, or the platform has no implementation.
  Future<bool> isAvailable();

  /// Full contents, or null when the read failed.
  ///
  /// The distinction is not cosmetic and callers must respect it: absent-from-
  /// the-map means "removed remotely" only when the read actually succeeded.
  /// Treating a failed read as an empty store is how a transient channel error
  /// turns into a wiped account.
  Future<Map<String, String>?> readAll();

  Future<void> write(String key, String encoded);

  Future<void> remove(String key);

  /// Best-effort push of pending changes. Never required for correctness.
  Future<void> flush();

  /// Remote changes, including the reasons that carry no key list.
  Stream<RemotePreferenceChange> get changes;

  /// Per-value size limit, or null when the transport has none.
  int? get maxValueBytes;

  Future<void> dispose();
}
