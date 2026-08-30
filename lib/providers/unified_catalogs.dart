/// Profile-scoped owner of the two unified catalogs Films and Series browse
/// (hoofdstuk 10.1 of docs/tvos-unified-experience.md: "Films toont standaard
/// alle zichtbare filmlibraries … Series toont alle zichtbare serielibraries").
///
/// ## Why an owner object rather than two providers
///
/// Films and Series need two independent [UnifiedCatalogProvider] instances —
/// separate queries, separate merges, separate paging positions. Registering
/// two of the same type side by side in one `MultiProvider` would make
/// `context.read<UnifiedCatalogProvider>()` ambiguous: whichever registration
/// happens to be nearest wins, and neither call site says which catalog it
/// meant. Subclassing purely to split the lookup type would move that
/// ambiguity into the reader's head instead of removing it, and would buy
/// nothing here — the shared catalog screen takes its provider as a
/// constructor argument either way, because it is deliberately kind-agnostic.
///
/// So the identity lives at the access site: `catalogs.movies`,
/// `catalogs.shows`. One `Provider<UnifiedCatalogs>` registration, two named
/// catalogs, no type gymnastics.
///
/// ## Lifecycle
///
/// Registered inside the profile-keyed subtree (`ProfileSessionScreen`) beside
/// `LibrariesProvider`, so hoofdstuk 22's "dispose unified providers on profile
/// switch" happens by construction: the `KeyedSubtree` tears the provider down
/// and [dispose] fans out to whichever catalogs were built.
///
/// Lazy at two levels, which is the point of the `??=`. Building this object
/// creates neither catalog, so a profile that never opens Series never
/// constructs one; and each [UnifiedCatalogProvider] is itself lazy, doing no
/// network work until a screen calls `ensureStarted`. A Films-only profile
/// therefore pays for exactly one catalog, and an offline start pays for none.
///
/// Because this sits *above* the tab switch in `MainScreen` — which rebuilds
/// screens but not providers — navigating Movies → Series → Movies returns to
/// the same merge, the same loaded pages and the same scroll position, instead
/// of refetching the catalog on every visit.
library;

import '../media/media_kind.dart';
import 'hidden_libraries_provider.dart';
import 'libraries_provider.dart';
import 'multi_server_provider.dart';
import 'unified_catalog_provider.dart';

class UnifiedCatalogs {
  UnifiedCatalogs({
    required MultiServerProvider multiServer,
    required LibrariesProvider libraries,
    required HiddenLibrariesProvider hiddenLibraries,
  }) : _multiServer = multiServer,
       _libraries = libraries,
       _hiddenLibraries = hiddenLibraries;

  final MultiServerProvider _multiServer;
  final LibrariesProvider _libraries;
  final HiddenLibrariesProvider _hiddenLibraries;

  UnifiedCatalogProvider? _movies;
  UnifiedCatalogProvider? _shows;

  /// The Films catalog, built on first access.
  UnifiedCatalogProvider get movies => _movies ??= _create(MediaKind.movie);

  /// The Series catalog, built on first access.
  UnifiedCatalogProvider get shows => _shows ??= _create(MediaKind.show);

  /// The catalog for [kind], for a surface that is generic over the two.
  ///
  /// Throws for anything else rather than inventing a third catalog: hoofdstuk
  /// 10.1 has exactly two, and a mixed browse stays Bibliotheken's job
  /// (hoofdstuk 4.5).
  UnifiedCatalogProvider forKind(MediaKind kind) => switch (kind) {
    MediaKind.movie => movies,
    MediaKind.show => shows,
    _ => throw ArgumentError.value(kind, 'kind', 'the unified catalog is Films or Series, nothing else'),
  };

  UnifiedCatalogProvider _create(MediaKind kind) => UnifiedCatalogProvider(
    multiServer: _multiServer,
    libraries: _libraries,
    hiddenLibraries: _hiddenLibraries,
    kind: kind,
  );

  /// Disposes whichever catalogs were actually built. Wired to the registering
  /// `Provider`'s own `dispose:`, so a profile switch releases both listeners
  /// each catalog registered on `LibrariesProvider`, `HiddenLibrariesProvider`
  /// and `MultiServerProvider`.
  void dispose() {
    _movies?.dispose();
    _shows?.dispose();
    _movies = null;
    _shows = null;
  }
}
