import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../connection/connection.dart';
import '../utils/app_logger.dart';

/// Security-scoped folder access for iOS/macOS local folder sources.
///
/// The generic file_picker discards the picked folder's security scope, so
/// sandbox reads fail (silently empty libraries). This service talks to the
/// native `SecureFolderPlugin`, which returns a persistable bookmark on pick
/// and re-opens the scope from that bookmark after app restarts.
class SecureFolderService {
  SecureFolderService._();
  static final instance = SecureFolderService._();

  static const _channel = MethodChannel('com.pleya/secure_folder');

  static bool get isRequired => Platform.isIOS || Platform.isMacOS;

  /// Connection-ids whose bookmark has been resolved (scope open) this session.
  final Map<String, String> _resolvedPaths = {};

  /// In-flight resolves per connection, so concurrent scans share one
  /// resolveBookmark call instead of racing double persists.
  final Map<String, Future<String>> _inFlight = {};

  /// Invoked when resolving returned a refreshed (stale) bookmark or a moved
  /// path, so the owner can persist the updated connection.
  FutureOr<void> Function(LocalFolderConnection updated)? onConnectionUpdated;

  /// Present the native folder picker. Returns the path plus the bookmark
  /// that must be stored in [LocalFolderConnection.bookmarkData].
  Future<({String path, String bookmark})?> pickFolder() async {
    if (!isRequired) return null;
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('pickFolder');
      final path = result?['path'] as String?;
      final bookmark = result?['bookmark'] as String?;
      if (path == null || bookmark == null) return null;
      return (path: path, bookmark: bookmark);
    } catch (e) {
      appLogger.w('SecureFolder: pickFolder failed', error: e);
      return null;
    }
  }

  /// Make sure [connection]'s folder is readable and return the usable root
  /// path (may differ from the stored one after a restore/move). Resolves the
  /// bookmark once per session. Connections without a bookmark (Android,
  /// pre-fix rows) pass through unchanged.
  Future<String> ensureAccess(LocalFolderConnection connection) async {
    final cached = _resolvedPaths[connection.id];
    if (cached != null) return cached;
    final bookmark = connection.bookmarkData;
    if (!isRequired || bookmark == null || bookmark.isEmpty) {
      return connection.directoryUri;
    }
    return _inFlight[connection.id] ??= _resolve(
      connection,
      bookmark,
    ).whenComplete(() => _inFlight.remove(connection.id));
  }

  Future<String> _resolve(LocalFolderConnection connection, String bookmark) async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('resolveBookmark', {'bookmark': bookmark});
      final path = result?['path'] as String? ?? connection.directoryUri;
      final freshBookmark = result?['bookmark'] as String?;
      _resolvedPaths[connection.id] = path;
      if (freshBookmark != null || path != connection.directoryUri) {
        final updated = connection.copyWith(directoryUri: path, bookmarkData: freshBookmark ?? bookmark);
        try {
          await onConnectionUpdated?.call(updated);
        } catch (e) {
          appLogger.w('SecureFolder: failed to persist refreshed bookmark', error: e);
        }
      }
      return path;
    } catch (e) {
      appLogger.w('SecureFolder: resolveBookmark failed for ${connection.displayName}', error: e);
      return connection.directoryUri;
    }
  }

  /// Human-readable reason of the most recent failed [listDirectory] call,
  /// so the UI can show WHY a folder came back empty instead of a bare
  /// empty state. Cleared on the next successful listing.
  String? lastListError;

  /// Native directory enumeration for iOS/macOS. Returns raw entry maps
  /// (`uri`, `name`, `isDir`, `length`, `lastModified`) or null on failure.
  /// Unlike Dart's `Directory.list`, this reaches File Provider folders.
  Future<List<Map<Object?, Object?>>?> listDirectory(String path) async {
    if (!isRequired) return null;
    try {
      // Belt-and-braces: a hung provider must surface as an error, never as an
      // infinite spinner in the library.
      final raw = await _channel
          .invokeListMethod<Map<Object?, Object?>>('listDirectory', {'path': path})
          .timeout(const Duration(seconds: 30));
      lastListError = null;
      return raw;
    } on TimeoutException {
      lastListError = 'timeout listing $path';
      appLogger.w('SecureFolder: listDirectory timed out for $path');
      return null;
    } on PlatformException catch (e) {
      lastListError = [e.message, e.details].whereType<Object>().join(' · ');
      appLogger.w('SecureFolder: listDirectory failed for $path', error: e);
      return null;
    } catch (e) {
      lastListError = '$e';
      appLogger.w('SecureFolder: listDirectory failed for $path', error: e);
      return null;
    }
  }

  void forget(String connectionId) {
    final path = _resolvedPaths.remove(connectionId);
    // Balance the native startAccessingSecurityScopedResource so the OS scope
    // isn't leaked after a source is removed or re-resolved.
    if (isRequired && path != null) {
      _channel.invokeMethod<void>('stopAccess', {'path': path}).catchError((Object e) {
        appLogger.w('SecureFolder: stopAccess failed', error: e);
      });
    }
  }
}
