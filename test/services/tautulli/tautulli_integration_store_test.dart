import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/tautulli/tautulli_account_store.dart';
import 'package:pleya/services/tautulli/tautulli_constants.dart';
import 'package:pleya/services/tautulli/tautulli_integration_store.dart';
import 'package:pleya/services/tautulli/tautulli_server_integration.dart';
import 'package:pleya/services/tautulli/tautulli_session.dart';

import '../../test_helpers/prefs.dart';

TautulliSession _session({
  String url = 'https://tautulli.example',
  String token = 'tok',
  String? machineIdentifier = 'pms-1',
}) => TautulliSession(
  baseUrl: url,
  authMode: TautulliAuthMode.device,
  token: token,
  machineIdentifier: machineIdentifier,
);

void main() {
  final store = TautulliIntegrationStore.instance;

  setUp(resetSharedPreferencesForTest);

  group('storage', () {
    test('keys are server-scoped, not profile-scoped', () async {
      expect(TautulliIntegrationStore.keyFor('pms-1'), 'tautulli_integration_pms-1');
      await store.save(
        TautulliServerIntegration(
          machineIdentifier: 'pms-1',
          baseUrl: 'https://a',
          authMode: TautulliAuthMode.device,
          token: 'tok',
        ),
      );
      final prefs = await BaseSharedPreferencesService.sharedCache();
      expect(prefs.keys, contains('tautulli_integration_pms-1'));
      expect(prefs.keys.any((k) => k.startsWith('user_')), isFalse);
    });

    test('two servers live side by side', () async {
      for (final id in ['pms-1', 'pms-2']) {
        await store.save(
          TautulliServerIntegration(
            machineIdentifier: id,
            baseUrl: 'https://$id',
            authMode: TautulliAuthMode.device,
            token: 'tok-$id',
          ),
        );
      }
      final all = await store.loadAll();
      expect(all.keys, containsAll(['pms-1', 'pms-2']));
      expect(all['pms-2']!.token, 'tok-pms-2');
    });

    test('an unreadable record is skipped without taking the others down', () async {
      await store.save(
        TautulliServerIntegration(
          machineIdentifier: 'pms-1',
          baseUrl: 'https://a',
          authMode: TautulliAuthMode.device,
          token: 'tok',
        ),
      );
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setString('tautulli_integration_broken', 'not json at all');
      final all = await store.loadAll();
      expect(all.keys, ['pms-1']);
    });

    test('remove deletes the record', () async {
      await store.save(
        TautulliServerIntegration(
          machineIdentifier: 'pms-1',
          baseUrl: 'https://a',
          authMode: TautulliAuthMode.device,
          token: 'tok',
        ),
      );
      await store.remove('pms-1');
      expect(await store.loadAll(), isEmpty);
    });
  });

  group('legacy migration', () {
    test('a session with a server identifier becomes an integration', () async {
      await TautulliAccountStore.instance.save('uuid-a', _session());
      final migrated = await store.migrateLegacySession('uuid-a');

      expect(migrated, isNotNull);
      expect(migrated!.machineIdentifier, 'pms-1');
      expect(migrated.token, 'tok');
      expect(migrated.useHistoryForRecommendations, isNull, reason: 'an existing pairing keeps working, on by default');
      expect(importEnabled(migrated), isTrue);
      expect(migrated.configuredByProfileId, 'uuid-a');

      expect(await store.loadAll(), contains('pms-1'));
      expect(await TautulliAccountStore.instance.load('uuid-a'), isNull, reason: 'legacy key removed');
    });

    test('a session without a server identifier stays profile-scoped', () async {
      await TautulliAccountStore.instance.save('uuid-a', _session(machineIdentifier: null));
      final migrated = await store.migrateLegacySession('uuid-a');

      expect(migrated, isNull);
      expect(await store.loadAll(), isEmpty);
      expect(await TautulliAccountStore.instance.load('uuid-a'), isNotNull, reason: 'left where it was');
    });

    test('nothing to migrate is not an error', () async {
      expect(await store.migrateLegacySession('uuid-a'), isNull);
      expect(await store.loadAll(), isEmpty);
    });

    test('an identical second legacy session is a duplicate, not a conflict', () async {
      // Two profiles paired the same instance with the same credential.
      await TautulliAccountStore.instance.save('uuid-a', _session());
      await store.migrateLegacySession('uuid-a');
      await TautulliAccountStore.instance.save('uuid-b', _session());

      final result = await store.migrateLegacySession('uuid-b');
      expect(result!.hasUnresolvedConflict, isFalse);
      expect(importEnabled(result), isTrue);
      expect(await TautulliAccountStore.instance.load('uuid-b'), isNull);
      expect((await store.loadAll()).length, 1);
    });

    test('two different legacy pairings for one server fail closed', () async {
      // Same server, different URL and different credential. There is no
      // recency on a prefs key, so picking one would be a coin flip over whose
      // credential the household runs on.
      await TautulliAccountStore.instance.save('uuid-a', _session(url: 'https://a', token: 'tok-a'));
      await store.migrateLegacySession('uuid-a');
      await TautulliAccountStore.instance.save('uuid-b', _session(url: 'https://b', token: 'tok-b'));

      final result = await store.migrateLegacySession('uuid-b');

      expect(result!.hasUnresolvedConflict, isTrue);
      expect(importEnabled(result), isFalse, reason: 'no profile consumes it until an admin re-pairs');
      // Credentials are never merged: the surviving record keeps its own.
      expect(result.baseUrl, 'https://a');
      expect(result.token, 'tok-a');
      // Persisted, so the conflict is not rediscovered on every launch, and the
      // legacy blob is cleared rather than left to re-trigger it.
      expect((await store.loadAll())['pms-1']!.hasUnresolvedConflict, isTrue);
      expect(await TautulliAccountStore.instance.load('uuid-b'), isNull);
    });

    test('a conflict is deterministic regardless of how many profiles collide', () async {
      await TautulliAccountStore.instance.save('uuid-a', _session(url: 'https://a', token: 'tok-a'));
      await store.migrateLegacySession('uuid-a');
      for (final uuid in ['uuid-b', 'uuid-c', 'uuid-d']) {
        await TautulliAccountStore.instance.save('uuid-x', _session(url: 'https://$uuid', token: 'tok-$uuid'));
        final result = await store.migrateLegacySession('uuid-x');
        expect(result!.token, 'tok-a', reason: 'the surviving credential never changes');
        expect(result.hasUnresolvedConflict, isTrue);
      }
      expect((await store.loadAll()).length, 1);
    });

    test('re-pairing after a conflict clears it', () async {
      await TautulliAccountStore.instance.save('uuid-a', _session(url: 'https://a', token: 'tok-a'));
      await store.migrateLegacySession('uuid-a');
      await TautulliAccountStore.instance.save('uuid-b', _session(url: 'https://b', token: 'tok-b'));
      await store.migrateLegacySession('uuid-b');

      final existing = (await store.loadAll())['pms-1'];
      final repaired = TautulliServerIntegration.fromSession(
        _session(url: 'https://chosen', token: 'tok-chosen'),
        machineIdentifier: 'pms-1',
        existing: existing,
      );
      await store.save(repaired);

      final after = (await store.loadAll())['pms-1']!;
      expect(after.hasUnresolvedConflict, isFalse);
      expect(after.token, 'tok-chosen');
      expect(importEnabled(after), isTrue);
    });

    test('a conflict does not disturb another server', () async {
      await store.save(
        TautulliServerIntegration(
          machineIdentifier: 'pms-2',
          baseUrl: 'https://other',
          authMode: TautulliAuthMode.device,
          token: 'tok-2',
        ),
      );
      await TautulliAccountStore.instance.save('uuid-a', _session(url: 'https://a', token: 'tok-a'));
      await store.migrateLegacySession('uuid-a');
      await TautulliAccountStore.instance.save('uuid-b', _session(url: 'https://b', token: 'tok-b'));
      await store.migrateLegacySession('uuid-b');

      final all = await store.loadAll();
      expect(all['pms-1']!.hasUnresolvedConflict, isTrue);
      expect(all['pms-2']!.hasUnresolvedConflict, isFalse);
      expect(importEnabled(all['pms-2']), isTrue);
    });
  });
}
