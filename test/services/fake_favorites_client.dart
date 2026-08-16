import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';

/// Minimal stand-in for the favorites half of [MediaServerClient].
///
/// Only the two primitives the watchlist sources use are implemented; every
/// other member throws, so a source that starts calling something else fails
/// loudly instead of quietly getting a default.
class FakeFavoritesClient implements MediaServerClient {
  FakeFavoritesClient({required this.favorites, this.pageSize = 100});

  final List<MediaItem> favorites;
  final int pageSize;

  final List<(String id, bool isFavorite)> setCalls = [];
  final List<MediaKind?> kindsRequested = [];
  int pagesServed = 0;

  @override
  Future<void> setFavorite(MediaItem item, bool isFavorite) async {
    setCalls.add((item.id, isFavorite));
  }

  @override
  Future<LibraryPage<MediaItem>> fetchFavorites({MediaKind? kind, int offset = 0, int limit = 100}) async {
    kindsRequested.add(kind);
    pagesServed++;
    final end = (offset + pageSize).clamp(0, favorites.length);
    final slice = offset >= favorites.length ? <MediaItem>[] : favorites.sublist(offset, end);
    return LibraryPage<MediaItem>(items: slice, totalCount: favorites.length, offset: offset);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('FakeFavoritesClient does not implement ${invocation.memberName}');
  }
}
