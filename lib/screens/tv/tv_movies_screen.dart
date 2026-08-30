/// Films (hoofdstuk 10.1 of docs/tvos-unified-experience.md): every visible
/// movie library on every visible server, as one catalog.
///
/// A thin wrapper, and deliberately so. Films and Series differ in which
/// [MediaKind] they browse and what the heading says; everything else is
/// contract-identical, and the shared screen owns it. Two full screens would
/// drift on their first bug fix.
///
/// The catalog itself comes from [UnifiedCatalogs] in the profile subtree, not
/// from here — see that class for why it outlives this widget.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../providers/unified_catalogs.dart';
import 'tv_unified_catalog_screen.dart';

class TvMoviesScreen extends StatelessWidget {
  const TvMoviesScreen({super.key, this.onManageServers});

  /// Hoofdstuk 14.7's "Servers beheren", which only the root shell can do.
  final VoidCallback? onManageServers;

  @override
  Widget build(BuildContext context) => TvUnifiedCatalogScreen(
    catalog: context.read<UnifiedCatalogs>().movies,
    title: t.unifiedCatalog.moviesTitle,
    onManageServers: onManageServers,
  );
}
