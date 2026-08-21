import 'dart:async';

/// Derived runtime state that a preference change invalidates.
///
/// A remote apply writes to `SharedPreferences`, and that is where it used to
/// stop. Everything downstream had already read the old value into a provider:
/// `HiddenLibrariesProvider` cached its set at construction,
/// `HomeLayoutProvider` guarded itself with `if (_isInitialized) return`, and
/// `LibrariesProvider` baked the order into its list. So the value in the store
/// was right and the screen was wrong until the app restarted.
///
/// Naming the families is what makes the invalidation targeted. Nothing here
/// rebuilds the app; each provider reloads its own slice.
enum PreferenceRefreshFamily {
  /// Which libraries are hidden.
  hiddenLibraries,

  /// The order libraries appear in.
  libraryOrder,

  /// Per-library filters, sort, grouping and the selected tab.
  libraryView,

  /// Home row order and hidden home rows.
  homeLayout,
}

/// Where invalidations are announced.
///
/// A stream rather than a callback list because the consumers are providers
/// with their own lifecycles: a profile switch throws the whole provider tree
/// away and builds a new one, and a subscription that is cancelled with its
/// provider cannot leak into the next.
class PreferenceRefreshBus {
  PreferenceRefreshBus();

  static final PreferenceRefreshBus instance = PreferenceRefreshBus();

  final StreamController<Set<PreferenceRefreshFamily>> _controller =
      StreamController<Set<PreferenceRefreshFamily>>.broadcast();

  Stream<Set<PreferenceRefreshFamily>> get changes => _controller.stream;

  /// Announce that [families] are stale. A no-op when nothing is stale, so
  /// callers can pass whatever a batch produced without filtering first.
  void invalidate(Set<PreferenceRefreshFamily> families) {
    if (families.isEmpty || _controller.isClosed) return;
    _controller.add(Set.unmodifiable(families));
  }

  /// Everything is stale: an import or a reset rewrote local state wholesale.
  void invalidateAll() => invalidate(PreferenceRefreshFamily.values.toSet());

  Future<void> dispose() => _controller.close();
}
