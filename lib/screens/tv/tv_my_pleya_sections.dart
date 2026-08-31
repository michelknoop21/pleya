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
    TvMyPleyaSection.libraries => t.navigation.libraries,
    TvMyPleyaSection.servers => t.tvMyPleya.servers,
    TvMyPleyaSection.activity => t.tvMyPleya.activity,
    TvMyPleyaSection.settings => t.common.settings,
    TvMyPleyaSection.logs => t.tvMyPleya.logs,
    TvMyPleyaSection.about => t.about.title,
  };

  /// A focus key for the tile that opens this section, so a pop can put the
  /// remote back exactly where it left (hoofdstuk 7.6).
  String get tileFocusKey => 'tvMyPleya_$name';
}
