/// Series (hoofdstuk 10.2a of docs/tvos-unified-experience.md, [DEC-064]): the
/// Films landing's counterpart, one level above the fase-5 complete catalog
/// `TvSeriesScreen` now sits behind. See `tv_movies_landing_screen.dart` for
/// why this is a thin wrapper.
library;

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import 'tv_discovery_landing_screen.dart';
import 'tv_series_screen.dart';

class TvSeriesLandingScreen extends StatelessWidget {
  const TvSeriesLandingScreen({super.key, this.onManageServers});

  /// Hoofdstuk 14.7's "Servers beheren", forwarded to both this landing's own
  /// activation and the fase-5 catalog behind "Alles bekijken".
  final VoidCallback? onManageServers;

  @override
  Widget build(BuildContext context) => TvDiscoveryLandingScreen(
    title: t.unifiedCatalog.seriesTitle,
    allTitle: t.unifiedCatalog.discovery.allSeries,
    viewAllSemanticLabel: t.unifiedCatalog.discovery.semantics.viewAllSeries,
    railsOf: (landing) => landing.seriesRails,
    buildAllScreen: () => TvSeriesScreen(onManageServers: onManageServers),
    onManageServers: onManageServers,
  );
}
