import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/icloud_sync_service.dart';
import 'package:pleya/services/settings_service.dart';

import '../test_helpers/prefs.dart';

/// Availability and health used to be one boolean, and every way of failing
/// collapsed into "sign in to iCloud" — which on an Apple TV was never true to
/// begin with. These tests hold the two apart: a platform that cannot sync is
/// [ICloudSyncStatus.unsupported] or [ICloudSyncStatus.signedOut], a platform
/// that can sync but just failed is [ICloudSyncStatus.error], and only the
/// first pair may take the control away.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.pleya/icloud_kvs');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// What the fake native side does for `isAvailable`: return a bool, or throw.
  late Object? availableAnswer;
  late Object? setThrows;

  void install() {
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'isAvailable':
          if (availableAnswer is Exception) throw availableAnswer!;
          return availableAnswer as bool?;
        case 'getAll':
          return <String, String>{};
        case 'set':
          if (setThrows != null) throw setThrows!;
          return null;
        case 'remove':
        case 'synchronize':
          return null;
      }
      return null;
    });
  }

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    availableAnswer = true;
    setThrows = null;
    install();
  });

  tearDown(() {
    ICloudSyncService.debugReset();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<ICloudSyncService> service() async =>
      ICloudSyncService.debugCreate(settings: await SettingsService.getInstance());

  group('isAvailable', () {
    test('a native yes is usable and healthy — this is the tvOS answer', () async {
      final svc = await service();
      expect(await svc.isAvailable(), isTrue);
      expect(svc.status.value, ICloudSyncStatus.ok);
      expect(svc.status.value.isUsable, isTrue);
    });

    test('a native no is a signed-out account, and only iOS/macOS can answer it', () async {
      availableAnswer = false;
      final svc = await service();
      expect(await svc.isAvailable(), isFalse);
      expect(svc.status.value, ICloudSyncStatus.signedOut);
      expect(svc.status.value.isUsable, isFalse);
    });

    test('a channel failure is a transport fault, not a missing account', () async {
      availableAnswer = PlatformException(code: 'ERR', message: 'channel down');
      final svc = await service();
      // True on purpose: the platform is still supported, so the control stays
      // on and the fault travels in the status instead of masquerading as
      // "not logged into iCloud".
      expect(await svc.isAvailable(), isTrue);
      expect(svc.status.value, ICloudSyncStatus.error);
      expect(svc.status.value, isNot(ICloudSyncStatus.signedOut));
      expect(svc.status.value.isUsable, isTrue);
    });

    test('a missing plugin is genuinely unavailable — there is no store to talk to', () async {
      availableAnswer = MissingPluginException('No implementation found');
      final svc = await service();
      expect(await svc.isAvailable(), isFalse);
      expect(svc.status.value, ICloudSyncStatus.unsupported);
    });

    test('a non-Apple platform never reaches the channel', () async {
      final svc = await service();
      // The test host is itself a supported platform, so the platform answer
      // has to be overridden to exercise Android/Linux/Windows at all.
      ICloudSyncService.debugSupportedOverride = false;
      addTearDown(() => ICloudSyncService.debugSupportedOverride = true);
      expect(await svc.isAvailable(), isFalse);
      expect(svc.status.value, ICloudSyncStatus.unsupported);
    });
  });

  group('health while running', () {
    test('a failing write is an error, and the next good call clears it', () async {
      final settings = await SettingsService.getInstance();
      final svc = ICloudSyncService.debugCreate(settings: settings);
      await svc.enable();

      setThrows = PlatformException(code: 'ERR', message: 'store unreachable');
      await settings.write(SettingsService.subtitleFontSize, 40);
      await Future<void>.delayed(Duration.zero);
      expect(svc.status.value, ICloudSyncStatus.error);

      setThrows = null;
      await settings.write(SettingsService.subtitleFontSize, 44);
      await Future<void>.delayed(Duration.zero);
      expect(svc.status.value, ICloudSyncStatus.ok);
    });

    test('a quota violation is a warning — sync keeps running', () async {
      final settings = await SettingsService.getInstance();
      final svc = ICloudSyncService.debugCreate(settings: settings);
      await svc.enable();

      await svc.debugHandleEvent({'reason': 2, 'changedKeys': <String>[]});
      expect(svc.status.value, ICloudSyncStatus.warning);
      expect(svc.status.value.isUsable, isTrue);
    });

    test('an oversized value is skipped as a warning, not an error', () async {
      final settings = await SettingsService.getInstance();
      final svc = ICloudSyncService.debugCreate(settings: settings);
      await svc.enable();

      // Straight to prefs plus a manual hook call: `write` needs a typed Pref,
      // and the oversized case is about an unbounded progress map, not a
      // declared setting.
      await settings.prefs.setString('local_progress_x', 'y' * (ICloudSyncService.maxValueBytes + 1));
      BaseSharedPreferencesService.onKeyWritten?.call('local_progress_x');
      await Future<void>.delayed(Duration.zero);
      expect(svc.status.value, ICloudSyncStatus.warning);
    });

    test('a standing error outranks a warning until something succeeds', () async {
      final settings = await SettingsService.getInstance();
      final svc = ICloudSyncService.debugCreate(settings: settings);
      await svc.enable();

      setThrows = PlatformException(code: 'ERR', message: 'store unreachable');
      await settings.write(SettingsService.subtitleFontSize, 40);
      await Future<void>.delayed(Duration.zero);
      expect(svc.status.value, ICloudSyncStatus.error);

      await svc.debugHandleEvent({'reason': 2, 'changedKeys': <String>[]});
      expect(svc.status.value, ICloudSyncStatus.error, reason: 'a dropped key is the smaller of the two problems');
    });
  });

  test('the status is a listenable the settings tile can subscribe to', () async {
    final svc = await service();
    final seen = <ICloudSyncStatus>[];
    svc.status.addListener(() => seen.add(svc.status.value));

    availableAnswer = false;
    await svc.isAvailable();
    availableAnswer = true;
    await svc.isAvailable();

    expect(seen, [ICloudSyncStatus.signedOut, ICloudSyncStatus.ok]);
  });
}
