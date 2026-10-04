import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/providers/continue_watching_hidden_provider.dart';
import 'package:pleya/services/storage_service.dart';

import '../test_helpers/prefs.dart';

MediaItem _episode(String id) => MediaItem(
  id: id,
  backend: MediaBackend.jellyfin,
  kind: MediaKind.episode,
  title: 'Gold Summit',
  grandparentTitle: 'The Penguin',
  parentIndex: 1,
  index: 6,
  serverId: 'zolder',
  serverName: 'Zolder',
);

void main() {
  setUp(resetSharedPreferencesForTest);

  test('hide records the title and its place, newest first', () async {
    final p = ContinueWatchingHiddenProvider();
    await p.hide(_episode('a'));
    await p.hide(_episode('b'));
    expect(p.entries.map((e) => e.globalKey), ['zolder:b', 'zolder:a']);
    expect(p.entries.first.title, 'The Penguin');
    expect(p.entries.first.subtitle, 'S1 E6 · Gold Summit');
    expect(p.keys, {'zolder:a', 'zolder:b'});
    p.dispose();
  });

  test('hiding the same title twice keeps one entry', () async {
    final p = ContinueWatchingHiddenProvider();
    await p.hide(_episode('a'));
    await p.hide(_episode('a'));
    expect(p.count, 1);
    p.dispose();
  });

  test('restore removes the entry and notifies; an unknown key is a no-op', () async {
    final p = ContinueWatchingHiddenProvider();
    await p.hide(_episode('a'));
    var notified = 0;
    p.addListener(() => notified++);
    await p.restore('zolder:nope');
    expect(notified, 0);
    await p.restore('zolder:a');
    expect(p.count, 0);
    expect(notified, 1);
    p.dispose();
  });

  test('the hidden set survives a reload and is per profile', () async {
    final first = ContinueWatchingHiddenProvider(profileId: 'p1');
    await first.hide(_episode('a'));
    first.dispose();

    final again = ContinueWatchingHiddenProvider(profileId: 'p1');
    await again.ensureInitialized();
    expect(again.keys, {'zolder:a'});
    again.dispose();

    final other = ContinueWatchingHiddenProvider(profileId: 'p2');
    await other.ensureInitialized();
    expect(other.count, 0, reason: 'another profile on this device hid nothing');
    other.dispose();
  });

  test('a corrupt line costs its own entry, not the set', () async {
    final storage = await StorageService.getInstance();
    await storage.saveHiddenContinueWatching(null, [
      'not json',
      const HiddenContinueWatchingEntry(globalKey: 'zolder:a', title: 'The Penguin', hiddenAt: 1).encode(),
    ]);
    final p = ContinueWatchingHiddenProvider();
    await p.ensureInitialized();
    expect(p.keys, {'zolder:a'});
    p.dispose();
  });
}
