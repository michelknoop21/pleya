import '../navigation/navigation_tabs.dart';

/// Stable, agent-addressable automation IDs on a closed set of domains:
/// `screen`, `nav`, `sidebar`, `library`, `discover`, `detail`, `player`,
/// `search`, `settings`, `dialog`, `sheet`, `hub`, `profile`, `overlay`.
///
/// Every automation ID in the app is either a literal here, or the output of
/// [navTab] — never a raw string literal at the call site. Enforced by
/// test/architecture/automation_ids_test.dart.
class AutomationIds {
  AutomationIds._();

  /// `nav.<NavigationTabId.name>` — derived from the enum itself, not a
  /// second hand-written list that could drift out of sync with it.
  static String navTab(NavigationTabId id) => 'nav.${id.name}';

  static const String screenMain = 'screen.main';
  static const String screenDiscover = 'screen.discover';
  static const String screenLibraries = 'screen.libraries';
  static const String screenMediaDetail = 'screen.media_detail';

  /// The static, autoritative id catalogue `GET /v1/automation_ids` serves.
  /// Deliberately not a dump of [AutomationRegistry]'s live-mounted nodes —
  /// that registry only ever holds whatever screen happens to be on screen,
  /// while a scenario needs the full, screen-independent set. Grows in step
  /// with the consts above; instance-suffixed ids (`library.grid.item[n]`
  /// and friends) and their `instanceable` metadata land with the Fase 5
  /// id rollout.
  static List<Map<String, Object?>> catalog() => [
    {'id': screenMain, 'role': 'screen'},
    {'id': screenDiscover, 'role': 'screen'},
    {'id': screenLibraries, 'role': 'screen'},
    {'id': screenMediaDetail, 'role': 'screen'},
    for (final tab in NavigationTabId.values) {'id': navTab(tab), 'role': 'nav'},
  ];
}
