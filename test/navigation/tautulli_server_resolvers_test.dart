import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/navigation/profile_session_screen.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/tautulli_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/tautulli/tautulli_constants.dart';
import 'package:pleya/services/tautulli/tautulli_integration_store.dart';
import 'package:pleya/services/tautulli/tautulli_server_integration.dart';
import 'package:pleya/services/tautulli/tautulli_session.dart';

import '../test_helpers/prefs.dart';

const _machine = 'pms-1';

/// A borrowed Plex connection: it runs on the owner's token, so the read-side
/// probe says owned, but the profile has no owner rights on the server.
class _BorrowedPlexManager extends MultiServerManager {
  @override
  List<String> get serverIds => const [_machine];

  @override
  bool isOwnerOrAdmin(ServerId serverId) => true;

  @override
  bool canManagePlexServer(ServerId serverId) => false;
}

void main() {
  setUp(resetSharedPreferencesForTest);

  test('the session wiring lets a borrowed Plex connection read Tautulli but not pair or unlink it', () async {
    await TautulliIntegrationStore.instance.save(
      const TautulliServerIntegration(
        machineIdentifier: _machine,
        baseUrl: 'https://tautulli.example',
        authMode: TautulliAuthMode.device,
        token: 'owner-key',
      ),
    );
    final manager = _BorrowedPlexManager();
    final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    final provider = TautulliProvider();
    addTearDown(() {
      provider.dispose();
      multiServer.dispose();
      manager.dispose();
    });

    attachTautulliServerResolvers(provider, multiServer: multiServer, plexHome: null);
    await provider.onActiveProfileChanged('uuid-kid');
    expect(provider.adminStatus, isNotNull, reason: 'reading stays on isOwnerOrAdmin');

    await provider.disconnect();
    await provider.commit(
      const TautulliSession(
        baseUrl: 'https://tautulli.example',
        authMode: TautulliAuthMode.device,
        token: 'borrowed-key',
        machineIdentifier: _machine,
      ),
    );

    final stored = (await TautulliIntegrationStore.instance.loadAll())[_machine]!;
    expect(stored.connectionState, TautulliConnectionState.connected, reason: 'unlink refused');
    expect(stored.token, 'owner-key', reason: 'pair refused');
  });
}
