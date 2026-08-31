/// Films (hoofdstuk 10.2a of docs/tvos-unified-experience.md, [DEC-064]): the
/// discovery landing at the Films root, one level above the fase-5 complete
/// catalog `TvMoviesScreen` now sits behind.
///
/// A thin wrapper over `TvDiscoveryLandingScreen`, same reasoning as
/// `TvMoviesScreen` itself: everything but which rows and which heading is
/// shared with Series, and the shared screen owns it.
library;

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import 'tv_discovery_landing_screen.dart';
import 'tv_movies_screen.dart';

class TvMoviesLandingScreen extends StatelessWidget {
  const TvMoviesLandingScreen({super.key, this.onManageServers});

  /// Hoofdstuk 14.7's "Servers beheren", forwarded to both this landing's own
  /// activation and the fase-5 catalog behind "Alles bekijken".
  final VoidCallback? onManageServers;

  @override
  Widget build(BuildContext context) => TvDiscoveryLandingScreen(
    title: t.unifiedCatalog.moviesTitle,
    allTitle: t.unifiedCatalog.discovery.allMovies,
    viewAllSemanticLabel: t.unifiedCatalog.discovery.semantics.viewAllMovies,
    railsOf: (landing) => landing.movieRails,
    buildAllScreen: () => TvMoviesScreen(onManageServers: onManageServers),
    onManageServers: onManageServers,
  );
}
