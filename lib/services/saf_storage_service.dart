import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:saf_util/saf_util.dart';
import '../utils/app_logger.dart';
import '../utils/platform_detector.dart';
import 'secure_folder_service.dart';
import 'package:saf_util/saf_util_platform_interface.dart';

/// Handles directory access for local media sources.
///
/// On Android this uses the Storage Access Framework (content:// URIs with
/// persistable permissions). On other platforms it falls back to plain
/// filesystem paths via dart:io + file_picker, exposed through the same
/// [SafDocumentFile] shape so callers don't need to care.
class SafStorageService {
  static SafStorageService? _instance;
  static SafStorageService get instance => _instance ??= SafStorageService._();
  SafStorageService._();

  final SafUtil _safUtil = SafUtil();

  /// Check if SAF is available (Android only)
  bool get isAvailable => Platform.isAndroid;

  bool _isContentUri(String uri) => uri.startsWith('content://');

  /// Pick a directory. Returns a content:// URI (Android/SAF) or a plain
  /// filesystem path (desktop/iOS), or null if cancelled/unsupported.
  Future<String?> pickDirectory() async {
    // Document pickers are not available on TV form factors.
    if (TvDetectionService.isTVSync()) return null;
    if (isAvailable) {
      try {
        // Pick directory with persistent write permission
        final doc = await _safUtil.pickDirectory(writePermission: true, persistablePermission: true);
        return doc?.uri;
      } catch (e) {
        appLogger.w('SAF pickDirectory error', error: e);
        return null;
      }
    }
    try {
      return await FilePicker.platform.getDirectoryPath();
    } catch (e) {
      appLogger.w('Directory picker error', error: e);
      return null;
    }
  }

  /// Create a subdirectory in a SAF directory
  /// Returns the URI of the created directory
  Future<String?> createDirectory(String parentUri, String name) async =>
      createNestedDirectories(parentUri, [name]);

  /// Traverse to a child file/directory under a directory.
  /// [names] is the path-component list from [parentUri] to the target;
  /// pass a single element for an immediate child.
  Future<SafDocumentFile?> getChild(String parentUri, List<String> names) async {
    if (_isContentUri(parentUri)) {
      try {
        return await _safUtil.child(parentUri, names);
      } catch (e) {
        appLogger.w('SAF getChild error', error: e);
        return null;
      }
    }
    try {
      final path = [parentUri, ...names].join(Platform.pathSeparator);
      final type = await FileSystemEntity.type(path);
      if (type == FileSystemEntityType.notFound) return null;
      return _fromPath(path, isDir: type == FileSystemEntityType.directory);
    } catch (e) {
      appLogger.w('getChild error', error: e);
      return null;
    }
  }

  /// Create nested directories under a directory.
  /// Returns the URI/path of the deepest directory
  Future<String?> createNestedDirectories(String parentUri, List<String> pathComponents) async {
    if (_isContentUri(parentUri)) {
      try {
        final result = await _safUtil.mkdirp(parentUri, pathComponents);
        return result.uri;
      } catch (e) {
        appLogger.w('SAF createNestedDirectories error', error: e);
        return null;
      }
    }
    try {
      final dir = Directory([parentUri, ...pathComponents].join(Platform.pathSeparator));
      await dir.create(recursive: true);
      return dir.path;
    } catch (e) {
      appLogger.w('createNestedDirectories error', error: e);
      return null;
    }
  }

  /// Delete a file or directory. Returns true on success, false on error.
  Future<bool> delete(String uri, {required bool isDir}) async {
    if (_isContentUri(uri)) {
      try {
        await _safUtil.delete(uri, isDir);
        return true;
      } catch (e) {
        appLogger.w('SAF delete error', error: e);
        return false;
      }
    }
    try {
      if (isDir) {
        await Directory(uri).delete(recursive: true);
      } else {
        await File(uri).delete();
      }
      return true;
    } catch (e) {
      appLogger.w('delete error', error: e);
      return false;
    }
  }

  /// Check whether a file or directory exists. Returns false on error.
  Future<bool> exists(String uri, {required bool isDir}) async {
    if (_isContentUri(uri)) {
      try {
        return await _safUtil.exists(uri, isDir);
      } catch (e) {
        appLogger.w('SAF exists error', error: e);
        return false;
      }
    }
    try {
      return isDir ? Directory(uri).existsSync() : File(uri).existsSync();
    } catch (e) {
      appLogger.w('exists error', error: e);
      return false;
    }
  }

  /// List children of a directory. Returns null on error so callers can
  /// distinguish "error" from "empty dir".
  Future<List<SafDocumentFile>?> list(String uri) async {
    if (_isContentUri(uri)) {
      try {
        return await _safUtil.list(uri);
      } catch (e) {
        appLogger.w('SAF list error', error: e);
        return null;
      }
    }
    // iOS/macOS: enumerate natively so File Provider folders (another app's
    // shared storage, e.g. Infuse) list correctly — Dart's POSIX Directory.list
    // returns empty for those. Falls back to Directory.list on native failure.
    if (SecureFolderService.isRequired) {
      final native = await SecureFolderService.instance.listDirectory(uri);
      if (native != null) {
        return native
            .map(
              (m) => SafDocumentFile(
                uri: m['uri'] as String,
                name: m['name'] as String,
                isDir: m['isDir'] as bool? ?? false,
                length: (m['length'] as num?)?.toInt() ?? 0,
                lastModified: (m['lastModified'] as num?)?.toInt() ?? 0,
              ),
            )
            .toList();
      }
    }
    try {
      final entries = <SafDocumentFile>[];
      await for (final entity in Directory(uri).list(followLinks: false)) {
        entries.add(_fromPath(entity.path, isDir: entity is Directory));
      }
      return entries;
    } catch (e) {
      appLogger.w('list error', error: e);
      return null;
    }
  }

  SafDocumentFile _fromPath(String path, {required bool isDir}) {
    var length = 0;
    var lastModified = 0;
    if (!isDir) {
      try {
        final stat = File(path).statSync();
        length = stat.size;
        lastModified = stat.modified.millisecondsSinceEpoch;
      } catch (_) {}
    }
    return SafDocumentFile(
      uri: path,
      name: path.split(Platform.pathSeparator).last,
      isDir: isDir,
      length: length,
      lastModified: lastModified,
    );
  }
}
