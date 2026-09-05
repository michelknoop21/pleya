/// A Home row the viewer defined themselves: a saved catalog filter with a
/// name (hoofdstuk 9.1 and 23 of docs/tvos-unified-experience.md,
/// [DEC-100](../../../docs/DECISIONS.md#dec-100)).
///
/// Every other row on Home comes from a hub the backend served. This one has
/// no hub behind it at all — its source is a [UnifiedCatalogPreferences], and
/// its content is whatever the hoofdstuk-10 catalog answers on that filter, in
/// that sort. So the type it needs is the catalog's own filter model, stored
/// per profile, and not a second filter vocabulary invented for Home.
///
/// ## Two identities, and why neither can be the other
///
/// [layoutRowId] is this row's name in `HomeLayoutProvider`'s space, which
/// predates unified rows and holds `'serverId:identifier'` strings. Hide and
/// reorder are stored against those, so a custom row needs one of its own that
/// no backend hub can ever produce. The `#` prefix is what guarantees that: a
/// server id is a Plex machine identifier, a Jellyfin server id or one of this
/// codebase's own fixed slugs, and none of them can begin with `#`, so
/// `homeRowId` cannot collide with this by accident or by a server renaming
/// itself.
///
/// [hubSlug] is the row's name in `UnifiedMediaHub`'s space, which is what the
/// feed keys focus memory, scroll position and restoration on. They are
/// deliberately different strings: one is a preference key that has to survive
/// a schema the projection layer knows nothing about, the other is a row
/// identity the projection layer owns.
///
/// ## The name is optional on purpose
///
/// An empty [name] means the row is labelled after its filter and keeps
/// following it (C1). That is not a display nicety: it is what makes a row
/// creatable without ever opening the on-screen keyboard, which on a remote is
/// the difference between three presses and a spelling session. Deriving the
/// label needs a locale, so it is not done here — this layer has none, the same
/// rule the rest of `lib/media/unified/` follows.
library;

import 'dart:convert';

import '../../media/media_kind.dart';
import '../../utils/app_logger.dart';
import 'unified_catalog_filters.dart';

class HomeCustomRow {
  /// Stable, opaque, and generated once at creation ([newId]). Never derived
  /// from the name or the filter: both are editable, and an id that changed
  /// with them would lose the row's place in the stored order and its focus
  /// memory on every edit.
  final String id;

  /// Films or Series, the two catalogs hoofdstuk 10.1 has.
  final MediaKind kind;

  /// The viewer's own label, or empty to follow the filter (C1).
  final String name;

  final UnifiedCatalogPreferences preferences;

  const HomeCustomRow({required this.id, required this.kind, this.name = '', required this.preferences});

  UnifiedCatalogFilterSelection get filters => preferences.filters;
  UnifiedCatalogSort get sort => preferences.sort;

  /// This row's id in `HomeLayoutProvider`'s legacy row-id space. See the
  /// library doc for why the prefix is load-bearing.
  String get layoutRowId => layoutRowIdFor(id);

  static String layoutRowIdFor(String id) => '#custom:$id';

  /// Whether [rowId] names a custom row rather than a backend hub.
  static bool isCustomLayoutRowId(String rowId) => rowId.startsWith('#custom:');

  /// This row's id in `UnifiedMediaHub`'s synthesized-slug space.
  String get hubSlug => 'custom:$id';

  HomeCustomRow copyWith({MediaKind? kind, String? name, UnifiedCatalogPreferences? preferences}) => HomeCustomRow(
    id: id,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    preferences: preferences ?? this.preferences,
  );

  /// The filter part rides on [UnifiedCatalogPreferences.toJson] rather than
  /// on a copy of it. Two serialisations of one selection would drift the
  /// moment a filter field is added, and the added field would then be silently
  /// dropped on exactly the rows the user cares about most.
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.id,
    if (name.isNotEmpty) 'name': name,
    'query': preferences.toJson(),
  };

  /// Null for anything this build cannot read as a row.
  ///
  /// A stored entry with no id, or a kind that is not one of the two catalogs,
  /// is dropped rather than repaired: a row without an identity cannot be
  /// reordered, edited or deleted, so keeping it would put something on Home
  /// that the panel has no way to remove.
  static HomeCustomRow? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    final kind = MediaKind.fromString(json['kind'] as String?);
    if (kind != MediaKind.movie && kind != MediaKind.show) return null;
    final query = json['query'];
    return HomeCustomRow(
      id: id,
      kind: kind,
      name: json['name'] is String ? json['name'] as String : '',
      preferences: query is Map<String, dynamic>
          ? UnifiedCatalogPreferences.fromJson(query)
          : UnifiedCatalogPreferences.defaults,
    );
  }

  /// Decodes one stored line, swallowing anything unreadable.
  ///
  /// Storage holds one JSON object per row rather than one document for all of
  /// them, so a single corrupt entry costs its own row and not the whole set.
  static HomeCustomRow? decode(String stored) {
    try {
      final decoded = jsonDecode(stored);
      return decoded is Map<String, dynamic> ? fromJson(decoded) : null;
    } catch (e) {
      appLogger.w('Failed to read a saved Home row', error: e);
      return null;
    }
  }

  String encode() => jsonEncode(toJson());

  /// A fresh row id.
  ///
  /// Time-based rather than random, so the ids of rows made in one session
  /// sort in the order they were made — useful in a log, harmless everywhere
  /// else. Uniqueness comes from the caller, which rejects a collision with a
  /// row it already holds.
  static String newId([DateTime? now]) => (now ?? DateTime.now()).microsecondsSinceEpoch.toRadixString(36);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HomeCustomRow &&
          other.id == id &&
          other.kind == kind &&
          other.name == name &&
          other.preferences == preferences;

  @override
  int get hashCode => Object.hash(id, kind, name, preferences);

  @override
  String toString() => 'HomeCustomRow($id, ${kind.id}, ${name.isEmpty ? 'unnamed' : name})';
}
