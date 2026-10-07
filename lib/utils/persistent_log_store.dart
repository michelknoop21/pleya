import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Two bounded JSONL files; a partial final line after process death is ignored.
class PersistentLogStore {
  PersistentLogStore(this.directory, {this.maxFileBytes = 2500000});

  final Directory directory;
  final int maxFileBytes;
  File get _current => File('${directory.path}/current.jsonl');
  File get _previous => File('${directory.path}/previous.jsonl');
  Future<void> _writes = Future<void>.value();
  final List<String> _pending = [];
  Timer? _timer;

  Future<List<Map<String, dynamic>>> read() async {
    await directory.create(recursive: true);
    final entries = <Map<String, dynamic>>[];
    for (final file in [_previous, _current]) {
      if (!await file.exists()) continue;
      if ((await file.lastModified()).isBefore(DateTime.now().subtract(const Duration(days: 7)))) {
        await file.delete();
        continue;
      }
      final contents = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      if (contents.isNotEmpty && !contents.endsWith('\n')) {
        await file.writeAsString('\n', mode: FileMode.append, flush: true);
      }
      for (final line in const LineSplitter().convert(contents)) {
        try {
          entries.add(jsonDecode(line) as Map<String, dynamic>);
        } on Object {
          // A killed process may leave the last write incomplete.
        }
      }
    }
    return entries;
  }

  void add(Map<String, dynamic> entry) {
    final line = '${jsonEncode(entry)}\n';
    // A single giant diagnostic must not exceed the storage budget.
    if (utf8.encode(line).length > maxFileBytes) return;
    _pending.add(line);
    _timer ??= Timer(const Duration(seconds: 1), () => unawaited(flush()));
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    final lines = List<String>.of(_pending);
    _pending.clear();
    return _enqueue(() async {
      var size = await _current.exists() ? await _current.length() : 0;
      final batch = StringBuffer();
      Future<void> writeBatch() async {
        if (batch.isEmpty) return;
        await _current.writeAsString(batch.toString(), mode: FileMode.append, flush: true);
        batch.clear();
      }

      for (final line in lines) {
        final bytes = utf8.encode(line).length;
        if (size + bytes > maxFileBytes) {
          await writeBatch();
          if (await _previous.exists()) await _previous.delete();
          if (await _current.exists()) await _current.rename(_previous.path);
          size = 0;
        }
        batch.write(line);
        size += bytes;
      }
      await writeBatch();
    });
  }

  Future<void> clear() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    return _enqueue(() async {
      for (final file in [_previous, _current]) {
        if (await file.exists()) await file.delete();
      }
    });
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    // Storage failure must not break playback or recursively log itself.
    _writes = _writes.then((_) => operation()).catchError((Object _) {});
    return _writes;
  }
}
