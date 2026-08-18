import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/models/plex/plex_home_user.dart';
import 'package:pleya/profiles/plex_self_account.dart';
import 'package:pleya/profiles/profile.dart';

const _adminUuid = '11111111-1111-1111-1111-111111111111';
const _kidUuid = '22222222-2222-2222-2222-222222222222';

PlexHomeUser _user(String uuid, {required int id, bool admin = false}) => PlexHomeUser(
  id: id,
  uuid: uuid,
  title: 'user$id',
  username: null,
  email: null,
  friendlyName: null,
  thumb: '',
  hasPassword: false,
  restricted: false,
  updatedAt: null,
  admin: admin,
  guest: false,
  protected: false,
);

Map<String, List<PlexHomeUser>> _oneAccount({String connection = 'plex.dev1'}) => {
  connection: [_user(_adminUuid, id: 67, admin: true), _user(_kidUuid, id: 68)],
};

void main() {
  test('a Plex Home profile resolves to its own home user', () {
    final id = plexHomeProfileId(accountConnectionId: 'plex.dev1', homeUserUuid: _kidUuid);
    expect(plexSelfAccountIdIn(id, _oneAccount()), 68);
  });

  test('a Plex Home profile on an unknown connection resolves to nothing', () {
    final id = plexHomeProfileId(accountConnectionId: 'plex.other', homeUserUuid: _kidUuid);
    expect(plexSelfAccountIdIn(id, _oneAccount()), isNull);
  });

  // Without this the signed-in admin was never recognised outside Plex Home,
  // so their own stream was drawn as somebody else watching.
  group('outside Plex Home', () {
    test('a local profile falls back to the account admin', () {
      expect(plexSelfAccountIdIn('local-abc', _oneAccount()), 67);
    });

    test('no profile at all falls back the same way', () {
      expect(plexSelfAccountIdIn(null, _oneAccount()), 67);
    });

    test('two Plex accounts leave it unanswered rather than guess', () {
      final two = {
        ..._oneAccount(),
        'plex.dev2': [_user(_kidUuid, id: 99, admin: true)],
      };
      expect(plexSelfAccountIdIn('local-abc', two), isNull);
    });

    test('an account whose Home list has no admin resolves to nothing', () {
      expect(
        plexSelfAccountIdIn('local-abc', {
          'plex.dev1': [_user(_kidUuid, id: 68)],
        }),
        isNull,
      );
    });

    test('nothing cached resolves to nothing', () {
      expect(plexSelfAccountIdIn('local-abc', const {}), isNull);
    });
  });
}
