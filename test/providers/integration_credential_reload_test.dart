import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/providers/tautulli_provider.dart';
import 'package:pleya/services/seerr/seerr_session.dart';
import 'package:pleya/services/tautulli/tautulli_constants.dart';
import 'package:pleya/services/tautulli/tautulli_integration_store.dart';
import 'package:pleya/services/tautulli/tautulli_server_integration.dart';
import 'package:pleya/services/tautulli/tautulli_session.dart';

import '../test_helpers/seerr_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('in-flight Seerr hydration cannot reactivate a locally disconnected client', () async {
    final store = _HeldSeerrStore()..sessions['profile'] = seerrSession();
    final provider = SeerrProvider(store: store);
    addTearDown(provider.dispose);
    await provider.onActiveProfileChanged('profile');
    store.hold = true;
    final loading = provider.onActiveProfileChanged('profile');
    await store.started.future;
    await provider.disconnect();
    store.release.complete();
    await loading;

    expect(provider.isConfigured, isFalse);
    expect(provider.client, isNull);
    expect(store.sessions, isEmpty);
  });

  test('in-flight Tautulli hydration never announces an old live binding after disconnect', () async {
    final store = _HeldTautulliStore();
    final provider = TautulliProvider(store: store);
    addTearDown(provider.dispose);
    provider.attachServerResolvers(
      serverIds: () => ['server'],
      isOwnerOrAdmin: (_) => true,
      mayAdminister: (_) => true,
    );
    await provider.onActiveProfileChanged('profile');
    expect(provider.client, isNotNull);
    store.hold = true;
    final loading = provider.onActiveProfileChanged('profile');
    await store.started.future;
    final announcements = <bool>[];
    provider.addListener(() => announcements.add(provider.client != null));
    final disconnect = provider.disconnect();
    store.release.complete();
    await loading;
    await disconnect;

    expect(provider.client, isNull);
    expect(announcements, isNot(contains(true)));
  });
}

class _HeldSeerrStore extends MemorySeerrStore {
  bool hold = false;
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<SeerrSession?> load(String userUuid) async {
    final result = sessions[userUuid];
    if (hold && !started.isCompleted) {
      started.complete();
      await release.future;
    }
    return result;
  }
}

class _HeldTautulliStore implements TautulliIntegrationStore {
  TautulliServerIntegration integration = const TautulliServerIntegration(
    machineIdentifier: 'server',
    baseUrl: 'https://stats.test',
    authMode: TautulliAuthMode.apiKey,
    token: 'secret',
  );
  bool hold = false;
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<Map<String, TautulliServerIntegration>> loadAll() async {
    final result = {'server': integration};
    if (hold && !started.isCompleted) {
      started.complete();
      await release.future;
    }
    return result;
  }

  @override
  Future<void> save(TautulliServerIntegration value, {bool policyOnly = false}) async => integration = value;
  @override
  Future<TautulliServerIntegration?> migrateLegacySession(String uuid) async => null;
  @override
  Future<TautulliSession?> loadLegacySession(String uuid) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
