import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/mpv/player/player_native.dart';
import 'package:pleya/utils/app_logger.dart';
import 'package:pleya/utils/persistent_log_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native memory evidence is on disk before the next one-second log batch', () async {
    final directory = await Directory.systemTemp.createTemp('pleya-native-memory-');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('com.pleya/mpv_player');
    const events = MethodChannel('com.pleya/mpv_player/events');
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    messenger.setMockMethodCallHandler(events, (_) async => null);
    MemoryLogOutput.clearLogs();
    await MemoryLogOutput.initializePersistence(directory);
    final player = PlayerNative();
    try {
      final ordinaryLog = player.streams.log.first;
      player.handlePlayerEvent('log-message', {'prefix': 'cplayer', 'level': 'warn', 'text': 'ordinary warning'});
      await ordinaryLog;
      expect(await PersistentLogStore(directory).read(), isEmpty);

      player.handlePropertyChange('demuxer-cache-state', {'total-bytes': 64 << 20});
      final memoryLog = player.streams.log.first;
      player.handlePlayerEvent('log-message', {
        'prefix': 'pleya-memory',
        'level': 'warn',
        'text': 'memory-pressure footprint=1234MB remaining=12MB',
      });
      await memoryLog;
      final saved = await PersistentLogStore(directory).read();
      expect(saved.last['message'], contains('footprint=1234MB remaining=12MB'));
      expect(saved.last['message'], contains('demux-cache=64MB'));

      player.handlePropertyChange('demuxer-cache-state', null);
      final clearedLog = player.streams.log.first;
      player.handlePlayerEvent('log-message', {'prefix': 'pleya-memory', 'level': 'warn', 'text': 'new title'});
      await clearedLog;
      expect((await PersistentLogStore(directory).read()).last['message'], isNot(contains('demux-cache=')));
    } finally {
      await player.dispose();
      await MemoryLogOutput.flush();
      await directory.delete(recursive: true);
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(events, null);
    }
  });
}
