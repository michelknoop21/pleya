import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/models/transcode_quality_preset.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/opened_file.dart';
import 'package:pleya/services/opened_file_service.dart';
import 'package:pleya/services/playback_context.dart';
import 'package:pleya/services/playback_initialization_service.dart';
import 'package:pleya/services/playback_source_resolver.dart';
import 'package:pleya/utils/opened_file_launcher.dart';
import 'package:pleya/utils/video_player_navigation.dart';

const _path = '/private/var/mobile/Containers/Shared/AppGroup/X/File Provider Storage/Vakantie 2025.mkv';

void main() {
  group('opened file item', () {
    test('is a local clip named after the file, under the opened-file server id', () {
      final item = openedFileItem(_path);

      expect(item.id, _path);
      expect(item.backend, MediaBackend.local);
      expect(item.kind, MediaKind.clip);
      expect(item.title, 'Vakantie 2025');
      expect(isOpenedFile(item), isTrue);
    });

    test('an item from a local folder library is not an opened file', () {
      final item = MediaItem(id: _path, backend: MediaBackend.local, kind: MediaKind.movie, serverId: 'local-1');

      expect(isOpenedFile(item), isFalse);
    });
  });

  group('playback of an opened file', () {
    test('plays the file itself without a client or a download row', () async {
      final result = await PlaybackInitializationService().getPlaybackData(
        metadata: openedFileItem(_path),
        selectedMediaIndex: 0,
      );

      expect(result.videoUrl, _path);
      expect(result.usesLocalMedia, isTrue);
      expect(result.isTranscoding, isFalse);
      expect(result.availableVersions.single.container, 'mkv');
    });

    test('a local item without a client still fails: only opened files skip the lookup', () async {
      final item = MediaItem(id: _path, backend: MediaBackend.local, kind: MediaKind.movie, serverId: 'local-1');

      expect(
        () => PlaybackInitializationService().getPlaybackData(metadata: item, selectedMediaIndex: 0),
        throwsA(isA<PlaybackException>()),
      );
    });

    test('reports no progress: there is no server to send it to', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final manager = MultiServerManager();
      addTearDown(() async {
        manager.dispose();
        await db.close();
      });

      final context = await PlaybackSourceResolver(serverManager: manager, database: db).resolve(
        metadata: openedFileItem(_path),
        selectedMediaIndex: 0,
        offlineLibraryMode: false,
        qualityPreset: TranscodeQualityPreset.original,
      );

      expect(context.sourceKind, PlaybackSourceKind.localFile);
      expect(context.reportingMode, PlaybackReportingMode.disabled);
      expect(context.reportingClient, isNull);
      expect(context.streamHeaders, isNull);
    });
  });

  group('OpenedFileService', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('com.pleya/open_file.test');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<String> pending;
    late int takeCalls;

    setUp(() {
      pending = [];
      takeCalls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'takePendingFiles') return null;
        takeCalls++;
        final taken = List<String>.of(pending);
        pending.clear();
        return taken;
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Future<void> nativeSignal() => messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('onFilesAvailable')),
      (_) {},
    );

    test('a file that started the app waits for the first listener', () async {
      pending.add(_path);
      final service = OpenedFileService.forTesting(supported: true, channel: channel);
      final played = <String>[];

      await pumpEventQueue();
      expect(takeCalls, 0, reason: 'nothing may take the path before somebody can play it');

      service.listener = played.add;
      await pumpEventQueue();

      expect(played, [_path]);
      expect(pending, isEmpty);
    });

    test('a file opened while the app runs plays on the native signal', () async {
      final service = OpenedFileService.forTesting(supported: true, channel: channel);
      final played = <String>[];
      service.listener = played.add;
      await pumpEventQueue();
      expect(played, isEmpty);

      pending.add(_path);
      await nativeSignal();
      await pumpEventQueue();

      expect(played, [_path]);
    });

    test('of several files opened together the last one plays', () async {
      pending.addAll(['/a/one.mp4', '/a/two.mp4']);
      final service = OpenedFileService.forTesting(supported: true, channel: channel);
      final played = <String>[];

      service.listener = played.add;
      await pumpEventQueue();

      expect(played, ['/a/two.mp4']);
    });

    test('without a listener the signal leaves the path on the native side', () async {
      OpenedFileService.forTesting(supported: true, channel: channel);
      pending.add(_path);

      await nativeSignal();
      await pumpEventQueue();

      expect(pending, [_path]);
    });

    test('an unsupported platform never touches the channel', () async {
      pending.add(_path);
      final service = OpenedFileService.forTesting(supported: false, channel: channel);

      service.listener = (_) => fail('no file can arrive here');
      await pumpEventQueue();

      expect(takeCalls, 0);
    });
  });

  group('isVideoPlayerOnTop', () {
    Route<void> route(String? name) => PageRouteBuilder<void>(
      settings: RouteSettings(name: name),
      pageBuilder: (_, _, _) => const SizedBox(),
    );

    testWidgets('is true only while the player is the top route', (tester) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(navigatorKey: key, home: const SizedBox()));
      final navigator = key.currentState!;
      expect(isVideoPlayerOnTop(navigator), isFalse);

      unawaited(navigator.push(route(kVideoPlayerRouteName)));
      await tester.pumpAndSettle();
      expect(isVideoPlayerOnTop(navigator), isTrue);

      unawaited(navigator.push(route('/sheet')));
      await tester.pumpAndSettle();
      expect(isVideoPlayerOnTop(navigator), isFalse);
      expect(navigator.canPop(), isTrue, reason: 'looking at the top route must not pop it');
    });
  });

  group('document types', () {
    for (final platform in ['ios', 'macos']) {
      test('$platform declares Pleya as a viewer for video files', () {
        final plist = File('$platform/Runner/Info.plist').readAsStringSync();
        final start = plist.indexOf('<key>CFBundleDocumentTypes</key>');
        expect(start, isNot(-1), reason: 'without document types the system never offers Pleya for a file');
        final types = plist.substring(start, plist.indexOf('<key>UTImportedTypeDeclarations</key>'));

        expect(types, contains('<string>public.movie</string>'));
        expect(types, contains('<string>org.matroska.mkv</string>'));
        expect(types, contains('<string>Alternate</string>'));
        // mkv is not a system type everywhere: it needs its own declaration.
        expect(plist.substring(start), contains('<string>mkv</string>'));
      });
    }

    test('ios routes scene callbacks through the delegate that takes file URLs', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      final delegate = File('ios/Runner/OpenFilePlugin.swift').readAsStringSync();

      expect(plist, contains(r'<string>$(PRODUCT_MODULE_NAME).PleyaSceneDelegate</string>'));
      expect(delegate, contains('class PleyaSceneDelegate: FlutterSceneDelegate'));
    });

    test('ios opens files in place instead of copying every film', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();

      expect(plist, contains('<key>LSSupportsOpeningDocumentsInPlace</key>\n\t<true/>'));
    });
  });
}
