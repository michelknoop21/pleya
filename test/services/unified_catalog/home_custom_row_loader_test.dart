/// ROW1i. A row asks the merge exactly one question and then throws the
/// service away, so anything `loadMore` leaves running is aborted rather than
/// merged. These two tests pin what that has to mean: finish the fetch when it
/// can be finished, and say the coverage is partial when it cannot.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/services/unified_catalog/home_custom_row.dart';
import 'package:pleya/services/unified_catalog/home_custom_row_loader.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/utils/media_server_http_client.dart';

MediaItem _film(String id, {required String title, required String serverId}) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: title, serverId: serverId);

MediaLibrary _library(String serverId, String libraryId) => MediaLibrary(
  id: libraryId,
  backend: MediaBackend.plex,
  title: libraryId,
  kind: MediaKind.movie,
  serverId: serverId,
  serverName: serverId,
);

/// One server's films, optionally held back until the test lets them through.
class _Client implements MediaServerClient {
  _Client(this._serverId, this._items, {this.gate});

  final String _serverId;
  final List<MediaItem> _items;
  final Completer<void>? gate;

  @override
  ServerId get serverId => ServerId(_serverId);

  @override
  String? get serverName => _serverId;

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    if (gate != null) await gate!.future;
    final end = (query.offset + query.limit).clamp(0, _items.length);
    final slice = query.offset >= _items.length ? const <MediaItem>[] : _items.sublist(query.offset, end);
    return LibraryPage(items: slice, totalCount: _items.length, offset: query.offset);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const row = HomeCustomRow(id: 'r1', kind: MediaKind.movie, preferences: UnifiedCatalogPreferences.defaults);

  CatalogHomeCustomRowLoader loaderFor(Map<String, _Client> clients) => CatalogHomeCustomRowLoader(
    libraries: () => [for (final id in clients.keys) _library(id, 'films-$id')],
    isServerVisible: (_) => true,
    hiddenLibraryKeys: () => const {},
    clientFor: (id) => clients[id.value],
    // A real two seconds per case buys nothing here.
    grace: const Duration(milliseconds: 10),
  );

  test('a library that answers after the grace still makes it into the row', () async {
    final gate = Completer<void>();
    final clients = {
      'fast': _Client('fast', [_film('f1', title: 'Alpha', serverId: 'fast')]),
      'slow': _Client('slow', [_film('s1', title: 'Bravo', serverId: 'slow')], gate: gate),
    };
    // Released well after the round's own wait has elapsed, which is exactly
    // the case `loadMore` returns early on.
    Timer(const Duration(milliseconds: 60), gate.complete);

    final content = await loaderFor(clients).load(row, limit: 20);

    expect(content.groups.map((g) => g.representativeSource.item.title), containsAll(['Alpha', 'Bravo']));
    expect(content.isPartial, isFalse, reason: 'nothing failed and nothing was left behind');
  });

  test('a library that never answers leaves the row partial, not complete', () async {
    final gate = Completer<void>();
    addTearDown(gate.complete);
    final clients = {
      'fast': _Client('fast', [_film('f1', title: 'Alpha', serverId: 'fast')]),
      'stuck': _Client('stuck', [_film('s1', title: 'Bravo', serverId: 'stuck')], gate: gate),
    };

    final content = await loaderFor(clients).load(row, limit: 1);

    // `limit: 1` is what stops the row asking again: it is full, and the stuck
    // library is abandoned. Nothing failed, so `failedLibraryIds` is empty and
    // only the pending fetch says the coverage is short.
    expect(content.groups, hasLength(1));
    expect(content.isPartial, isTrue);
  });
}
