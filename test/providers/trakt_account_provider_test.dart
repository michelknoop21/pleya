import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/providers/trakt_account_provider.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/trackers/tracker_account_store.dart';
import 'package:pleya/services/trackers/tracker_constants.dart';
import 'package:pleya/services/trackers/tracker_session.dart';
import 'package:pleya/services/trakt/trakt_scrobble_service.dart';
import 'package:pleya/services/trakt/trakt_sync_service.dart';

import '../test_helpers/prefs.dart';

final _store = trackerAccountStore(TrackerService.trakt);

TrackerSession _session({String? username, String accessToken = 'at', String refreshToken = 'rt'}) {
  return TrackerSession(
    accessToken: accessToken,
    refreshToken: refreshToken,
    expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
    scope: 'public',
    createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    username: username,
  );
}

void main() {
  setUp(resetSharedPreferencesForTest);

  group('TraktAccountProvider', () {
    test('starts disconnected with null session', () {
      final p = TraktAccountProvider(kidsProfileCheck: () async => false);
      expect(p.session, isNull);
      expect(p.isConnected, isFalse);
      expect(p.username, isNull);
      expect(p.isConnecting, isFalse);
      p.dispose();
    });

    test('onActiveProfileChanged loads stored session and notifies', () async {
      // Pre-seed the store for a specific profile uuid.
      const uuid = 'profile-1';
      await _store.save(uuid, _session(username: 'alice'));

      // Reset cached singletons so the provider reads fresh prefs state.
      BaseSharedPreferencesService.resetForTesting();

      final p = TraktAccountProvider(kidsProfileCheck: () async => false);
      var notified = 0;
      p.addListener(() => notified++);

      await p.onActiveProfileChanged(uuid);
      expect(p.isConnected, isTrue);
      expect(p.username, 'alice');
      expect(p.session?.accessToken, 'at');
      // _setSessionAndRebind notifies once.
      expect(notified, greaterThanOrEqualTo(1));

      p.dispose();
    });

    test('onActiveProfileChanged with unknown uuid clears session', () async {
      const uuid = 'profile-1';
      await _store.save(uuid, _session(username: 'alice'));
      BaseSharedPreferencesService.resetForTesting();

      final p = TraktAccountProvider(kidsProfileCheck: () async => false);
      await p.onActiveProfileChanged(uuid);
      expect(p.isConnected, isTrue);

      // Switch to a profile with no stored session.
      await p.onActiveProfileChanged('other-profile');
      expect(p.isConnected, isFalse);
      expect(p.username, isNull);

      p.dispose();
    });

    test('onActiveProfileChanged with null uuid loads from empty/global slot', () async {
      final p = TraktAccountProvider(kidsProfileCheck: () async => false);
      await p.onActiveProfileChanged(null);
      expect(p.isConnected, isFalse);
      p.dispose();
    });

    test('disconnect with no session clears state and notifies', () async {
      final p = TraktAccountProvider(kidsProfileCheck: () async => false);
      var notified = 0;
      p.addListener(() => notified++);

      await p.disconnect();
      expect(p.isConnected, isFalse);
      expect(p.session, isNull);
      // _setSessionAndRebind always notifies.
      expect(notified, 1);

      p.dispose();
    });

    test('late refresh update after disconnect does not restore session', () async {
      const uuid = 'profile-1';
      await _store.save(uuid, _session(username: 'alice'));
      BaseSharedPreferencesService.resetForTesting();

      final p = TraktAccountProvider(kidsProfileCheck: () async => false);
      await p.onActiveProfileChanged(uuid);
      final staleGeneration = p.debugBindingGenerationForTesting;

      await p.disconnect();
      expect(p.isConnected, isFalse);
      expect(await _store.load(uuid), isNull);

      p.debugHandleSessionUpdatedForTesting(
        uuid,
        staleGeneration,
        _session(accessToken: 'late-at', refreshToken: 'late-rt', username: 'alice'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(p.isConnected, isFalse);
      expect(await _store.load(uuid), isNull);

      p.dispose();
    });

    test('cancelConnect is a no-op when not connecting', () {
      final p = TraktAccountProvider(kidsProfileCheck: () async => false);
      // Should not throw when no completer exists.
      expect(() => p.cancelConnect(), returnsNormally);
      expect(p.isConnecting, isFalse);
      p.dispose();
    });

    test('safeNotifyListeners after dispose is a no-op', () async {
      final p = TraktAccountProvider(kidsProfileCheck: () async => false);
      p.dispose();
      // After dispose, calling onActiveProfileChanged still runs the rebind
      // path; safeNotifyListeners must swallow the post-dispose notification
      // without throwing.
      await p.onActiveProfileChanged('any-uuid');
    });
  });

  group('TraktAccountProvider kids gate', () {
    Future<void> seed(String uuid) async {
      await _store.save(uuid, _session(username: 'alice'));
      BaseSharedPreferencesService.resetForTesting();
    }

    test('an adult profile binds its stored session to the services', () async {
      await seed('adult');
      final p = TraktAccountProvider(kidsProfileCheck: () async => false);
      await p.onActiveProfileChanged('adult');
      expect(p.isConnected, isTrue);
      expect(p.isKidsProfile, isFalse);
      expect(TraktScrobbleService.instance.hasClient, isTrue);
      expect(TraktSyncService.instance.hasClient, isTrue);
      p.dispose();
    });

    test('a kids profile gets no session and no service client, and the stored session stays', () async {
      await seed('kid');
      final p = TraktAccountProvider(kidsProfileCheck: () async => true);
      await p.onActiveProfileChanged('kid');
      expect(p.isConnected, isFalse);
      expect(p.isKidsProfile, isTrue);
      expect(TraktScrobbleService.instance.hasClient, isFalse);
      expect(TraktSyncService.instance.hasClient, isFalse);
      expect(await _store.load('kid'), isNotNull);
      p.dispose();
    });

    test('a failing check fails closed', () async {
      await seed('kid');
      final p = TraktAccountProvider(kidsProfileCheck: () async => throw StateError('prefs unavailable'));
      await p.onActiveProfileChanged('kid');
      expect(p.isConnected, isFalse);
      expect(p.isKidsProfile, isTrue);
      expect(TraktScrobbleService.instance.hasClient, isFalse);
      p.dispose();
    });

    test('the adult client is unbound before the kids check answers', () async {
      await seed('adult');
      final gate = Completer<bool>();
      final p = TraktAccountProvider(kidsProfileCheck: () async => false);
      await p.onActiveProfileChanged('adult');
      expect(TraktScrobbleService.instance.hasClient, isTrue);

      p.debugSetKidsProfileCheckForTesting(() => gate.future);
      final switching = p.onActiveProfileChanged('adult');
      expect(TraktScrobbleService.instance.hasClient, isFalse);
      expect(TraktSyncService.instance.hasClient, isFalse);
      gate.complete(false);
      await switching;
      p.dispose();
    });

    test('switching the kids switch on stops scrobble and sync without removing the session', () async {
      await seed('adult');
      var kids = false;
      final p = TraktAccountProvider(kidsProfileCheck: () async => kids);
      await p.onActiveProfileChanged('adult');
      expect(TraktScrobbleService.instance.hasClient, isTrue);

      kids = true;
      await p.reevaluateKidsGate();
      expect(p.isKidsProfile, isTrue);
      expect(TraktScrobbleService.instance.hasClient, isFalse);
      expect(await _store.load('adult'), isNotNull);

      kids = false;
      await p.reevaluateKidsGate();
      expect(p.isConnected, isTrue);
      expect(TraktScrobbleService.instance.hasClient, isTrue);
      p.dispose();
    });

    test('connect refuses on a kids profile', () async {
      final p = TraktAccountProvider(kidsProfileCheck: () async => true);
      await p.onActiveProfileChanged('kid');
      var codeShown = false;
      expect(await p.connect(onCodeReady: (_) => codeShown = true), isFalse);
      expect(codeShown, isFalse);
      expect(p.isConnecting, isFalse);
      p.dispose();
    });

    test('the refreshed pair is written before the services use it', () async {
      await seed('adult');
      final p = TraktAccountProvider(kidsProfileCheck: () async => false);
      await p.onActiveProfileChanged('adult');
      final generation = p.debugBindingGenerationForTesting;
      await p.debugHandleSessionUpdatedForTesting(
        'adult',
        generation,
        _session(accessToken: 'at2', refreshToken: 'rt2', username: 'alice'),
      );
      expect((await _store.load('adult'))?.refreshToken, 'rt2');
      p.dispose();
    });

    test('a refreshed pair on its way when the kids switch goes on is still written', () async {
      await seed('adult');
      var kids = false;
      final p = TraktAccountProvider(kidsProfileCheck: () async => kids);
      await p.onActiveProfileChanged('adult');
      final generation = p.debugBindingGenerationForTesting;

      kids = true;
      await p.reevaluateKidsGate();
      expect(p.debugBindingGenerationForTesting, generation);

      await p.debugHandleSessionUpdatedForTesting(
        'adult',
        generation,
        _session(accessToken: 'at3', refreshToken: 'rt3', username: 'alice'),
      );
      expect((await _store.load('adult'))?.refreshToken, 'rt3');
      expect(p.isConnected, isFalse);
      expect(TraktScrobbleService.instance.hasClient, isFalse);
      p.dispose();
    });

    test('disposing an old provider unbinds only what is still its own', () async {
      await seed('adult');
      final first = TraktAccountProvider(kidsProfileCheck: () async => false);
      await first.onActiveProfileChanged('adult');
      final second = TraktAccountProvider(kidsProfileCheck: () async => false);
      await second.onActiveProfileChanged('adult');

      first.dispose();
      expect(TraktScrobbleService.instance.hasClient, isTrue);

      second.dispose();
      expect(TraktScrobbleService.instance.hasClient, isFalse);
      expect(TraktSyncService.instance.hasClient, isFalse);
    });

    test('a kids profile that never reads its provider still ends the adult binding when it is created', () async {
      await seed('adult');
      final adult = TraktAccountProvider(kidsProfileCheck: () async => false);
      await adult.onActiveProfileChanged('adult');
      expect(TraktScrobbleService.instance.hasClient, isTrue);

      // The profile session creates the kids provider (lazy: false) and then
      // disposes the adult one.
      final kid = TraktAccountProvider(kidsProfileCheck: () async => true);
      final hydrating = kid.onActiveProfileChanged('kid');
      adult.dispose();
      await hydrating;

      expect(TraktScrobbleService.instance.hasClient, isFalse);
      expect(TraktSyncService.instance.hasClient, isFalse);
      kid.dispose();
    });

    test('a disconnect or invalidation during a rebind cancels the bind', () async {
      await seed('adult');
      final gate = Completer<bool>();
      final p = TraktAccountProvider(kidsProfileCheck: () => gate.future);
      final rebinding = p.onActiveProfileChanged('adult');

      p.debugBumpGenerationForTesting();
      gate.complete(false);
      await rebinding;

      expect(p.isConnected, isFalse);
      expect(TraktScrobbleService.instance.hasClient, isFalse);
      p.dispose();
    });

    test('the kids shield wins over a bind that happened while the check ran', () async {
      await seed('adult');
      final gate = Completer<bool>();
      final p = TraktAccountProvider(kidsProfileCheck: () async => false);
      await p.onActiveProfileChanged('adult');
      expect(TraktScrobbleService.instance.hasClient, isTrue);

      p.debugSetKidsProfileCheckForTesting(() => gate.future);
      final gating = p.reevaluateKidsGate();
      p.debugBumpGenerationForTesting();
      gate.complete(true);
      await gating;

      expect(p.isKidsProfile, isTrue);
      expect(p.isConnected, isFalse);
      expect(TraktScrobbleService.instance.hasClient, isFalse);
      p.dispose();
    });
  });
}
