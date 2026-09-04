/// A semantically meaningful discovery row (hoofdstuk 17 of
/// docs/tvos-unified-experience.md): the projection layer's answer to "what
/// is one row on Home, on the Films landing, on the Series landing".
///
/// Pure model, like every other type in this directory — no I/O, no writes
/// (hoofdstuk 4.6). `home_projection_service.dart` is the one place that
/// builds these out of [MediaHub]/`MediaItem`; a widget never assembles one
/// itself (DEC-064's architectuurgrens: a second projection architecture
/// next to this one is exactly what fase 6 exists to prevent).
library;

import '../media_hub.dart';
import 'unified_media_group.dart';

/// The media scope of a discovery row.
///
/// Deliberately not `MediaKind`: a backend hub's `type` is regularly
/// `mixed` (Plex's promoted home hubs, Jellyfin's synthesized "Recently
/// added" over a mixed library), and `MediaKind` has no value for that —
/// mapping it onto `unknown` would erase the difference between "this row
/// holds films and series" and "we could not read this row's type at all",
/// which is exactly the distinction a landing page needs to decide whether a
/// row belongs on Films, on Series, or on Home only.
enum UnifiedHubKind {
  movie,
  show,
  episode,
  mixed,

  /// No hoofdstuk 17 scope applies (music rows, photo rows, an unreadable
  /// backend type).
  other;

  /// The kind a backend [MediaHub.type] token names.
  static UnifiedHubKind fromHubType(String? type) => switch (type?.trim().toLowerCase()) {
    'movie' || 'movies' => UnifiedHubKind.movie,
    'show' || 'shows' || 'series' => UnifiedHubKind.show,
    'episode' || 'episodes' => UnifiedHubKind.episode,
    'mixed' => UnifiedHubKind.mixed,
    _ => UnifiedHubKind.other,
  };

  /// The kind covering all of [kinds]. Identical kinds keep their own value;
  /// anything else is genuinely [mixed] — merging two servers' rows must not
  /// silently claim one of the two scopes.
  static UnifiedHubKind merged(Iterable<UnifiedHubKind> kinds) {
    final distinct = kinds.toSet();
    if (distinct.isEmpty) return UnifiedHubKind.other;
    if (distinct.length == 1) return distinct.single;
    return UnifiedHubKind.mixed;
  }
}

/// The complete-catalogus destination a landing row offers behind
/// "Alles bekijken" (hoofdstuk 10.2b, DEC-064: a first-class route, not a
/// tiny text link). A synthesized landing row carries one; a backend hub
/// does not — "everything Plex called Recently Added" is not a catalogue.
enum UnifiedHubViewAll { allMovies, allSeries }

/// The hoofdstuk 17.2 merge key: two hubs become one row only when this
/// matches, i.e. only when their semantics are demonstrably equal.
///
/// Titles are not part of it, in either direction. "Niet twee hubs
/// samenvoegen omdat de vertaalde titel gelijk klinkt" rules out title as
/// evidence *for* a merge, and using it as evidence *against* one would
/// split two servers whose per-library hub titles embed the user's own
/// library name ("Recently Added in Films" vs "Recently Added in Movies")
/// while describing the same row.
class UnifiedHubKey {
  /// The backend's own semantic identifier for this row, verbatim —
  /// `home.continue`, `tv.recentlyadded`, `library.<id>.recent`.
  ///
  /// Kept case-sensitive on purpose. Jellyfin folds a server-local library
  /// id straight into the identifier (`library.$libraryId.recent`), and two
  /// libraries whose ids differ only in case are two libraries; lower-casing
  /// for tidiness would merge them.
  final String backendIdentifier;

  /// Normalized [MediaHub.type]. A safe thing to lower-case: it is a fixed
  /// backend token, never user- or locale-supplied.
  final String semanticType;

  /// Which library this row is scoped to, when it is scoped to one at all.
  /// Server-qualified, because a library id only means anything on its own
  /// server.
  final String? libraryScope;

  /// Why the backend recommended this row ("because you watched X").
  ///
  /// Null under the default derivation: no field on [MediaHub] carries a
  /// recommendation reason today, so the projection cannot read one. It is
  /// still part of the key because hoofdstuk 17.2 names it, and because
  /// [narrowedTo] fills it with the backend's own row discriminator, which
  /// is the closest honest stand-in.
  final String? recommendationReason;

  /// Set when the row belongs to one specific server and must never merge
  /// with another server's row (hoofdstuk 17.5: a genuinely server-specific
  /// hub keeps its server context; a global row loses it).
  final String? serverScope;

  const UnifiedHubKey({
    required this.backendIdentifier,
    required this.semanticType,
    this.libraryScope,
    this.recommendationReason,
    this.serverScope,
  });

  /// The key [hub] merges on by default.
  ///
  /// Two dimensions decide whether the row may cross a server boundary:
  ///
  /// - **No [MediaHub.identifier].** All that is left is [MediaHub.id], the
  ///   backend's opaque key — a Plex hub path can embed server-local
  ///   directory ids, so equality across two servers proves nothing. Such a
  ///   row stays server-scoped.
  /// - **A [MediaHub.libraryId].** The row was split out of one concrete
  ///   library (see that field's own doc), and library identity is
  ///   server-local. Also server-scoped.
  ///
  /// Everything else — a backend that told us this row is `home.continue` —
  /// merges across servers *and* across backends. That is not a guess about
  /// two backends happening to agree: `plex_mappers.dart` passes Plex's own
  /// `hubIdentifier` through, and `jellyfin_mappers.dart`'s synthesized hubs
  /// are handed identifiers Pleya itself chose (`home.continue`,
  /// `home.nextup`, `home.recent`) precisely to name the same semantics.
  factory UnifiedHubKey.forHub(MediaHub hub) {
    final identifier = hub.identifier?.trim();
    final hasIdentifier = identifier != null && identifier.isNotEmpty;
    final libraryId = hub.libraryId;
    final serverId = hub.serverId;
    final libraryScope = libraryId == null ? null : '${serverId ?? ''}/$libraryId';
    return UnifiedHubKey(
      backendIdentifier: hasIdentifier ? identifier : hub.id,
      semanticType: hub.type.trim().toLowerCase(),
      libraryScope: libraryScope,
      serverScope: (!hasIdentifier || libraryScope != null) ? serverId : null,
    );
  }

  /// This key narrowed to one server and one concrete backend row.
  ///
  /// Used when a single server contributes two hubs that share a key. The
  /// backend distinguishes them by a reason we cannot see (several
  /// "Because you watched" rows share one identifier — see `homeRowId`'s doc
  /// in `home_layout_provider.dart`), so merging them would fuse two
  /// different recommendations into one row. Narrowing instead of merging
  /// mirrors `grouping_service.dart`'s C19 rule at the item layer: a server
  /// contributing two candidates to one bucket makes that bucket ambiguous,
  /// and ambiguity never merges.
  UnifiedHubKey narrowedTo({required String? serverId, required String backendRowKey}) => UnifiedHubKey(
    backendIdentifier: backendIdentifier,
    semanticType: semanticType,
    libraryScope: libraryScope,
    recommendationReason: backendRowKey,
    serverScope: serverId,
  );

  /// Canonical string form, also usable as a map key.
  String get value =>
      '$backendIdentifier|$semanticType|${libraryScope ?? ''}|${recommendationReason ?? ''}|${serverScope ?? ''}';

  /// The [UnifiedMediaHub.hubId] a row built on this key carries.
  String get hubId => 'hub:$value';

  @override
  bool operator ==(Object other) => identical(this, other) || other is UnifiedHubKey && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'UnifiedHubKey($value)';
}

class UnifiedMediaHub {
  /// Stable row identity. Derived from semantics only — a [UnifiedHubKey],
  /// or a caller-supplied slug for a global Pleya row — never from a list
  /// index, a fetch order or an object hash. Two runs over the same topology
  /// produce byte-identical ids, because hide/reorder, focus memory and
  /// restoration all key on this (hoofdstuk 17.5, 7.6, 11.9).
  final String hubId;

  /// Already-resolved display title. A backend row shows what the backend
  /// called it; a synthesized row shows the label its caller passed in.
  /// Nothing here reaches into i18n — this layer has no locale.
  final String title;

  final UnifiedHubKind kind;

  /// The row's cards, ordered and unmodifiable.
  final List<UnifiedMediaGroup> groups;

  /// True when a source that should have contributed did not — an offline or
  /// failed server (hoofdstuk 21.4: healthy content stays fully usable, the
  /// header says coverage is partial, and there is no full-page error).
  ///
  /// A failed server contributes no hub at all, so nothing in the input
  /// points back at what is missing; which servers failed is therefore a
  /// fact only the caller's topology knowledge carries, and the projection
  /// takes it as an argument rather than inferring it.
  final bool isPartial;

  /// The complete-catalogus destination behind "Alles bekijken", when this
  /// row has one (hoofdstuk 10.2b).
  final UnifiedHubViewAll? viewAll;

  /// The legacy `homeRowId(MediaHub)` values (`'serverId:identifier'`, see
  /// `home_layout_provider.dart`) of every [MediaHub] that fed this row.
  ///
  /// Load-bearing, not diagnostics: hide/reorder preferences are stored
  /// against those ids, so merging two servers' rows into one unified row
  /// has to keep both of them reachable, or a user's saved Home layout
  /// silently stops applying to the row they hid.
  final List<String> contributingRowIds;

  /// The server this row belongs to, and only when it genuinely belongs to
  /// one (hoofdstuk 17.5: server names disappear from *global* row titles).
  /// Null for a merged or synthesized row.
  final String? serverName;

  UnifiedMediaHub({
    required this.hubId,
    required this.title,
    required this.kind,
    required List<UnifiedMediaGroup> groups,
    this.isPartial = false,
    this.viewAll,
    List<String> contributingRowIds = const [],
    this.serverName,
  }) : groups = List.unmodifiable(groups),
       contributingRowIds = List.unmodifiable(contributingRowIds);

  /// A row projected from one or more backend hubs sharing [key].
  factory UnifiedMediaHub.fromKey({
    required UnifiedHubKey key,
    required String title,
    required UnifiedHubKind kind,
    required List<UnifiedMediaGroup> groups,
    bool isPartial = false,
    UnifiedHubViewAll? viewAll,
    List<String> contributingRowIds = const [],
    String? serverName,
  }) => UnifiedMediaHub(
    hubId: key.hubId,
    title: title,
    kind: kind,
    groups: groups,
    isPartial: isPartial,
    viewAll: viewAll,
    contributingRowIds: contributingRowIds,
    serverName: serverName,
  );

  /// A global Pleya row that no single backend hub produced — Verder kijken,
  /// a landing's "Alle films" (hoofdstuk 17.1). [slug] is the row's
  /// semantics, not its label: it must survive translation of [title], so it
  /// is never derived from it.
  factory UnifiedMediaHub.synthesized({
    required String slug,
    required String title,
    required UnifiedHubKind kind,
    required List<UnifiedMediaGroup> groups,
    bool isPartial = false,
    UnifiedHubViewAll? viewAll,
    List<String> contributingRowIds = const [],
  }) => UnifiedMediaHub(
    hubId: synthesizedHubId(slug),
    title: title,
    kind: kind,
    groups: groups,
    isPartial: isPartial,
    viewAll: viewAll,
    contributingRowIds: contributingRowIds,
  );

  static String synthesizedHubId(String slug) => 'hub:pleya:$slug';

  bool get isEmpty => groups.isEmpty;

  /// Whether this row carries genuine server context to show (hoofdstuk
  /// 17.5). A merged row never does.
  bool get isServerSpecific => serverName != null;

  @override
  String toString() => 'UnifiedMediaHub($hubId, ${groups.length} group${groups.length == 1 ? '' : 's'})';
}
