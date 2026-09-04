/// Navigation tab identifiers.
///
/// Order here is not the display order (that is `allNavigationTabs`) and the
/// enum position is not persisted either: `EnumPref` serialises on `.name`, so
/// inserting a value cannot shift a stored `startup_section`.
///
/// **This file must not import anything.** It lives apart from
/// `navigation_tabs.dart`, which is a widget file, so that
/// `lib/automation/automation_ids.dart` can name a tab without dragging in
/// Flutter. `tool/generate_automation_ids_yaml.dart` runs on the standalone
/// Dart VM, and that VM cannot compile the Flutter framework at all: its FFI
/// use-site transformer throws `type 'InvalidType' is not a subtype of type
/// 'FunctionType'` on any program that imports `package:flutter`. Adding an
/// import here breaks the generator, and
/// `test/architecture/automation_ids_generator_test.dart` fails when it does.
///
/// `navigation_tabs.dart` re-exports this, so importing either one still
/// gives you the enum.
enum NavigationTabId {
  discover,
  movies,
  series,
  books,
  libraries,
  liveTv,
  search,
  watchlist,
  requests,
  downloads,
  settings,
  myPleya,
}
