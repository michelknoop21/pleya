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

  group('progress queue', () {
    test('an opened file never queues progress, a download played offline does', () {
      final download = MediaItem(id: 'mv1', backend: MediaBackend.plex, kind: MediaKind.movie, serverId: 'srv');

      expect(queuesOfflineProgress(openedFileItem(_path), offlinePlayback: true), isFalse);
      expect(queuesOfflineProgress(download, offlinePlayback: true), isTrue);
      expect(queuesOfflineProgress(download, offlinePlayback: false), isFalse);
    });
  });

  group('OpenedFileService', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('com.pleya/open_file.test');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<String> pending;
    late int takeCalls;
    late List<String> released;

    setUp(() {
      pending = [];
      takeCalls = 0;
      released = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'releaseFiles') released.addAll((call.arguments as List).cast<String>());
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

      service.attach(played.add);
      await pumpEventQueue();

      expect(played, [_path]);
      expect(pending, isEmpty);
    });

    test('a file opened while the app runs plays on the native signal', () async {
      final service = OpenedFileService.forTesting(supported: true, channel: channel);
      final played = <String>[];
      service.attach(played.add);
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

      service.attach(played.add);
      await pumpEventQueue();

      expect(played, ['/a/two.mp4']);
    });

    test('the files that lose to the last one are released: nothing will ever play them', () async {
      pending.addAll(['/a/one.mp4', '/a/two.mp4']);
      final service = OpenedFileService.forTesting(supported: true, channel: channel);

      service.attach((_) {});
      await pumpEventQueue();

      expect(released, ['/a/one.mp4']);
    });

    test('a file is released when its player is gone', () async {
      final service = OpenedFileService.forTesting(supported: true, channel: channel);

      service.markPlaying(_path);
      await pumpEventQueue();
      expect(released, isEmpty, reason: 'the player still reads the file');

      service.markFinished(_path);
      await pumpEventQueue();
      expect(released, [_path]);
    });

    test('a file opened again keeps its access until the second player is gone too', () async {
      final service = OpenedFileService.forTesting(supported: true, channel: channel);

      service.markPlaying(_path);
      service.markPlaying(_path);
      service.markFinished(_path);
      await pumpEventQueue();
      expect(released, isEmpty, reason: 'the replacing player plays the same file');

      service.markFinished(_path);
      await pumpEventQueue();
      expect(released, [_path]);
    });

    test('a file that waits behind a route is not released by a player closing', () async {
      final service = OpenedFileService.forTesting(supported: true, channel: channel);

      service.markPlaying(_path);
      service.defer(_path);
      service.markFinished(_path);
      await pumpEventQueue();

      expect(released, isEmpty);
    });

    test('without a listener the signal leaves the path on the native side', () async {
      OpenedFileService.forTesting(supported: true, channel: channel);
      pending.add(_path);

      await nativeSignal();
      await pumpEventQueue();

      expect(pending, [_path]);
    });

    test('a screen disposed after its successor attached leaves that listener in place', () async {
      final service = OpenedFileService.forTesting(supported: true, channel: channel);
      final outgoing = <String>[];
      final incoming = <String>[];
      // Method tear-offs of two instances, as two MainScreen states are: equal
      // per instance, never identical.
      final outgoingScreen = _Screen(outgoing);
      final incomingScreen = _Screen(incoming);

      service.attach(outgoingScreen.onFile);
      service.attach(incomingScreen.onFile);
      service.detach(outgoingScreen.onFile);
      pending.add(_path);
      await nativeSignal();
      await pumpEventQueue();

      expect(incoming, [_path]);
      expect(outgoing, isEmpty);
    });

    test('a screen lets go of its own listener', () async {
      final service = OpenedFileService.forTesting(supported: true, channel: channel);
      final screen = _Screen([]);
      service.attach(screen.onFile);
      service.detach(screen.onFile);
      pending.add(_path);

      await nativeSignal();
      await pumpEventQueue();

      expect(screen.played, isEmpty);
      expect(pending, [_path]);
    });

    test('a failed native read keeps the deferred paths', () async {
      final service = OpenedFileService.forTesting(supported: true, channel: channel);
      var covered = true;
      final played = <String>[];
      service.attach((path) => covered ? service.defer(path) : played.add(path));
      pending.add(_path);
      await nativeSignal();
      await pumpEventQueue();

      messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'gone'));
      covered = false;
      service.redeliver();
      await pumpEventQueue();
      expect(played, isEmpty);

      messenger.setMockMethodCallHandler(channel, (call) async => const <String>[]);
      service.redeliver();
      await pumpEventQueue();
      expect(played, [_path]);
    });

    test('a deferred file is offered again, to the same listener or the next one', () async {
      final service = OpenedFileService.forTesting(supported: true, channel: channel);
      var chooserOpen = true;
      final played = <String>[];
      void listener(String path) => chooserOpen ? service.defer(path) : played.add(path);
      service.attach(listener);
      pending.add(_path);
      await nativeSignal();
      await pumpEventQueue();
      expect(played, isEmpty);

      chooserOpen = false;
      service.redeliver();
      await pumpEventQueue();
      expect(played, [_path]);

      service.defer('/a/later.mp4');
      final next = <String>[];
      service.attach(next.add);
      await pumpEventQueue();
      expect(next, ['/a/later.mp4']);
    });

    test('an unsupported platform never touches the channel', () async {
      pending.add(_path);
      final service = OpenedFileService.forTesting(supported: false, channel: channel);

      service.attach((_) => fail('no file can arrive here'));
      await pumpEventQueue();

      expect(takeCalls, 0);
    });
  });

  group('playOpenedFile', () {
    testWidgets('starts the player on its offline path, the only one without a server client', (tester) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(navigatorKey: key, home: const SizedBox()));
      MediaItem? played;
      bool? offline;
      bool? fresh;
      bool? replaced;

      await playOpenedFile(
        key.currentContext!,
        _path,
        navigate:
            (
              context, {
              required metadata,
              usePushReplacement = false,
              isOffline = false,
              resolveWatchState = true,
            }) async {
              played = metadata;
              offline = isOffline;
              fresh = resolveWatchState;
              replaced = usePushReplacement;
              return null;
            },
      );

      expect(isOpenedFile(played!), isTrue);
      expect(played!.id, _path);
      expect(offline, isTrue);
      expect(fresh, isFalse);
      expect(replaced, isFalse);
    });

    testWidgets('holds the file while the player is open and lets go of it after, also when the start throws', (
      tester,
    ) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(navigatorKey: key, home: const SizedBox()));
      const channel = MethodChannel('com.pleya/open_file.launcher_test');
      final released = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'releaseFiles') released.addAll((call.arguments as List).cast<String>());
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
      final service = OpenedFileService.forTesting(supported: true, channel: channel);
      final closed = Completer<bool?>();

      final playing = playOpenedFile(
        key.currentContext!,
        _path,
        service: service,
        navigate:
            (context, {required metadata, usePushReplacement = false, isOffline = false, resolveWatchState = true}) =>
                closed.future,
      );
      await tester.pump();
      expect(released, isEmpty, reason: 'the player is still open');

      closed.complete(null);
      await playing;
      await tester.pump();
      expect(released, [_path]);

      released.clear();
      await expectLater(
        playOpenedFile(
          key.currentContext!,
          _path,
          service: service,
          navigate:
              (context, {required metadata, usePushReplacement = false, isOffline = false, resolveWatchState = true}) =>
                  throw StateError('no player'),
        ),
        throwsStateError,
      );
      await tester.pump();
      expect(released, [_path]);
    });
  });

  group('a route on the root navigator', () {
    testWidgets('covers the session below it, and its removal offers the waiting file again', (tester) async {
      const channel = MethodChannel('com.pleya/open_file.cover');
      final service = OpenedFileService.forTesting(supported: false, channel: channel);
      final rootKey = GlobalKey<NavigatorState>();
      final sessionKey = GlobalKey<NavigatorState>();
      final insideKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootKey,
          navigatorObservers: [OpenedFileRouteObserver(service)],
          home: Navigator(
            key: sessionKey,
            onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => SizedBox(key: insideKey)),
          ),
        ),
      );
      final played = <String>[];
      void listener(String path) {
        if (isCoveredByOuterRoute(insideKey.currentContext!)) {
          service.defer(path);
        } else {
          played.add(path);
        }
      }

      service.attach(listener);
      expect(isCoveredByOuterRoute(insideKey.currentContext!), isFalse);

      // A page on the session navigator itself does not hide a player pushed there.
      unawaited(sessionKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const SizedBox())));
      await tester.pumpAndSettle();
      expect(isCoveredByOuterRoute(insideKey.currentContext!), isFalse);

      // The profile chooser on the root navigator does.
      unawaited(rootKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const SizedBox())));
      await tester.pumpAndSettle();
      expect(isCoveredByOuterRoute(insideKey.currentContext!), isTrue);
      listener(_path);
      expect(played, isEmpty);

      rootKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(played, [_path]);
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

    test('ios lets go of a released file: its security scope and its Inbox copy', () {
      final plugin = File('ios/Runner/OpenFilePlugin.swift').readAsStringSync();
      final release = plugin.substring(plugin.indexOf('private static func release('));

      expect(plugin, contains('case "releaseFiles":'));
      expect(release, contains('scopedURLs.removeValue(forKey: path)?.stopAccessingSecurityScopedResource()'));
      expect(release, contains('if isOwnInbox('), reason: 'only a copy in our own container is ever deleted');
    });

    test('macos answers a release instead of failing the call', () {
      expect(File('macos/Runner/OpenFilePlugin.swift').readAsStringSync(), contains('case "releaseFiles":'));
    });

    test('ios opens files in place instead of copying every film', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();

      expect(plist, contains('<key>LSSupportsOpeningDocumentsInPlace</key>\n\t<true/>'));
    });
  });
}

class _Screen {
  _Screen(this.played);

  final List<String> played;

  void onFile(String path) => played.add(path);
}
