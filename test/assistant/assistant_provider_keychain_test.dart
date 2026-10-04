import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/pleya_keychain.dart';
import 'package:pleya/utils/app_logger.dart';
import 'package:pleya/utils/platform_detector.dart';

import '../test_helpers/prefs.dart';

const _channel = MethodChannel('com.pleya/keychain');
const _key = AssistantProviderStore.key;

const _cloud = AssistantProviderConfig(
  kind: AssistantProviderKind.ollamaCloud,
  baseUrl: 'https://ollama.com',
  apiKey: 'sk-cloud',
  model: 'gpt-oss:120b',
);
const _server = AssistantProviderConfig(
  kind: AssistantProviderKind.ollamaServer,
  baseUrl: 'http://nas.lan:11434',
  model: 'qwen3:8b',
);

/// The native side in memory: items, a call log and switchable failures.
class _Keychain {
  final items = <String, String>{};
  final calls = <String>[];
  PlatformException? readError;
  PlatformException? writeError;
  PlatformException? deleteError;
  bool writeResult = true;

  /// Holds the write of [gatedValue] until completed, to make two
  /// operations overlap.
  Completer<void>? writeGate;
  String? gatedValue;
  final gateReached = Completer<void>();

  /// Replaces what a write stores, to fake an item that comes back different.
  String Function(String value)? writeTamper;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      final args = (call.arguments as Map).cast<String, Object?>();
      final key = args['key'] as String;
      calls.add(call.method);
      switch (call.method) {
        case 'read':
          if (readError != null) throw readError!;
          return items[key];
        case 'write':
          if (args['value'] == gatedValue) {
            gateReached.complete();
            await writeGate?.future;
          }
          if (writeError != null) throw writeError!;
          if (!writeResult) return false;
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

PlatformException _osStatus(int status) => PlatformException(code: 'keychain', message: 'OSStatus $status');

Future<String?> _prefsBlob() async => (await BaseSharedPreferencesService.sharedCache()).getString(_key);

Future<String?> _pending() async =>
    (await BaseSharedPreferencesService.sharedCache()).getString(AssistantProviderStore.pendingKey);

String _sha(String raw) => sha256.convert(utf8.encode(raw)).toString();

const _openRouter = AssistantProviderConfig(
  kind: AssistantProviderKind.openRouter,
  baseUrl: AssistantProviderConfig.openRouterUrl,
  apiKey: 'sk-or',
  model: 'x/y',
);

/// A blob written by the old prefs-only store, as tvOS has it today.
Future<void> _legacy(AssistantProviderConfig config) => AssistantProviderStore().save(config);

String _json(AssistantProviderConfig config) => jsonEncode(config.toJson());

void main() {
  late _Keychain keychain;
  late AssistantProviderStore store;

  setUp(() {
    resetSharedPreferencesForTest();
    keychain = _Keychain()..install();
    store = AssistantProviderStore(keychain: const PleyaKeychain());
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  group('save', () {
    test('a fresh save goes to the keychain, not to the prefs', () async {
      await store.save(_cloud);

      expect(keychain.items[_key], _json(_cloud));
      expect(await _prefsBlob(), isNull);
      expect((await store.load())?.apiKey, 'sk-cloud');
    });

    test('negative control: a failed keychain write keeps the prefs path working', () async {
      keychain.writeError = _osStatus(-34018);

      await store.save(_cloud);

      expect(keychain.items, isEmpty);
      expect(await _prefsBlob(), isNotNull);
      expect(await _pending(), 'none');
      expect((await store.load())?.model, 'gpt-oss:120b');
    });

    test('a refused save beats the synced item it was saved over and goes up later', () async {
      keychain.items[_key] = _json(_server);
      keychain.writeError = _osStatus(-25308);

      await store.save(_cloud);
      expect(await _pending(), _sha(_json(_server)));

      expect((await store.load())?.kind, AssistantProviderKind.ollamaCloud);
      expect(await _prefsBlob(), isNotNull);
      expect(keychain.items[_key], _json(_server));

      keychain.writeError = null;
      expect((await store.load())?.kind, AssistantProviderKind.ollamaCloud);
      expect(keychain.items[_key], _json(_cloud));
      expect(await _prefsBlob(), isNull);
      expect(await _pending(), isNull);
      expect((await store.load())?.kind, AssistantProviderKind.ollamaCloud);
    });

    test('negative control: a newer save from another device beats the refused one', () async {
      keychain.items[_key] = _json(_server);
      keychain.writeError = _osStatus(-25308);
      await store.save(_cloud);
      keychain.writeError = null;
      keychain.items[_key] = _json(_openRouter); // another device saved since

      expect((await store.load())?.kind, AssistantProviderKind.openRouter);
      expect(keychain.items[_key], _json(_openRouter));
      expect(await _prefsBlob(), isNull);
      expect(await _pending(), isNull);
    });

    test('another device clearing since the refused save wins too', () async {
      keychain.items[_key] = _json(_server);
      keychain.writeError = _osStatus(-25308);
      await store.save(_cloud);
      keychain.writeError = null;
      keychain.items.clear();

      expect(await store.load(), isNull);
      expect(await _prefsBlob(), isNull);
      expect(keychain.items, isEmpty);
    });

    test('with an unknown marker a decodable keychain item wins and the pending blob goes', () async {
      keychain.readError = _osStatus(-25308);
      keychain.writeError = _osStatus(-25308);
      await store.save(_cloud);
      expect(await _pending(), 'unknown');
      keychain
        ..readError = null
        ..writeError = null
        ..items[_key] = _json(_openRouter);

      expect((await store.load())?.kind, AssistantProviderKind.openRouter);
      expect(keychain.items[_key], _json(_openRouter));
      expect(keychain.calls, isNot(contains('write')));
      expect(await _pending(), isNull);
      expect(await _prefsBlob(), isNull);
    });

    test('with an unknown marker the pending blob goes up into an empty keychain', () async {
      keychain.readError = _osStatus(-25308);
      keychain.writeError = _osStatus(-25308);
      await store.save(_cloud);
      keychain
        ..readError = null
        ..writeError = null;

      expect((await store.load())?.kind, AssistantProviderKind.ollamaCloud);
      expect(keychain.items[_key], _json(_cloud));
      expect(await _pending(), isNull);
      expect(await _prefsBlob(), isNull);
    });

    test('a save whose read fails is marked with the last item seen and goes up over that item', () async {
      keychain.items[_key] = _json(_server);
      expect((await store.load())?.kind, AssistantProviderKind.ollamaServer);
      keychain
        ..readError = _osStatus(-25308)
        ..writeError = _osStatus(-25308);
      await store.save(_cloud);
      expect(await _pending(), _sha(_json(_server)));
      keychain
        ..readError = null
        ..writeError = null;

      expect((await store.load())?.kind, AssistantProviderKind.ollamaCloud);
      expect(keychain.items[_key], _json(_cloud));
      expect(await _pending(), isNull);
      expect(await _prefsBlob(), isNull);
    });

    test('negative control: a failed-read save loses to an item changed since, and says so in the log', () async {
      keychain.items[_key] = _json(_server);
      await store.load();
      keychain
        ..readError = _osStatus(-25308)
        ..writeError = _osStatus(-25308);
      await store.save(_cloud);
      keychain
        ..readError = null
        ..writeError = null
        ..items[_key] = _json(_openRouter);
      MemoryLogOutput.clearLogs();

      expect((await store.load())?.kind, AssistantProviderKind.openRouter);
      expect(keychain.items[_key], _json(_openRouter));
      expect(await _pending(), isNull);
      expect(await _prefsBlob(), isNull);
      expect(MemoryLogOutput.getLogs().map((e) => e.message), contains(contains('pending config dropped')));
    });

    test('a device that never read the keychain still marks unknown, and a decodable item wins', () async {
      keychain
        ..items[_key] = _json(_server)
        ..readError = _osStatus(-25308)
        ..writeError = _osStatus(-25308);
      await store.save(_cloud);
      expect(await _pending(), 'unknown');
      keychain
        ..readError = null
        ..writeError = null;

      expect((await store.load())?.kind, AssistantProviderKind.ollamaServer);
      expect(keychain.items[_key], _json(_server));
      expect(await _pending(), isNull);
    });

    test('a successful save clears an earlier pending marker', () async {
      keychain.writeError = _osStatus(-25308);
      await store.save(_server);
      keychain.writeError = null;

      await store.save(_cloud);

      expect(await _pending(), isNull);
      expect(await _prefsBlob(), isNull);
      expect(keychain.items[_key], _json(_cloud));
    });
  });

  group('legacy migration', () {
    test('moves the blob to the keychain and drops the prefs key only after the readback', () async {
      await _legacy(_cloud);
      expect(await _prefsBlob(), isNotNull);

      final loaded = await store.load();

      expect(loaded?.apiKey, 'sk-cloud');
      expect(keychain.items[_key], _json(_cloud));
      expect(keychain.calls, ['read', 'write', 'read']);
      expect(await _prefsBlob(), isNull);
      // The next load reads the keychain alone.
      expect((await store.load())?.model, 'gpt-oss:120b');
    });

    test('negative control: a readback that differs keeps the blob and deletes nothing', () async {
      await _legacy(_cloud);
      // Another device's sync lands between the write and the readback.
      keychain.writeTamper = (_) => _json(_openRouter);

      expect((await store.load())?.apiKey, 'sk-cloud');
      expect(await _prefsBlob(), isNotNull);
      expect(keychain.items[_key], _json(_openRouter));
      expect(keychain.calls, ['read', 'write', 'read']);

      // The next load resolves normally: the synced config wins.
      expect((await store.load())?.kind, AssistantProviderKind.openRouter);
      expect(await _prefsBlob(), isNull);
    });

    test('negative control: a write the keychain declines keeps the prefs blob', () async {
      await _legacy(_cloud);
      keychain.writeResult = false;

      expect((await store.load())?.apiKey, 'sk-cloud');
      expect(await _prefsBlob(), isNotNull);
    });
  });

  group('keychain errors', () {
    test('a read error falls back to the legacy blob and deletes nothing', () async {
      await _legacy(_cloud);
      keychain.readError = _osStatus(-25308);

      expect((await store.load())?.apiKey, 'sk-cloud');
      expect(await _prefsBlob(), isNotNull);
      expect(keychain.calls, ['read']);
    });

    test('a write error during migration keeps the legacy blob', () async {
      await _legacy(_cloud);
      keychain.writeError = _osStatus(-34018);

      expect((await store.load())?.apiKey, 'sk-cloud');
      expect(await _prefsBlob(), isNotNull);
    });

    test('a read error without a legacy blob throws instead of reading as not configured', () async {
      keychain.readError = _osStatus(-25308);

      await expectLater(store.load(), throwsA(isA<AssistantProviderStoreException>()));
    });

    test('negative control: a missing item without a legacy blob is not configured', () async {
      expect(await store.load(), isNull);
    });
  });

  group('conflict', () {
    test('a synced item wins and the local legacy blob goes', () async {
      await _legacy(_server);
      keychain.items[_key] = _json(_cloud);

      expect((await store.load())?.kind, AssistantProviderKind.ollamaCloud);
      expect(await _prefsBlob(), isNull);
      expect(keychain.items[_key], _json(_cloud));
      expect(keychain.calls, isNot(contains('write')));
    });

    test('an unreadable synced item without a legacy blob throws instead of reading as unset', () async {
      keychain.items[_key] = '{"kind":"fromTheFuture"}';

      await expectLater(store.load(), throwsA(isA<AssistantProviderStoreException>()));
      expect(keychain.items[_key], '{"kind":"fromTheFuture"}');
    });

    test('negative control: an unreadable synced item neither wins nor gets overwritten', () async {
      await _legacy(_server);
      keychain.items[_key] = '{"kind":"fromTheFuture"}';

      expect((await store.load())?.kind, AssistantProviderKind.ollamaServer);
      expect(await _prefsBlob(), isNotNull);
      expect(keychain.items[_key], '{"kind":"fromTheFuture"}');
    });
  });

  group('unreadable synced item', () {
    const future = '{"kind":"fromTheFuture"}';

    test('a save refuses to overwrite it', () async {
      keychain.items[_key] = future;

      await expectLater(store.save(_cloud), throwsA(isA<AssistantProviderUnreadableException>()));
      expect(keychain.items[_key], future);
      expect(keychain.calls, ['read']);
      expect(await _prefsBlob(), isNull);
    });

    test('an explicit replace overwrites it', () async {
      keychain.items[_key] = future;

      await store.save(_cloud, replaceUnreadable: true);

      expect(keychain.items[_key], _json(_cloud));
    });

    test('a save whose read fails does not write blind but takes the fallback', () async {
      keychain.items[_key] = future;
      keychain.readError = _osStatus(-25308);

      await store.save(_cloud);

      expect(keychain.calls, ['read']);
      expect(keychain.items[_key], future);
      expect(await _prefsBlob(), isNotNull);
      expect(await _pending(), 'unknown');
    });

    test('negative control: with replaceUnreadable a failed read still writes', () async {
      keychain.readError = _osStatus(-25308);

      await store.save(_cloud, replaceUnreadable: true);

      expect(keychain.items[_key], _json(_cloud));
      expect(await _prefsBlob(), isNull);
    });

    test('an unknown marker never overwrites an unreadable item on load', () async {
      keychain.items[_key] = future;
      keychain.readError = _osStatus(-25308);
      await store.save(_cloud);
      keychain.readError = null;

      expect((await store.load())?.kind, AssistantProviderKind.ollamaCloud);
      expect(keychain.items[_key], future);
      expect(keychain.calls, isNot(contains('write')));
      expect(await _pending(), 'unknown');
      expect(await _prefsBlob(), isNotNull);
      // A save without Vervangen is refused, not written over it.
      await expectLater(store.save(_server), throwsA(isA<AssistantProviderUnreadableException>()));
      expect(keychain.items[_key], future);
    });
  });

  group('serial', () {
    test('a save that overlaps a pending migration ends with the save', () async {
      const openRouter = _openRouter;
      keychain.items[_key] = _json(_server);
      keychain.writeError = _osStatus(-25308);
      await store.save(_cloud); // pending blob
      keychain.writeError = null;
      final gate = keychain.writeGate = Completer<void>();
      keychain.gatedValue = _json(_cloud);

      final load = store.load(); // migrates the pending blob, held at its write
      await keychain.gateReached.future;
      final save = store.save(openRouter);
      await pumpEventQueue();
      gate.complete();
      await Future.wait([load, save]);

      expect(keychain.items[_key], _json(openRouter));
      expect(await _prefsBlob(), isNull);
      expect((await store.load())?.kind, AssistantProviderKind.openRouter);
    });
  });

  group('clear', () {
    test('wipes the keychain item, the prefs blob and the marker and signals the change', () async {
      await _legacy(_server);
      await (await BaseSharedPreferencesService.sharedCache()).setString(AssistantProviderStore.pendingKey, 'none');
      keychain.items[_key] = _json(_cloud);
      final before = AssistantProviderStore.changes.value;

      await store.clear();

      expect(keychain.items, isEmpty);
      expect(await _prefsBlob(), isNull);
      expect(await _pending(), isNull);
      expect(AssistantProviderStore.changes.value, before + 1);
      expect(await store.load(), isNull);
    });

    test('a failed keychain delete keeps a pending blob', () async {
      keychain.items[_key] = _json(_server);
      keychain.writeError = _osStatus(-25308);
      await store.save(_cloud);
      keychain.deleteError = _osStatus(-25308);

      await expectLater(store.clear(), throwsA(isA<PlatformException>()));
      expect(await _prefsBlob(), isNotNull);
      expect(await _pending(), isNotNull);
      expect((await store.load())?.kind, AssistantProviderKind.ollamaCloud);
    });

    test('negative control: a failed keychain delete is reported, not hidden', () async {
      keychain.items[_key] = _json(_cloud);
      keychain.deleteError = _osStatus(-25308);

      await expectLater(store.clear(), throwsA(isA<PlatformException>()));
      expect(keychain.items[_key], isNotNull);
    });
  });

  group('platforms', () {
    test('an unsupported platform uses only the prefs', () async {
      final prefsOnly = AssistantProviderStore();

      await prefsOnly.save(_cloud);

      expect((await prefsOnly.load())?.apiKey, 'sk-cloud');
      expect(await _prefsBlob(), isNotNull);
      expect(keychain.calls, isEmpty);
    });

    test('negative control: on Apple TV the default store uses the keychain', () async {
      TvDetectionService.debugSetAppleTVOverride(true);

      await AssistantProviderStore().save(_cloud);

      expect(keychain.calls, ['read', 'write']);
      expect(await _prefsBlob(), isNull);
    });
  });
}
