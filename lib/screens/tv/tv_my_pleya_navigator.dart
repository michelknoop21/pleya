/// Mijn Pleya's nested navigation (hoofdstuk 6.3).
///
/// ```
/// Mijn Pleya
///    └─ Bibliotheken
///        └─ Library detail
/// ```
///
/// Back inside Mijn Pleya returns to the hub first, and only a Back *at* the
/// hub reaches the root contract of hoofdstuk 7.5 — which is the whole point of
/// 6.3: it is more robust than switching the main tab to Settings and then
/// pretending with projection rules that Mijn Pleya is selected.
///
/// This file is the route table, not a second stack. The stack lives in
/// [TvNavigationCoordinator], shared with every other destination that opens
/// something above its root — "Alle films" and "Alle series" do the same thing
/// from the Films and Series landings, and hoofdstuk 33's shared shell is
/// binding on all eight references, so both have to keep the top navigation on
/// screen. One mechanism, one back chain, one place where "what is open inside
/// this destination" is answered. See [TvNestedRoute] for why that mechanism is
/// deliberately not a Flutter `Navigator`.
///
/// The stack is one level deep here on purpose. Every section is a screen that
/// owns its own depth already — Bibliotheken has its library detail,
/// Instellingen its sub-pages — and those pushes go to the profile navigator,
/// exactly as they do from the desktop rail today.
library;

import 'package:flutter/material.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../navigation/tv/tv_navigation_coordinator.dart';
import '../../watch_together/screens/watch_together_screen.dart';
import '../now_watching_screen.dart';
import '../downloads/downloads_screen.dart';
import '../libraries/libraries_screen.dart';
import '../seerr/seerr_discover_screen.dart';
import '../settings/about_screen.dart';
import '../settings/logs_screen.dart';
import '../settings/settings_screen.dart';
import '../watchlist_screen.dart';
import 'tv_my_pleya_sections.dart';
import 'tv_servers_screen.dart';

/// The nested route a Mijn Pleya tile opens.
///
/// Every one of these is a screen this app already shipped. Fase 7 adds no
/// feature here; it gives the rail rows and settings sub-pages of hoofdstuk
/// 18.2 a place on TV. [TvNestedRoute.restoreFocusKey] is the tile itself, so
/// popping puts the remote back where it was (hoofdstuk 7.6).
TvNestedRoute tvMyPleyaNestedRoute(TvMyPleyaSection section, {GlobalKey? librariesKey, GlobalKey? watchlistKey}) =>
    TvNestedRoute(
      id: 'tvMyPleya_${section.name}',
      restoreFocusKey: section.tileFocusKey,
      // Without a key the shell has nothing to ask where the focus belongs, and
      // a section opened on a remote with no focused element is a section you
      // cannot use. Bibliotheken reuses the key the hoofdstuk 6.4 adapter
      // already needs; Kijklijst reuses `MainScreen`'s own `_watchlistKey`, for
      // the same reason and because the route and the screens list have to
      // resolve to one `State`.
      //
      // The route *did* make a fresh `GlobalKey` here for every section — but
      // it made it for the route, and handed it to nothing: only Bibliotheken's
      // `builder` passed a key down to its screen. So `screenKey.currentState`
      // was permanently null for Kijklijst, which is the first of P5's four
      // stacked causes, and exactly what the comment above already warned
      // about.
      screenKey: switch (section) {
        TvMyPleyaSection.libraries => librariesKey,
        TvMyPleyaSection.watchlist => watchlistKey,
        _ => GlobalKey(debugLabel: 'tvMyPleya_${section.name}'),
      },
      // Addressable, and measurable. Without a node here the whole nested
      // surface was invisible to `/v1/ui_tree`: a scenario could press SELECT
      // on a tile and had no way to assert that anything opened, let alone
      // that it opened with the right page insets under the top bar. The
      // instance is the section name, matching the tile that opened it, so
      // `my_pleya.tile[settings]` and `my_pleya.section[settings]` name the
      // two ends of one journey.
      builder: (context) => AutomationNode(
        id: AutomationIds.myPleyaSection,
        instance: section.name,
        role: 'region',
        child: switch (section) {
          TvMyPleyaSection.watchlist => WatchlistScreen(key: watchlistKey),
          TvMyPleyaSection.requests => const SeerrDiscoverScreen(),
          TvMyPleyaSection.downloads => const DownloadsScreen(),
          // Keyed so the hoofdstuk 6.4 adapter can reach the same
          // `loadLibraryByKey` the rail's library rows have always called.
          // Keyed by the route's own `screenKey`, which for this section *is*
          // `librariesKey`; a second key here would leave one of them resolving
          // to nothing.
          TvMyPleyaSection.libraries => LibrariesScreen(key: librariesKey),
          TvMyPleyaSection.servers => const TvServersScreen(),
          TvMyPleyaSection.activity => const NowWatchingScreen(),
          TvMyPleyaSection.watchTogether => const WatchTogetherScreen(),
          TvMyPleyaSection.settings => const SettingsScreen(),
          TvMyPleyaSection.logs => const LogsScreen(),
          TvMyPleyaSection.about => const AboutScreen(),
        },
      ),
    );
