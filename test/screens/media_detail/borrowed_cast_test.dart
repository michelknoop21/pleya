import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_role.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/screens/media_detail/borrowed_cast.dart';
import 'package:pleya/utils/global_key_utils.dart';

class _Source extends Fake implements MediaServerClient {
  _Source(this.roles, {this.fails = false});

  final List<MediaRole> roles;
  final bool fails;
  final List<String> asked = [];

  @override
  Future<MediaItem?> fetchItem(String id) async {
    asked.add(id);
    if (fails) throw StateError('offline');
    return MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Coyote vs Acme', roles: roles);
  }
}

void main() {
  final pageKey = buildGlobalKey(ServerId('pleya-server'), 'item-1');
  final plexKey = buildGlobalKey(ServerId('plex'), '14345');
  final jellyfinKey = buildGlobalKey(ServerId('jellyfin'), 'abc');

  // What Pleya Server sends: names and parts, no picture and no id.
  const pageRoles = [MediaRole(tag: 'Will Forte', role: 'Kevin Avery'), MediaRole(tag: 'Lana Condor', role: 'Paige')];

  test('a cast list without pictures takes them from another source, matched on name', () async {
    final plex = _Source(const [
      MediaRole(id: '9', tag: ' will  forte ', thumbPath: 'https://metadata-static.plex.tv/people/wf.jpg'),
      MediaRole(id: '10', tag: 'Somebody Else', thumbPath: 'https://metadata-static.plex.tv/people/se.jpg'),
    ]);

    final borrowed = await borrowCastPhotos(
      pageRoles: pageRoles,
      pageSourceKey: pageKey,
      sourceKeys: [pageKey, plexKey],
      clientFor: (id) => id == ServerId('plex') ? plex : null,
    );

    expect(plex.asked, ['14345']);
    final forte = BorrowedCast.resolve(pageRoles[0], null, borrowed);
    expect(forte.thumbPath, 'https://metadata-static.plex.tv/people/wf.jpg');
    expect(forte.client, same(plex), reason: 'the path only means something on the server it came from');
    final condor = BorrowedCast.resolve(pageRoles[1], null, borrowed);
    expect(condor.thumbPath, isNull, reason: 'nobody else\'s picture is used for her');
    expect(borrowed!.thumbByName, hasLength(1));
  });

  test('a page that has pictures of its own asks nobody', () async {
    final plex = _Source(const [MediaRole(tag: 'Will Forte', thumbPath: '/other.jpg')]);

    final borrowed = await borrowCastPhotos(
      pageRoles: const [
        MediaRole(tag: 'Will Forte', thumbPath: '/own.jpg'),
        MediaRole(tag: 'Lana Condor'),
      ],
      pageSourceKey: pageKey,
      sourceKeys: [pageKey, plexKey],
      clientFor: (_) => plex,
    );

    expect(borrowed, isNull);
    expect(plex.asked, isEmpty);
  });

  test('a source that fails or has no pictures is skipped for the next one', () async {
    final plex = _Source(const [], fails: true);
    final jellyfin = _Source(const [MediaRole(tag: 'Lana Condor', thumbPath: '/Items/p1/Images/Primary')]);

    final borrowed = await borrowCastPhotos(
      pageRoles: pageRoles,
      pageSourceKey: pageKey,
      sourceKeys: [pageKey, plexKey, jellyfinKey],
      clientFor: (id) => id == ServerId('plex') ? plex : jellyfin,
    );

    expect(BorrowedCast.resolve(pageRoles[1], null, borrowed).client, same(jellyfin));
  });

  test('without another source there is nothing to borrow', () async {
    final borrowed = await borrowCastPhotos(
      pageRoles: pageRoles,
      pageSourceKey: pageKey,
      sourceKeys: [pageKey],
      clientFor: (_) => fail('no other source to ask'),
    );

    expect(borrowed, isNull);
  });

  test('a role keeps its own picture when it has one', () {
    final lender = _Source(const []);
    const own = MediaRole(tag: 'Will Forte', thumbPath: '/own.jpg');

    final picture = BorrowedCast.resolve(
      own,
      null,
      BorrowedCast(client: lender, thumbByName: const {'will forte': '/lent.jpg'}),
    );

    expect(picture.thumbPath, '/own.jpg');
    expect(picture.client, isNull);
  });
}
