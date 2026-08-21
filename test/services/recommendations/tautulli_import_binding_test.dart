import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/models/plex/plex_home_user.dart';
import 'package:pleya/services/recommendations/tautulli_import_binding.dart';
import 'package:pleya/services/tautulli/tautulli_constants.dart';
import 'package:pleya/services/tautulli/tautulli_server_integration.dart';

const _adminUuid = 'aaaaaaaa-1111-2222-3333-444444444444';
const _kidUuid = 'bbbbbbbb-1111-2222-3333-444444444444';
const _adminProfile = 'plex-home-conn1-$_adminUuid';
const _kidProfile = 'plex-home-conn1-$_kidUuid';

PlexHomeUser _user({required int id, required String uuid, required bool admin}) => PlexHomeUser(
  id: id,
  uuid: uuid,
  title: 'u$id',
  thumb: '',
  hasPassword: false,
  restricted: false,
  updatedAt: null,
  admin: admin,
  guest: false,
  protected: false,
);

final _home = <String, List<PlexHomeUser>>{
  'conn1': [_user(id: 4725462, uuid: _adminUuid, admin: true), _user(id: 564993903, uuid: _kidUuid, admin: false)],
};

TautulliServerIntegration _integration({
  String machineIdentifier = 'pms-1',
  String? token = 'tok',
  TautulliConnectionState state = TautulliConnectionState.connected,
  bool? policy,
  bool conflict = false,
}) => TautulliServerIntegration(
  machineIdentifier: machineIdentifier,
  baseUrl: 'https://tautulli.example',
  authMode: TautulliAuthMode.device,
  token: token,
  connectionState: state,
  useHistoryForRecommendations: policy,
  hasUnresolvedConflict: conflict,
);

TautulliImportBinding _resolve({
  bool personalized = true,
  TautulliServerIntegration? integration,
  String? profileId = _adminProfile,
  Map<String, List<PlexHomeUser>>? homeUsers,
  List<String> servers = const ['pms-1'],
  bool hasClient = true,
}) => resolveTautulliImportBinding(
  personalizedRecommendationsEnabled: personalized,
  integration: integration ?? _integration(),
  activeProfileId: profileId,
  homeUsers: homeUsers ?? _home,
  registeredServerIds: servers,
  hasCatalogueClient: (_) => hasClient,
);

TautulliImportRefusalReason _refusal(TautulliImportBinding b) => (b as TautulliImportRefusal).reason;

void main() {
  group('refusals', () {
    test('personalized recommendations off', () {
      expect(_refusal(_resolve(personalized: false)), TautulliImportRefusalReason.personalizedRecommendationsOff);
    });

    test('no integration', () {
      final binding = resolveTautulliImportBinding(
        personalizedRecommendationsEnabled: true,
        integration: null,
        activeProfileId: _adminProfile,
        homeUsers: _home,
        registeredServerIds: const ['pms-1'],
        hasCatalogueClient: (_) => true,
      );
      expect(_refusal(binding), TautulliImportRefusalReason.noIntegration);
    });

    test('the admin policy is off', () {
      expect(_refusal(_resolve(integration: _integration(policy: false))), TautulliImportRefusalReason.importDisabled);
    });

    test('the integration is disconnected', () {
      expect(
        _refusal(_resolve(integration: _integration(state: TautulliConnectionState.disconnected))),
        TautulliImportRefusalReason.importDisabled,
      );
    });

    test('the credential is gone', () {
      expect(_refusal(_resolve(integration: _integration(token: null))), TautulliImportRefusalReason.importDisabled);
    });

    test('a migration conflict is unresolved', () {
      expect(_refusal(_resolve(integration: _integration(conflict: true))), TautulliImportRefusalReason.importDisabled);
    });

    test('no active profile', () {
      expect(_refusal(_resolve(profileId: null)), TautulliImportRefusalReason.noActiveProfile);
      expect(_refusal(_resolve(profileId: '')), TautulliImportRefusalReason.noActiveProfile);
    });

    test('an ambiguous user: two Plex accounts and no Home match', () {
      final twoAccounts = {
        'conn1': [_user(id: 1, uuid: 'x', admin: true)],
        'conn2': [_user(id: 2, uuid: 'y', admin: true)],
      };
      expect(
        _refusal(_resolve(profileId: 'local-profile', homeUsers: twoAccounts)),
        TautulliImportRefusalReason.ambiguousUser,
      );
    });

    test('a Home profile whose uuid is not in the list', () {
      expect(
        _refusal(_resolve(profileId: 'plex-home-conn1-cccccccc-1111-2222-3333-444444444444')),
        TautulliImportRefusalReason.ambiguousUser,
      );
    });

    test('an empty machine identifier', () {
      expect(
        _refusal(_resolve(integration: _integration(machineIdentifier: ''))),
        TautulliImportRefusalReason.serverNotRegistered,
      );
    });

    test('an identifier that matches no registered server', () {
      // Deliberately stricter than tautulliMonitoredServer, which would fall
      // back to "the only owned server". A wrong guess writes another server's
      // titles into a permanent taste profile.
      expect(_refusal(_resolve(servers: const ['pms-other'])), TautulliImportRefusalReason.serverNotRegistered);
      expect(_refusal(_resolve(servers: const [])), TautulliImportRefusalReason.serverNotRegistered);
    });

    test('no catalogue client for the server', () {
      expect(_refusal(_resolve(hasClient: false)), TautulliImportRefusalReason.noCatalogueClient);
    });
  });

  group('targets', () {
    test('the admin profile resolves to its own account id', () {
      final target = _resolve() as TautulliImportTarget;
      expect(target.userId, 4725462);
      expect(target.serverId, ServerId('pms-1'));
      expect(target.machineIdentifier, 'pms-1');
      expect(target.activeProfileId, _adminProfile);
    });

    test('a regular profile consumes the admin-authorised integration', () {
      // The whole point of the server-scoped record: no admin rights needed to
      // use it, and the row filter is still this profile's own account id.
      final target = _resolve(profileId: _kidProfile) as TautulliImportTarget;
      expect(target.userId, 564993903);
      expect(target.activeProfileId, _kidProfile);
      expect(target.serverId, ServerId('pms-1'));
    });

    test('two profiles on one server never share a user id', () {
      final admin = _resolve() as TautulliImportTarget;
      final kid = _resolve(profileId: _kidProfile) as TautulliImportTarget;
      expect(admin.userId, isNot(kid.userId));
      expect(admin.activeProfileId, isNot(kid.activeProfileId));
    });

    test('a single non-Home Plex account resolves to its admin entry', () {
      final target =
          _resolve(
                profileId: 'local-profile',
                homeUsers: {
                  'conn1': [_user(id: 99, uuid: 'z', admin: true)],
                },
              )
              as TautulliImportTarget;
      expect(target.userId, 99);
    });

    test('an explicit policy of true resolves like the default', () {
      expect(_resolve(integration: _integration(policy: true)), isA<TautulliImportTarget>());
    });

    test('the right server is picked out of several', () {
      final target = _resolve(servers: const ['pms-other', 'pms-1', 'pms-third']) as TautulliImportTarget;
      expect(target.machineIdentifier, 'pms-1');
    });
  });
}
