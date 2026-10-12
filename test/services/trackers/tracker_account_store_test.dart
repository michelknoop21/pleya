import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/credential_vault.dart';
import 'package:pleya/services/pleya_keychain.dart';
import 'package:pleya/services/preferences/preference_sync_policy.dart';
import 'package:pleya/services/trackers/tracker_account_store.dart';
import 'package:pleya/services/trackers/tracker_constants.dart';
import 'package:pleya/services/trackers/tracker_session.dart';

import '../../test_helpers/prefs.dart';

const _channel = MethodChannel('com.pleya/keychain');
const _key = 'user_alice_mal_session';
const _marker = '${_key}_kc';

/// The native side in memory, with the scope every call carried.
class _Keychain {
  final items = <String, String>{};
  final scopes = <String?>[];
  final calls = <String>[];
  PlatformException? readError;
  PlatformException? writeError;
  PlatformException? deleteError;
  String Function(String value)? writeTamper;

  /// Runs when a write arrives, before it takes effect.
  Future<void> Function()? onWrite;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      final args = (call.arguments as Map).cast<String, Object?>();
      final key = args['key'] as String;
      calls.add(call.method);
      scopes.add(args['scope'] as String?);
      switch (call.method) {
        case 'read':
          if (readError != null) throw readError!;
          return items[key];
        case 'write':
          await onWrite?.call();
          if (writeError != null) throw writeError!;
          final value = args['value'] as String;
          items[key] = writeTamper == null ? value : writeTamper!(value);
          return true;
        case 'delete':
          if (deleteError != null) throw deleteError!;
          items.remove(key);
          return null;
      }
      throw MissingPluginException(call.method);
    });
  }
}

TrackerSession _session(String access, {int expiresAt = 2000000000}) =>
    TrackerSession(accessToken: access, refreshToken: 'refresh-$access', expiresAt: expiresAt, createdAt: 1700000000);

Future<String?> _blob() async => (await BaseSharedPreferencesService.sharedCache()).getString(_key);
Future<bool?> _markerSet() async => (await BaseSharedPreferencesService.sharedCache()).getBool(_marker);

void main() {
  final store = trackerAccountStore(TrackerService.mal);
  late _Keychain keychain;

  setUp(() {
    resetSharedPreferencesForTest();
    keychain = _Keychain()..install();
  });

  tearDown(() {
    PleyaKeychain.debugForceSupported = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
  });

  group('with the keychain (iOS, tvOS)', () {
    setUp(() => PleyaKeychain.debugForceSupported = true);

    test('a saved session lives in the device keychain and leaves no token in the prefs', () async {
      await store.save('alice', _session('tok-1'));

      expect(keychain.items[_key], contains('tok-1'));
      expect(await _blob(), isNull);
      expect(await _markerSet(), isTrue);
      expect(keychain.scopes.toSet(), {'device'}, reason: 'never the synced iCloud keychain');
      expect((await store.load('alice'))?.accessToken, 'tok-1');
    });

    test('a plaintext session from before the move migrates on load and leaves the prefs', () async {
      final legacy = _session('legacy').encode();
      resetSharedPreferencesForTest(initialAsync: {_key: legacy});

      final loaded = await store.load('alice');

      expect(loaded?.accessToken, 'legacy');
      expect(loaded?.refreshToken, 'refresh-legacy');
      expect(keychain.items[_key], legacy);
      expect(await _blob(), isNull);
      expect(await _markerSet(), isTrue);
      expect((await store.load('alice'))?.accessToken, 'legacy');
    });

    test('a refused write keeps the legacy session readable and in the prefs', () async {
      resetSharedPreferencesForTest(initialAsync: {_key: _session('legacy').encode()});
      keychain.writeError = PlatformException(code: 'KEYCHAIN', message: 'OSStatus -25308');

      expect((await store.load('alice'))?.accessToken, 'legacy');
      expect(await _blob(), isNotNull);
      expect(await _markerSet(), isNull);

      keychain.writeError = null;
      expect((await store.load('alice'))?.accessToken, 'legacy');
      expect(await _blob(), isNull);
    });

    test('a readback that differs does not drop the prefs copy', () async {
      resetSharedPreferencesForTest(initialAsync: {_key: _session('legacy').encode()});
      keychain.writeTamper = (v) => v.replaceAll('legacy', 'other');

      expect((await store.load('alice'))?.accessToken, 'legacy');
      expect(await _blob(), isNotNull);
      expect(await _markerSet(), isNull);
    });

    test('a save the keychain refuses is kept protected in the prefs and beats the older item', () async {
      await store.save('alice', _session('old'));
      keychain.writeError = PlatformException(code: 'KEYCHAIN', message: 'OSStatus -25308');

      await store.save('alice', _session('rotated'));

      final blob = await _blob();
      expect(CredentialVault.isProtected(blob), isTrue);
      expect(blob, isNot(contains('rotated')));
      expect(keychain.items[_key], contains('old'));
      expect((await store.load('alice'))?.accessToken, 'rotated');

      keychain.writeError = null;
      expect((await store.load('alice'))?.accessToken, 'rotated');
      expect(keychain.items[_key], contains('rotated'));
      expect(await _blob(), isNull);
    });

    test('a keychain item without marker is from an earlier install: not read', () async {
      keychain.items[_key] = _session('previous-install').encode();

      expect(await store.load('alice'), isNull);
      expect(keychain.calls, isEmpty);
    });

    test('prefs that read empty do not delete a valid item', () async {
      await store.save('alice', _session('tok-1'));
      // A launch before the first unlock: the prefs come back empty.
      resetSharedPreferencesForTest();

      expect(await store.load('alice'), isNull);
      expect(keychain.items[_key], contains('tok-1'));
      expect(keychain.calls, isNot(contains('delete')));
    });

    test('the marker is in the prefs before the keychain write lands', () async {
      bool? markerAtWrite;
      keychain.onWrite = () async => markerAtWrite = await _markerSet();

      await store.save('alice', _session('tok-1'));

      expect(markerAtWrite, isTrue, reason: 'an app that dies after the write must find its item again');
    });

    test('a refused first write leaves no marker, so an earlier install stays unread', () async {
      keychain.items[_key] = _session('previous-install').encode();
      keychain.writeError = PlatformException(code: 'KEYCHAIN', message: 'OSStatus -25308');

      await store.save('alice', _session('tok-1'));
      expect(await _markerSet(), isNull);
      (await BaseSharedPreferencesService.sharedCache()).remove(_key);

      expect(await store.load('alice'), isNull);
    });

    test('a protected blob the vault cannot open reads as not connected', () async {
      await store.save('alice', _session('tok-1'));
      resetSharedPreferencesForTest(initialAsync: {_key: 'enc:v1:{"n":"AAAA","c":"AAAA","m":"AAAA"}', _marker: true});

      expect(await store.load('alice'), isNull);
      expect(keychain.items[_key], contains('tok-1'), reason: 'nothing is deleted');
    });

    test('the slot without profile works like any other', () async {
      await store.save('', _session('global'));

      expect(keychain.items['mal_session'], contains('global'));
      expect((await store.load(''))?.accessToken, 'global');
      expect(await store.load('alice'), isNull);
    });

    test('a failed keychain read is not a disconnect: the item and marker stay', () async {
      await store.save('alice', _session('tok-1'));
      keychain.readError = PlatformException(code: 'KEYCHAIN', message: 'OSStatus -25308');

      expect(await store.load('alice'), isNull);
      expect(keychain.items[_key], contains('tok-1'));
      expect(await _markerSet(), isTrue);

      keychain.readError = null;
      expect((await store.load('alice'))?.accessToken, 'tok-1');
    });

    test('clear removes the item, the marker and any prefs copy', () async {
      await store.save('alice', _session('tok-1'));
      keychain.writeError = PlatformException(code: 'KEYCHAIN', message: 'OSStatus -25308');
      await store.save('alice', _session('tok-2'));
      keychain.writeError = null;

      await store.clear('alice');

      expect(keychain.items, isEmpty);
      expect(await _blob(), isNull);
      expect(await _markerSet(), isNull);
      expect(await store.load('alice'), isNull);
    });

    test('a clear whose keychain delete failed does not come back on the next load', () async {
      await store.save('alice', _session('tok-1'));
      keychain.deleteError = PlatformException(code: 'KEYCHAIN', message: 'OSStatus -25308');
      await store.clear('alice');
      expect(keychain.items[_key], isNotNull);
      expect(await _markerSet(), isFalse);

      // Still refused: the item stays unread.
      expect(await store.load('alice'), isNull);
      expect(keychain.calls.last, 'delete');

      keychain.deleteError = null;
      expect(await store.load('alice'), isNull);
      expect(keychain.items, isEmpty);
      expect(await _markerSet(), isNull);
    });

    test('overlapping save and load never put an older session back', () async {
      // A protected blob: opening it suspends the load, which is where a save
      // could slip in ahead of the migration.
      PleyaKeychain.debugForceSupported = false;
      await store.save('alice', _session('legacy'));
      PleyaKeychain.debugForceSupported = true;
      expect(CredentialVault.isProtected(await _blob()), isTrue);

      final load = store.load('alice');
      final save = store.save('alice', _session('newer'));
      await Future.wait([load, save]);

      expect((await store.load('alice'))?.accessToken, 'newer');
      expect(keychain.items[_key], contains('newer'));
    });

    test('profiles keep separate items', () async {
      await store.save('alice', _session('a'));
      await store.save('bob', _session('b'));

      expect((await store.load('alice'))?.accessToken, 'a');
      expect((await store.load('bob'))?.accessToken, 'b');
      await store.clear('alice');
      expect((await store.load('bob'))?.accessToken, 'b');
    });
  });

  group('without the keychain (Android, desktop)', () {
    test('a saved session is vault-protected in the prefs, never plaintext', () async {
      await store.save('alice', _session('tok-1'));

      final blob = await _blob();
      expect(CredentialVault.isProtected(blob), isTrue);
      expect(blob, isNot(contains('tok-1')));
      expect(keychain.calls, isEmpty);
      expect((await store.load('alice'))?.accessToken, 'tok-1');
    });

    test('a plaintext session from before the move is rewritten protected on load', () async {
      resetSharedPreferencesForTest(initialAsync: {_key: _session('legacy').encode()});

      expect((await store.load('alice'))?.accessToken, 'legacy');

      final blob = await _blob();
      expect(CredentialVault.isProtected(blob), isTrue);
      expect(blob, isNot(contains('legacy')));
      expect((await store.load('alice'))?.accessToken, 'legacy');
    });

    test('a corrupt blob reads as not connected and is left alone', () async {
      resetSharedPreferencesForTest(initialAsync: {_key: '{"access_token":'});

      expect(await store.load('alice'), isNull);
      expect(await _blob(), '{"access_token":');
    });
  });

  test('the marker is a secret-family key: never synced, never exported', () {
    for (final base in ['mal_session_kc', 'anilist_session_kc', 'simkl_session_kc', 'trakt_session_kc']) {
      expect(PreferenceSyncPolicyRegistry.maySync(base), isFalse, reason: base);
      expect(PreferenceSyncPolicyRegistry.isExportable(base), isFalse, reason: base);
    }
  });
}
