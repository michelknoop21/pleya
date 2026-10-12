import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';

class _Client implements MediaServerClient {
  _Client(this.answer);

  final Future<MediaItem?> Function() answer;

  @override
  ServerId get serverId => ServerId('srv');

  @override
  Future<MediaItem?> fetchItem(String id, {bool useCache = true}) => answer();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final item = MediaItem(id: 'a', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'A', serverId: 'srv');

  test('answers the item', () async {
    expect(await fetchItemOrNull(_Client(() async => item), 'a'), item);
  });

  test('answers null when the item is gone', () async {
    expect(await fetchItemOrNull(_Client(() async => null), 'a'), isNull);
  });

  test('answers null instead of throwing when the server errors: the callers run unawaited', () async {
    expect(await fetchItemOrNull(_Client(() async => throw StateError('502')), 'a'), isNull);
  });

  test('the guest media switch resolves its item through it', () {
    final source = File('lib/screens/video_player/parts/watch_together.dart').readAsStringSync();

    expect(source, contains('fetchItemOrNull(client, ratingKey)'));
    expect(source, isNot(contains('await client.fetchItem(ratingKey)')));
  });
}
