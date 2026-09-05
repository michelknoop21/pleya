/// The navigation tab identifiers, on their own, with no Flutter import above
/// them.
///
/// Split out of `navigation_tabs.dart` so `automation_ids.dart` can name a tab
/// without dragging the widget tree along. `tool/generate_automation_ids_yaml.dart`
/// runs on the plain Dart VM, and a Flutter import there crashes the FFI
/// use-site transformer long before it reaches the catalogue. The full file
/// re-exports this one, so every existing import keeps working.
library;

/// Navigation tab identifiers.
///
/// Order here is not the display order (that is `allNavigationTabs`) and the
/// enum position is not persisted either: `EnumPref` serialises on `.name`, so
/// inserting a value cannot shift a stored `startup_section`.
enum NavigationTabId {
  discover,
  movies,
  series,
  libraries,
  liveTv,
  search,
  watchlist,
  requests,
  downloads,
  settings,
  myPleya,
}
