/// Collection and playlist wire types for Pleya Protocol v1 (chapter 14b).
/// Split from `pleya_wire_library.dart` for the same reason that file was split
/// from `pleya_wire.dart`.
library;

import 'pleya_wire_parse.dart';

/// `CollectionVisibility`, unknown-safe. Null means the server named a value
/// this build does not know: the app shows the collection as shared, never
/// sends the value back and leaves the visibility alone when editing.
enum PleyaCollectionVisibility {
  private('private'),
  everyone('everyone'),
  users('users');

  const PleyaCollectionVisibility(this.wire);

  final String wire;

  static PleyaCollectionVisibility? tryParse(String? raw) => switch (raw) {
    'private' => PleyaCollectionVisibility.private,
    'everyone' => PleyaCollectionVisibility.everyone,
    'users' => PleyaCollectionVisibility.users,
    _ => null,
  };
}

/// `ListUser`: who owns a list, or who it is shared with.
class PleyaListUser {
  const PleyaListUser({required this.id, required this.username});

  final String id;
  final String username;

  factory PleyaListUser.fromJson(Map<String, dynamic> json) =>
      PleyaListUser(id: str(json, 'id'), username: str(json, 'username'));
}

/// The shape a collection page and a playlist page share (`Page`).
class PleyaListPage<T> {
  const PleyaListPage({required this.items, this.nextCursor, this.totalEstimate});

  final List<T> items;
  final String? nextCursor;
  final int? totalEstimate;

  factory PleyaListPage.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) parse) => PleyaListPage(
    items: [for (final row in objectList(json['items'], 'items')) parse(row)],
    nextCursor: strOrNull(json, 'next_cursor'),
    totalEstimate: integerOrNull(json, 'total_estimate'),
  );
}

List<String> _idList(Object? raw, String what) {
  if (raw == null) return const [];
  if (raw is! List) fail('$what is not an array');
  return [for (final id in raw) id is String ? id : fail('$what element is not a string')];
}

/// `Collection`.
class PleyaCollection {
  const PleyaCollection({
    required this.id,
    required this.title,
    required this.owner,
    required this.isOwner,
    required this.visibility,
    required this.itemCount,
    required this.artwork,
    required this.createdAt,
    required this.updatedAt,
    this.sharedWith = const [],
  });

  final String id;
  final String title;
  final PleyaListUser owner;

  /// The requester owns it and may therefore write to it.
  final bool isOwner;

  final PleyaCollectionVisibility? visibility;

  /// Only for the owner, and only at [PleyaCollectionVisibility.users].
  final List<PleyaListUser> sharedWith;

  /// Per viewer: only items this requester may see.
  final int itemCount;

  /// Artwork ids of the first items this requester may see.
  final List<String> artwork;

  final DateTime createdAt;
  final DateTime updatedAt;

  factory PleyaCollection.fromJson(Map<String, dynamic> json) => PleyaCollection(
    id: str(json, 'id'),
    title: str(json, 'title'),
    owner: PleyaListUser.fromJson(obj(json['owner'], 'owner')),
    isOwner: boolean(json, 'is_owner'),
    visibility: PleyaCollectionVisibility.tryParse(str(json, 'visibility')),
    sharedWith: [for (final user in objectList(json['shared_with'], 'shared_with')) PleyaListUser.fromJson(user)],
    itemCount: integer(json, 'item_count'),
    artwork: _idList(json['artwork'], 'artwork'),
    createdAt: timestamp(json, 'created_at'),
    updatedAt: timestamp(json, 'updated_at'),
  );
}

/// `Playlist`. Always the requester's own.
class PleyaPlaylist {
  const PleyaPlaylist({
    required this.id,
    required this.title,
    required this.itemCount,
    required this.durationMs,
    required this.artwork,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final int itemCount;
  final int durationMs;
  final List<String> artwork;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory PleyaPlaylist.fromJson(Map<String, dynamic> json) => PleyaPlaylist(
    id: str(json, 'id'),
    title: str(json, 'title'),
    itemCount: integer(json, 'item_count'),
    durationMs: integer(json, 'duration_ms'),
    artwork: _idList(json['artwork'], 'artwork'),
    createdAt: timestamp(json, 'created_at'),
    updatedAt: timestamp(json, 'updated_at'),
  );
}

/// `CreateCollectionRequest`, a closed schema.
class PleyaCreateCollectionRequest {
  const PleyaCreateCollectionRequest({required this.title, this.visibility, this.sharedWith});

  final String title;
  final PleyaCollectionVisibility? visibility;
  final List<String>? sharedWith;

  factory PleyaCreateCollectionRequest.fromJson(Map<String, dynamic> json) => PleyaCreateCollectionRequest(
    title: str(json, 'title'),
    visibility: PleyaCollectionVisibility.tryParse(strOrNull(json, 'visibility')),
    sharedWith: json.containsKey('shared_with') ? _idList(json['shared_with'], 'shared_with') : null,
  );

  Map<String, dynamic> toJson() => {'title': title, 'visibility': ?visibility?.wire, 'shared_with': ?sharedWith};
}

/// `UpdateCollectionRequest`, a closed schema: a field that is absent stays as
/// it is, so a null here is never sent.
class PleyaUpdateCollectionRequest {
  const PleyaUpdateCollectionRequest({this.title, this.visibility, this.sharedWith});

  final String? title;
  final PleyaCollectionVisibility? visibility;
  final List<String>? sharedWith;

  factory PleyaUpdateCollectionRequest.fromJson(Map<String, dynamic> json) => PleyaUpdateCollectionRequest(
    title: strOrNull(json, 'title'),
    visibility: PleyaCollectionVisibility.tryParse(strOrNull(json, 'visibility')),
    sharedWith: json.containsKey('shared_with') ? _idList(json['shared_with'], 'shared_with') : null,
  );

  Map<String, dynamic> toJson() => {'title': ?title, 'visibility': ?visibility?.wire, 'shared_with': ?sharedWith};
}

/// `CreatePlaylistRequest` and `UpdatePlaylistRequest` carry the same one
/// field, and only `title` is required in the first.
class PleyaPlaylistTitleRequest {
  const PleyaPlaylistTitleRequest({this.title});

  final String? title;

  factory PleyaPlaylistTitleRequest.fromJson(Map<String, dynamic> json) =>
      PleyaPlaylistTitleRequest(title: strOrNull(json, 'title'));

  Map<String, dynamic> toJson() => {'title': ?title};
}

/// `ListItemsRequest`, for both replacing a list and appending to it.
class PleyaListItemsRequest {
  const PleyaListItemsRequest({required this.itemIds});

  final List<String> itemIds;

  factory PleyaListItemsRequest.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('item_ids')) fail('item_ids is missing');
    return PleyaListItemsRequest(itemIds: _idList(json['item_ids'], 'item_ids'));
  }

  Map<String, dynamic> toJson() => {'item_ids': itemIds};
}
