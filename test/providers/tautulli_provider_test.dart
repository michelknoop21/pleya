import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/providers/tautulli_provider.dart';
import 'package:pleya/services/tautulli/tautulli_account_store.dart';
import 'package:pleya/services/tautulli/tautulli_constants.dart';
import 'package:pleya/services/tautulli/tautulli_integration_store.dart';
import 'package:pleya/services/tautulli/tautulli_server_integration.dart';
import 'package:pleya/services/tautulli/tautulli_session.dart';

import '../test_helpers/prefs.dart';

const _machine = 'pms-1';

TautulliSession _session({String url = 'https://tautulli.example', String token = 'tok', String? id = _machine}) =>
    TautulliSession(baseUrl: url, authMode: TautulliAuthMode.device, token: token, machineIdentifier: id);

void main() {
  setUp(resetSharedPreferencesForTest);

  /// [isAdmin] is the only difference between the two kinds of profile.
  Future<TautulliProvider> provider({
    bool isAdmin = true,
    List<String> servers = const [_machine],
    String uuid = 'uuid-a',
  }) async {
    final p = TautulliProvider();
    p.attachServerResolvers(serverIds: () => servers, isOwnerOrAdmin: (_) => isAdmin);
    await p.onActiveProfileChanged(uuid);
    return p;
  }

  Future<void> seedIntegration({bool? policy, TautulliConnectionState? state, String? token = 'tok'}) =>
      TautulliIntegrationStore.instance.save(
        TautulliServerIntegration(
          machineIdentifier: _machine,
          baseUrl: 'https://tautulli.example',
          authMode: TautulliAuthMode.device,
          token: token,
          connectionState: state ?? TautulliConnectionState.connected,
          useHistoryForRecommendations: policy,
        ),
      );

  group('who sees what', () {
    test('an admin profile gets the full admin surface', () async {
      await seedIntegration();
      final p = await provider();
      expect(p.isConfigured, isTrue);
      expect(p.client, isNotNull);
      expect(p.adminStatus, isNotNull);
      expect(p.machineIdentifier, _machine);
      addTearDown(p.dispose);
    });

    test('a regular profile sees no admin surface but can still import', () async {
      // The product requirement in one test: no toggle, no credential, no
      // Tautulli anywhere in the UI, and their own history still gets used.
      await seedIntegration();
      final p = await provider(isAdmin: false, uuid: 'uuid-kid');
      expect(p.isConfigured, isFalse);
      expect(p.client, isNull);
      expect(p.session, isNull);
      expect(p.adminStatus, isNull);
      expect(p.enabledImportServerIds(), {_machine});
      addTearDown(p.dispose);
    });

    test('a profile without the server sees nothing at all', () async {
      await seedIntegration();
      final p = await provider(servers: const ['other-server']);
      expect(p.isConfigured, isFalse);
      expect(p.adminStatus, isNull);
      addTearDown(p.dispose);
    });

    test('a server registering late is picked up', () async {
      await seedIntegration();
      var servers = <String>[];
      final p = TautulliProvider();
      p.attachServerResolvers(serverIds: () => servers, isOwnerOrAdmin: (_) => true);
      await p.onActiveProfileChanged('uuid-a');
      expect(p.isConfigured, isFalse);

      servers = [_machine];
      p.refreshBinding();
      expect(p.isConfigured, isTrue);
      addTearDown(p.dispose);
    });
  });

  group('state transitions', () {
    test('a fresh pairing is enabled without anyone switching anything', () async {
      final p = await provider();
      await p.commit(_session());
      expect(p.historyForRecommendations, isTrue);
      expect(p.enabledImportServerIds(), {_machine});
      expect(p.adminStatus!.historyPolicy, isNull);
      addTearDown(p.dispose);
    });

    test('the admin switching it off excludes the server at once', () async {
      final p = await provider();
      await p.commit(_session());
      await p.setHistoryForRecommendations(false);

      expect(p.historyForRecommendations, isFalse);
      expect(p.enabledImportServerIds(), isEmpty);
      expect((await TautulliIntegrationStore.instance.loadAll())[_machine]!.policyChangedAtMs, isNotNull);
      // Persisted, not just in memory.
      expect((await TautulliIntegrationStore.instance.loadAll())[_machine]!.useHistoryForRecommendations, isFalse);
      addTearDown(p.dispose);
    });

    test('switching it back on restores it without re-downloading anything', () async {
      final p = await provider();
      await p.commit(_session());
      await p.setHistoryForRecommendations(false);
      await p.setHistoryForRecommendations(true);
      expect(p.enabledImportServerIds(), {_machine});
      expect(p.adminStatus!.historyPolicy, isTrue);
      addTearDown(p.dispose);
    });

    test('disconnecting excludes the server but keeps the policy', () async {
      final p = await provider();
      await p.commit(_session());
      await p.setHistoryForRecommendations(false);
      await p.disconnect();

      expect(p.isConfigured, isFalse);
      expect(p.enabledImportServerIds(), isEmpty);
      final stored = (await TautulliIntegrationStore.instance.loadAll())[_machine]!;
      expect(stored.connectionState, TautulliConnectionState.disconnected);
      expect(stored.hasCredential, isFalse, reason: 'the credential is gone');
      expect(stored.useHistoryForRecommendations, isFalse, reason: 'removing a credential is not revoking a decision');
      addTearDown(p.dispose);
    });

    test('reconnecting the same server keeps an earlier explicit off', () async {
      final p = await provider();
      await p.commit(_session());
      await p.setHistoryForRecommendations(false);
      await p.disconnect();
      await p.commit(_session(token: 'new-token'));

      expect(p.isConfigured, isTrue);
      expect(p.historyForRecommendations, isFalse);
      expect(p.enabledImportServerIds(), isEmpty);
      addTearDown(p.dispose);
    });

    test('a genuinely new server starts on the default', () async {
      final p = await provider(servers: const [_machine, 'pms-2']);
      await p.commit(_session());
      await p.setHistoryForRecommendations(false);
      await p.commit(_session(id: 'pms-2', token: 'tok-2'));
      expect(p.enabledImportServerIds(), {'pms-2'}, reason: 'pms-1 stays off, pms-2 starts on');
      addTearDown(p.dispose);
    });

    test('an unreadable credential disables import but keeps the record', () async {
      await seedIntegration(policy: true, token: null);
      final p = await provider();
      expect(p.enabledImportServerIds(), isEmpty);
      expect(p.adminStatus, isNotNull);
      expect(p.adminStatus!.historyPolicy, isTrue);
      addTearDown(p.dispose);
    });
  });

  group('scoping to what this profile has', () {
    test('a server the profile does not have is neither scored nor fetched', () async {
      await seedIntegration();
      // The record is device-wide by design, so the pairing exists. Having the
      // *server* is a separate question, and it is the one that decides whether
      // this profile's taste may be built on history from it.
      final p = await provider(servers: const ['some-other-server']);
      expect(p.enabledImportServerIds(), isEmpty);
      expect(await p.fetchImportHistory(ServerId(_machine), profileId: 'uuid-a', length: 5, start: 0), isNull);
      addTearDown(p.dispose);
    });

    test('a server registering late is included from then on', () async {
      await seedIntegration();
      var servers = <String>[];
      final p = TautulliProvider();
      p.attachServerResolvers(serverIds: () => servers, isOwnerOrAdmin: (_) => true);
      await p.onActiveProfileChanged('uuid-a');
      expect(p.enabledImportServerIds(), isEmpty);

      servers = [_machine];
      p.refreshBinding();
      expect(p.enabledImportServerIds(), {_machine});
      addTearDown(p.dispose);
    });
  });

  group('hydration readiness', () {
    test('is not announced before the store has been read', () async {
      await seedIntegration();
      final p = TautulliProvider();
      p.attachServerResolvers(serverIds: () => const [_machine], isOwnerOrAdmin: (_) => true);
      expect(p.isHydrated, isFalse, reason: 'an empty map before the load is not an answer');

      var ready = false;
      unawaited(p.whenHydrated().then((_) => ready = true));
      final load = p.onActiveProfileChanged('uuid-a');
      expect(p.isHydrated, isFalse);

      await load;
      await pumpEventQueue();
      expect(p.isHydrated, isTrue);
      expect(ready, isTrue);
      expect(p.enabledImportServerIds(), {_machine});
      addTearDown(p.dispose);
    });

    test('a profile switch waits again, and never strands the previous waiter', () async {
      await seedIntegration();
      final p = await provider(uuid: 'uuid-a');
      expect(p.isHydrated, isTrue);
      final firstWait = p.whenHydrated();

      final second = p.onActiveProfileChanged('uuid-b');
      expect(p.isHydrated, isFalse, reason: 'the new profile has its own answer to wait for');
      await firstWait; // completes rather than hanging
      await second;
      expect(p.isHydrated, isTrue);
      addTearDown(p.dispose);
    });

    test('dispose releases anyone still waiting', () async {
      final p = TautulliProvider();
      final waiting = p.whenHydrated();
      p.dispose();
      await waiting; // would hang before
    });
  });

  group('the admin gate', () {
    test('a regular profile cannot change the policy', () async {
      await seedIntegration();
      final p = await provider(isAdmin: false);
      await p.setHistoryForRecommendations(false);
      expect(
        (await TautulliIntegrationStore.instance.loadAll())[_machine]!.useHistoryForRecommendations,
        isNull,
        reason: 'the write is refused below the UI, not only in it',
      );
      addTearDown(p.dispose);
    });

    test('a regular profile cannot disconnect', () async {
      await seedIntegration();
      final p = await provider(isAdmin: false);
      await p.disconnect();
      final stored = (await TautulliIntegrationStore.instance.loadAll())[_machine]!;
      expect(stored.connectionState, TautulliConnectionState.connected);
      expect(stored.hasCredential, isTrue);
      addTearDown(p.dispose);
    });

    test('a regular profile cannot re-pair over the admin credential', () async {
      await seedIntegration();
      final p = await provider(isAdmin: false);
      await p.commit(_session(token: 'stolen'));
      expect((await TautulliIntegrationStore.instance.loadAll())[_machine]!.token, 'tok');
      addTearDown(p.dispose);
    });
  });

  group('legacy pairings', () {
    test('a session without a server identifier stays profile-scoped', () async {
      final p = await provider();
      await p.commit(_session(id: null));
      expect(p.isConfigured, isTrue, reason: 'the presence surfaces keep working');
      expect(p.adminStatus, isNull);
      expect(p.enabledImportServerIds(), isEmpty, reason: 'it can never import');
      expect(await TautulliAccountStore.instance.load('uuid-a'), isNotNull);
      addTearDown(p.dispose);
    });

    test('a legacy session with an identifier migrates on profile bind', () async {
      await TautulliAccountStore.instance.save('uuid-a', _session());
      final p = await provider();
      expect(p.adminStatus, isNotNull);
      expect(p.enabledImportServerIds(), {_machine});
      expect(await TautulliAccountStore.instance.load('uuid-a'), isNull);
      addTearDown(p.dispose);
    });

    test('re-pairing clears this profile\'s superseded legacy blob', () async {
      // Otherwise the next launch finds a legacy pairing for a server that
      // already has a record, sees a different URL and token, and flags the
      // fresh record as conflicted — so fixing a broken instance would switch
      // import off one restart later, silently.
      await TautulliAccountStore.instance.save('uuid-a', _session(url: 'https://old', token: 'old-tok'));
      final p = await provider();
      await p.commit(_session(url: 'https://new', token: 'new-tok'));

      expect(await TautulliAccountStore.instance.load('uuid-a'), isNull);
      expect(p.enabledImportServerIds(), {_machine});

      // Prove it survives the restart, which is where the old bug landed.
      final restarted = await provider();
      expect(restarted.hasIntegrationConflict, isFalse);
      expect(restarted.enabledImportServerIds(), {_machine});
      addTearDown(p.dispose);
      addTearDown(restarted.dispose);
    });

    test('re-pairing clears a housemate\'s superseded blob too', () async {
      // The household version of the same trap. Clearing only the active
      // profile's blob leaves the other one to be discovered on whichever
      // launch *that* profile is active, where it flags the fresh record as
      // conflicted and switches import off for everyone.
      await TautulliAccountStore.instance.save('uuid-a', _session(url: 'https://old', token: 'old-tok'));
      await TautulliAccountStore.instance.save('uuid-b', _session(url: 'https://old', token: 'old-tok'));

      final admin = await provider(uuid: 'uuid-a');
      await admin.commit(_session(url: 'https://new', token: 'new-tok'));
      expect(await TautulliAccountStore.instance.load('uuid-b'), isNull);

      final housemate = await provider(uuid: 'uuid-b');
      expect(housemate.hasIntegrationConflict, isFalse);
      expect(housemate.enabledImportServerIds(), {_machine});
      addTearDown(admin.dispose);
      addTearDown(housemate.dispose);
    });

    test('a pairing for a different server is left alone', () async {
      await TautulliAccountStore.instance.save('uuid-b', _session(id: 'pms-other', token: 'other-tok'));
      final p = await provider();
      await p.commit(_session(token: 'new-tok'));
      expect(await TautulliAccountStore.instance.load('uuid-b'), isNotNull);
      addTearDown(p.dispose);
    });

    test('two conflicting legacy pairings disable import until an admin re-pairs', () async {
      await TautulliAccountStore.instance.save('uuid-a', _session(url: 'https://a', token: 'tok-a'));
      final first = await provider(uuid: 'uuid-a');
      expect(first.enabledImportServerIds(), {_machine});
      first.dispose();

      await TautulliAccountStore.instance.save('uuid-b', _session(url: 'https://b', token: 'tok-b'));
      final second = await provider(uuid: 'uuid-b');
      expect(second.enabledImportServerIds(), isEmpty);
      expect(second.hasIntegrationConflict, isTrue);

      await second.commit(_session(url: 'https://chosen', token: 'tok-chosen'));
      expect(second.hasIntegrationConflict, isFalse);
      expect(second.enabledImportServerIds(), {_machine});
      addTearDown(second.dispose);
    });
  });

  test('fetchImportHistory refuses once the integration is no longer enabled', () async {
    await seedIntegration(policy: false);
    final p = await provider();
    final page = await p.fetchImportHistory(ServerId(_machine), profileId: 'uuid-a', length: 10, start: 0);
    expect(page, isNull);
    addTearDown(p.dispose);
  });

  test('fetchImportHistory refuses an unknown server', () async {
    await seedIntegration();
    final p = await provider();
    expect(await p.fetchImportHistory(ServerId('nope'), profileId: 'uuid-a', length: 10, start: 0), isNull);
    addTearDown(p.dispose);
  });
}
