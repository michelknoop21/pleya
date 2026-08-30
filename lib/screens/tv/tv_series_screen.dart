/// Series (hoofdstuk 10.1 of docs/tvos-unified-experience.md): every visible
/// show library on every visible server, as one catalog.
///
/// The Series counterpart of `tv_movies_screen.dart`, and the same thin
/// wrapper for the same reason. Note the card treatment is identical to Films':
/// hoofdstuk 10.2 specifies 2:3 posters for *both* pages, and 33.3 marks the
/// Series mockup's landscape clearlogo cards as richtinggevend rather than
/// binding precisely so the two grids keep one rhythm.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../providers/unified_catalogs.dart';
import 'tv_unified_catalog_screen.dart';

class TvSeriesScreen extends StatelessWidget {
  const TvSeriesScreen({super.key, this.onManageServers});

  /// Hoofdstuk 14.7's "Servers beheren", which only the root shell can do.
  final VoidCallback? onManageServers;

  @override
  Widget build(BuildContext context) => TvUnifiedCatalogScreen(
    catalog: context.read<UnifiedCatalogs>().shows,
    title: t.unifiedCatalog.seriesTitle,
    onManageServers: onManageServers,
  );
}
