import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/pleya_server_client.dart';

import 'pleya_fake_server.dart';

/// Household activity on the client side (protocol chapter 14b). The detail
/// page draws a line from this, so every way of not getting an answer has to
/// end in an empty list and never in an exception.
void main() {
  late PleyaServerClient client;
  tearDown(() => client.close());

  Future<PleyaServerClient> connected(PleyaFakeServer fake) async {
    final c = fake.client();
    await c.refreshCapabilities();
    return c;
  }

  Map<String, dynamic> entry(String username, {bool self = false, int completed = 1}) => {
    'user_id': 'user-$username',
    'username': username,
    'initials': username[0].toUpperCase(),
    'is_self': self,
    'last_watched_at': '2026-10-29T20:42:00Z',
    'play_count': 2,
    'completed_items': completed,
  };

  test('a server with the flag answers, in its own order', () async {
    final server = PleyaFakeServer(watchState: true)
      ..itemActivityCapability = true
      ..itemActivityByItem['movie-1'] = [entry('sam', completed: 0), entry('michel', self: true)];
    client = await connected(server);

    expect(client.capabilities.itemActivity, isTrue);
    final items = await client.fetchItemActivity('movie-1');

    expect(server.itemActivityRequests, ['/items/movie-1/activity']);
    expect(items.map((e) => e.username), ['sam', 'michel']);
    expect(items.first.completedItems, 0);
    expect(items.last.isSelf, isTrue);
    expect(items.last.playCount, 2);
  });

  test('a server without the flag is not asked', () async {
    final server = PleyaFakeServer(watchState: true)..itemActivityByItem['movie-1'] = [entry('sam')];
    client = await connected(server);

    expect(client.capabilities.itemActivity, isFalse);
    expect(await client.fetchItemActivity('movie-1'), isEmpty);
    expect(server.itemActivityRequests, isEmpty);
  });

  test('a failing server reads as nobody', () async {
    final server = PleyaFakeServer(watchState: true)
      ..itemActivityCapability = true
      ..itemActivityFailureStatus = 500;
    client = await connected(server);

    expect(await client.fetchItemActivity('movie-1'), isEmpty);
    expect(server.itemActivityRequests, hasLength(1));
  });

  test('an item the requester may not see reads as nobody', () async {
    final server = PleyaFakeServer(watchState: true)
      ..itemActivityCapability = true
      ..itemActivityFailureStatus = 404;
    client = await connected(server);

    expect(await client.fetchItemActivity('movie-1'), isEmpty);
  });

  test('an unreadable answer reads as nobody and does not throw', () async {
    final server = PleyaFakeServer(watchState: true)
      ..itemActivityCapability = true
      ..itemActivityByItem['movie-1'] = [
        {'user_id': 'x', 'username': 'sam'},
      ];
    client = await connected(server);

    expect(await client.fetchItemActivity('movie-1'), isEmpty);
  });
}
