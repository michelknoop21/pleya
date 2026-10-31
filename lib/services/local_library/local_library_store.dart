import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../media/media_backend.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_library.dart';
import '../../utils/isolate_helper.dart';
import '../download_artwork_helpers.dart';

/// Durable, device-local storage belonging to exactly one Pleya profile.
/// Artwork is separate from the bounded transient image cache and downloads.
/// All mutations, including clear, share one queue so late IO cannot undo clear.
class LocalLibraryStore {
  LocalLibraryStore(this.directory);
  final Directory directory;
  bool enabled = false;
  bool wifiOnly = true;
  final Map<String, Set<String>> libraryAccess = {};
  final Map<String, bool> serverAccess = {};
  final Map<String, MediaLibrary> _libraries = {};
  final Map<String, Map<String, MediaItem>> _items = {};
  final Map<String, DateTime> _completed = {};
  final Map<String, String> _posters = {};
  Future<void> _pending = Future.value();

  static String digest(String value) => sha256.convert(utf8.encode(value)).toString();
  static String _posterKey(String serverId, String path) => digest('$serverId|${artworkStorageKey(path)}');
  static Set<String> _posterKeys(Set<(String, String)> posters) => {
    for (final (serverId, path) in posters) _posterKey(serverId, path),
  };
  List<MediaItem> get items => _items.values.expand((v) => v.values).toList(growable: false);
  List<MediaLibrary> get libraries => _libraries.values.toList(growable: false);
  bool isComplete(String key) => _completed.containsKey(key);
  DateTime? get lastSync =>
      _completed.values.isEmpty ? null : _completed.values.reduce((a, b) => a.isBefore(b) ? a : b);
  MediaItem? item(String serverId, String id) {
    for (final rows in _items.values) {
      final hit = rows['$serverId:$id'];
      if (hit != null) return hit;
    }
    return null;
  }

  List<MediaItem> libraryItems(String key) => _items[key]?.values.toList(growable: false) ?? const [];
  static const _encodeBatch = 500;

  File get _optionsFile => File('${directory.path}/options.json');
  File _libraryFile(String key) => File('${directory.path}/library-${digest(key)}.json');

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _pending = _pending.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<void> load() async {
    await directory.create(recursive: true);
    if (await _optionsFile.exists()) {
      final data = jsonDecode(await _optionsFile.readAsString()) as Map<String, dynamic>;
      enabled = data['enabled'] == true;
      wifiOnly = data['wifiOnly'] != false;
      serverAccess.addAll((data['serverAccess'] as Map<String, dynamic>? ?? {}).cast<String, bool>());
      for (final entry in (data['libraryAccess'] as Map<String, dynamic>? ?? {}).entries) {
        libraryAccess[entry.key] = (entry.value as List).cast<String>().toSet();
      }
    }
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.json') || !entity.uri.pathSegments.last.startsWith('library-'))
        continue;
      final text = await entity.readAsString();
      final snapshot = await tryIsolateRun(() {
        final data = jsonDecode(text) as Map<String, dynamic>;
        final raw = data['library'] as Map<String, dynamic>;
        final library = MediaLibrary(
          id: raw['id'] as String,
          backend: MediaBackend.values.byName(raw['backend'] as String),
          title: raw['title'] as String,
          kind: MediaKind.fromString(raw['kind'] as String),
          serverId: raw['serverId'] as String,
          serverName: raw['serverName'] as String?,
        );
        final rows = <String, MediaItem>{};
        for (final value in data['items'] as List) {
          final item = MediaItem.fromJson(value as Map<String, dynamic>);
          rows[item.globalKey] = item;
        }
        return (library: library, rows: rows, completed: DateTime.tryParse(data['completed'] as String? ?? ''));
      });
      _libraries[snapshot.library.globalKey] = snapshot.library;
      _items[snapshot.library.globalKey] = snapshot.rows;
      if (snapshot.completed != null) _completed[snapshot.library.globalKey] = snapshot.completed!;
    }
    final posters = Directory('${directory.path}/posters');
    if (await posters.exists()) {
      await for (final entity in posters.list()) {
        if (entity is File && entity.path.endsWith('.image')) {
          final key = entity.uri.pathSegments.last.split('.').first;
          if (_version(entity.path) >= _version(_posters[key])) _posters[key] = entity.path;
        }
      }
    }
  }

  Future<void> _atomic(File target, String contents, bool Function() valid) async {
    final temporary = File('${target.path}.pending');
    await temporary.writeAsString(contents, flush: true);
    if (valid()) {
      await temporary.rename(target.path);
    } else if (await temporary.exists()) {
      await temporary.delete();
    }
  }

  /// Writes `head`, the rows as comma-separated JSON and `tail` to [target].
  ///
  /// The rows go through an isolate [_encodeBatch] at a time. Handing an isolate
  /// a whole library copies it on the calling thread first, which on a 34 MB
  /// library held the remote's key presses back by up to 148 ms on Apple TV.
  Future<void> _atomicRows(File target, String head, List<MediaItem> rows, String tail, bool Function() valid) async {
    final temporary = File('${target.path}.pending');
    final file = await temporary.open(mode: FileMode.write);
    try {
      await file.writeString(head);
      for (var start = 0; start < rows.length && valid(); start += _encodeBatch) {
        final end = start + _encodeBatch < rows.length ? start + _encodeBatch : rows.length;
        final encoded = await _encodeRows(rows.sublist(start, end));
        if (start > 0) await file.writeString(',');
        // Without the array brackets of this batch.
        await file.writeFrom(encoded, 1, encoded.length - 1);
      }
      await file.writeString(tail);
      await file.flush();
    } finally {
      await file.close();
    }
    if (valid()) {
      await temporary.rename(target.path);
    } else if (await temporary.exists()) {
      await temporary.delete();
    }
  }

  // A function of its own so the isolate's closure holds this batch and nothing
  // else from the caller's scope.
  static Future<Uint8List> _encodeRows(List<MediaItem> rows) =>
      tryIsolateRun(() => utf8.encode(jsonEncode([for (final row in rows) row.toJson()])));

  Map<String, Object?> get _options => {
    'enabled': enabled,
    'wifiOnly': wifiOnly,
    'serverAccess': serverAccess,
    'libraryAccess': {for (final e in libraryAccess.entries) e.key: e.value.toList()},
  };

  Future<void> saveAccess() => _serial(() => _atomic(_optionsFile, jsonEncode(_options), () => true));

  Future<void> setOptions({bool? enabled, bool? wifiOnly}) => _serial(() async {
    this.enabled = enabled ?? this.enabled;
    this.wifiOnly = wifiOnly ?? this.wifiOnly;
    await _atomic(_optionsFile, jsonEncode(_options), () => true);
  });

  /// An interrupted/partial scan may add fresh rows but never proves removal.
  Future<void> saveLibrary(
    MediaLibrary library,
    List<MediaItem> items, {
    required bool complete,
    bool Function()? isCurrent,
  }) => _serial(() async {
    bool valid() => isCurrent?.call() ?? true;
    if (!valid()) return;
    final key = library.globalKey;
    final next = <String, MediaItem>{if (!complete) ...?_items[key], for (final item in items) item.globalKey: item};
    final completed = complete ? DateTime.now() : _completed[key];
    await _persistLibrary(library, next, completed, valid);
    if (valid() && complete) await _pruneUnreferencedPosters();
  });

  Future<void> _persistLibrary(
    MediaLibrary library,
    Map<String, MediaItem> next,
    DateTime? completed,
    bool Function() valid,
  ) async {
    final key = library.globalKey;
    final head = jsonEncode({
      'library': {
        'id': library.id,
        'backend': library.backend.name,
        'title': library.title,
        'kind': library.kind.id,
        'serverId': library.serverId,
        'serverName': library.serverName,
      },
    });
    final tail = jsonEncode({'completed': completed?.toIso8601String()});
    await _atomicRows(
      _libraryFile(key),
      '${head.substring(0, head.length - 1)},"items":[',
      next.values.toList(),
      '],${tail.substring(1)}',
      valid,
    );
    if (!valid()) return;
    _libraries[key] = library;
    _items[key] = next;
    if (completed != null) _completed[key] = completed;
  }

  /// A confirmed source deletion changes membership without certifying an
  /// unfinished initial download as a fully synced library.
  Future<void> removeConfirmed(String serverId, String itemId, {bool Function()? isCurrent}) => _serial(() async {
    bool valid() => isCurrent?.call() ?? true;
    for (final library in _libraries.values.where((l) => l.serverId == serverId).toList()) {
      if (!valid()) return;
      final rows = _items[library.globalKey]!;
      final removed = {itemId};
      var size = -1;
      while (size != removed.length) {
        size = removed.length;
        for (final item in rows.values) {
          if (removed.contains(item.parentId) || removed.contains(item.grandparentId)) removed.add(item.id);
        }
      }
      if (!rows.values.any((i) => removed.contains(i.id))) continue;
      await _persistLibrary(
        library,
        {
          for (final i in rows.values)
            if (!removed.contains(i.id)) i.globalKey: i,
        },
        _completed[library.globalKey],
        valid,
      );
    }
    if (valid()) await _pruneUnreferencedPosters();
  });

  static int _version(String? path) =>
      path == null ? 0 : int.tryParse(path.split('/').last.split('.').elementAtOrNull(1) ?? '') ?? 0;

  Future<void> savePoster(String serverId, String path, Uint8List bytes, {bool Function()? isCurrent}) =>
      _serial(() async {
        bool valid() => isCurrent?.call() ?? true;
        if (!valid()) return;
        final key = _posterKey(serverId, path);
        final hash = sha256.convert(bytes).toString();
        if (_posters[key]?.endsWith('.$hash.image') ?? false) return;
        final priorVersion = _version(_posters[key]);
        final now = DateTime.now().microsecondsSinceEpoch;
        final version = now > priorVersion ? now : priorVersion + 1;
        final folder = Directory('${directory.path}/posters');
        await folder.create(recursive: true);
        final pending = File('${folder.path}/$key.pending');
        await pending.writeAsBytes(bytes, flush: true);
        if (!valid()) {
          await pending.delete();
          return;
        }
        final saved = await pending.rename('${folder.path}/$key.$version.$hash.image');
        if (valid()) _posters[key] = saved.path;
      });

  String? posterPath(String serverId, String path) => _posters[_posterKey(serverId, path)];

  Future<void> _pruneUnreferencedPosters() async {
    final posters = <(String, String)>{};
    for (final item in items) {
      for (final path in [item.thumbPath, item.parentThumbPath, item.grandparentThumbPath]) {
        if (item.serverId != null && path != null) posters.add((item.serverId!, path));
      }
    }
    // A hash per poster, in the hundreds of thousands on a large library: off
    // the UI thread, like the rest of a scan.
    final referenced = await tryIsolateRun(() => _posterKeys(posters));
    for (final key in _posters.keys.where((k) => !referenced.contains(k)).toList()) {
      final file = File(_posters.remove(key)!);
      if (await file.exists()) await file.delete();
    }
    final folder = Directory('${directory.path}/posters');
    if (await folder.exists()) {
      final kept = _posters.values.toSet();
      await for (final file in folder.list(followLinks: false)) {
        if (file is File && file.path.endsWith('.image') && !kept.contains(file.path)) await file.delete();
      }
    }
  }

  Future<int> storageBytes() => _serial(() async {
    var bytes = 0;
    if (!await directory.exists()) return 0;
    try {
      await for (final entity in directory.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        try {
          bytes += await entity.length();
        } on FileSystemException {
          if (await entity.exists()) rethrow;
        }
      }
    } on FileSystemException {
      if (await directory.exists()) rethrow;
    }
    return bytes;
  });

  Future<void> clear() => _serial(() async {
    enabled = false;
    // Persist off before removing data; a crash must not restart the download.
    await _atomic(_optionsFile, jsonEncode(_options), () => true);
    _libraries.clear();
    _items.clear();
    _completed.clear();
    _posters.clear();
    await for (final entity in directory.list(followLinks: false)) {
      if (entity.path != _optionsFile.path) await entity.delete(recursive: true);
    }
  });
}
