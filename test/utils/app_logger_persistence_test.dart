import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/utils/app_logger.dart';
import 'package:pleya/utils/persistent_log_store.dart';

void main() {
  test('restores recent diagnostics, redacts secrets and persists new logs and clearing', () async {
    final directory = await Directory.systemTemp.createTemp('pleya-logger-test-');
    try {
      MemoryLogOutput.clearLogs();
      final store = PersistentLogStore(directory);
      store.add({
        'time': DateTime.now().toIso8601String(),
        'level': 'debug',
        'message': 'previous session',
        'error': 'Authorization=Bearer-secret',
        'stack': 'https://example.test?X-Plex-Token=private',
      });
      store.add({
        'time': DateTime.now().subtract(const Duration(days: 8)).toIso8601String(),
        'level': 'info',
        'message': 'expired session',
      });
      await store.flush();
      await MemoryLogOutput.initializePersistence(directory);
      final logs = MemoryLogOutput.getLogs();
      expect(logs.map((e) => e.message), contains('previous session'));
      expect(logs.map((e) => e.message), isNot(contains('expired session')));
      expect(logs.single.error.toString(), isNot(contains('Bearer-secret')));
      expect(logs.single.stackTrace.toString(), isNot(contains('private')));
      appLogger.d('new session X-Plex-Token=secret');
      await MemoryLogOutput.flush();
      final saved = await PersistentLogStore(directory).read();
      expect(saved.last['message'], contains('new session'));
      expect(saved.last['message'], isNot(contains('=secret')));
      MemoryLogOutput.clearLogs();
      await MemoryLogOutput.flush();
      expect(await PersistentLogStore(directory).read(), isEmpty);
    } finally {
      await MemoryLogOutput.flush();
      await directory.delete(recursive: true);
    }
  });
}
