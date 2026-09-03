/// The routes that live *inside* Mijn Pleya on TV (hoofdstuk 18.2's function
/// mapping).
///
/// Its own file so [TvMyPleyaScreen] (which decides which tiles exist) and
/// [TvMyPleyaNavigator] (which decides what a tile opens) can share one
/// identity without either importing the other.
library;

import '../../i18n/strings.g.dart';

enum TvMyPleyaSection {
  watchlist,
  requests,
  downloads,
  libraries,
  servers,
  activity,
  // Fase 8: Watch Together's only entry point was the Home billboard's overlaid
  // action bar, which 33.1's composition does not have and hoofdstuk 7.3 left
  // on no focus path. Removing that bar without giving it a home would have
  // made a working feature unreachable on TV, so it moved to the destination
  // hoofdstuk 18 already defines as "everything personal that is not browsing".
  //
  // Pleya Remote deliberately did *not* come with it. On TV that action opened
  // the **host** surface (`RemoteSessionDialog`, via
  // `PlatformDetector.shouldActAsRemoteHost`) — pairing status, start/stop —
  // and a host surface has no screen form to push here; `MobileRemoteScreen` is
  // the *client*, which on a TV is the opposite role. Manufacturing the missing
  // screen is functional integration, which is fase 9. The gap is registered in
  // [DEC-070] rather than papered over with the wrong screen.
  watchTogether,
  settings,
  logs,
  about;

  /// The heading the section is pushed under. The tile's own title, so the two
  /// levels cannot end up naming the same place differently — the mistake fase
  /// 6 had to fix between the Films landing and its catalog.
  String get title => switch (this) {
    TvMyPleyaSection.watchlist => t.watchlist.title,
    TvMyPleyaSection.requests => t.seerr.title,
    TvMyPleyaSection.downloads => t.navigation.downloads,
    // `t.libraries.title`, not `t.navigation.libraries`. The two differ in
    // Dutch — the rail says "Media", the screen says "Bibliotheken" — and the
    // audit of 2 September 2026 counted three names on one place: a tile
    // reading Media, a screen heading reading Movies, and a concept called
    // Bibliotheken. The rail keeps its own short label; the tile takes the
    // name of the thing it opens.
    TvMyPleyaSection.libraries => t.libraries.title,
    TvMyPleyaSection.servers => t.tvMyPleya.servers,
    TvMyPleyaSection.activity => t.tvMyPleya.activity,
    TvMyPleyaSection.watchTogether => t.watchTogether.title,
    // `t.settings.title`, not `t.common.settings`. The two differ in Dutch,
    // "Instellingen" against "Opties", and the section page heading is the
    // screen's own name. Same rule as Bibliotheken one line up: the tile takes
    // the name of the thing it opens.
    TvMyPleyaSection.settings => t.settings.title,
    TvMyPleyaSection.logs => t.tvMyPleya.logs,
    TvMyPleyaSection.about => t.about.title,
  };

  /// A focus key for the tile that opens this section, so a pop can put the
  /// remote back exactly where it left (hoofdstuk 7.6).
  String get tileFocusKey => 'tvMyPleya_$name';
}
