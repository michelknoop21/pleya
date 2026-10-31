import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/item_watcher.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/item_watchers_service.dart';

MediaItem _item({
  MediaKind kind = MediaKind.movie,
  int? viewCount,
  int? offset,
  int? duration = 1000,
  int? leafs,
  int? viewed,
}) => MediaItem(
  id: 'item',
  backend: MediaBackend.jellyfin,
  kind: kind,
  viewCount: viewCount,
  viewOffsetMs: offset,
  durationMs: duration,
  leafCount: leafs,
  viewedLeafCount: viewed,
);

void main() {
  const service = ItemWatchersService();
  List<ItemWatcher> line(MediaItem item, [List<ItemWatcher> household = const []]) =>
      service.activityLine(item, household: household, selfName: 'Michel').watchers;

  test('nothing watched and nobody else: nothing to say', () {
    expect(line(_item()), isEmpty);
    expect(line(_item(viewCount: 0, offset: 0)), isEmpty);
  });

  test('a finished film and a started one both count', () {
    expect(line(_item(viewCount: 1)).single.isSelf, isTrue);
    expect(line(_item(offset: 500)).single.isSelf, isTrue);
  });

  test('a position past the end is no started film', () {
    expect(line(_item(offset: 1000)), isEmpty);
  });

  test('a series counts from its first episode, and an empty one not at all', () {
    expect(line(_item(kind: MediaKind.show, leafs: 8, viewed: 1)).single.isSelf, isTrue);
    expect(line(_item(kind: MediaKind.show, leafs: 8, viewed: 0)), isEmpty);
    expect(line(_item(kind: MediaKind.show, leafs: 0, viewed: 0)), isEmpty);
  });

  test('the viewer goes in front once, and the household stays in its order', () {
    const sam = ItemWatcher(id: 'a', displayName: 'sam');
    const you = ItemWatcher(id: 'b', displayName: 'michel', isSelf: true);

    expect(line(_item(viewCount: 1), const [sam]).map((w) => w.displayName), ['Michel', 'sam']);
    expect(line(_item(viewCount: 1), const [sam, you]).map((w) => w.displayName), ['sam', 'michel']);
    expect(line(_item(), const [sam]).map((w) => w.displayName), ['sam']);
  });

  test('the claim stays activity, not watched', () {
    expect(service.activityLine(_item(viewCount: 1), selfName: 'Michel').scope, ItemWatchersScope.activity);
  });
}
