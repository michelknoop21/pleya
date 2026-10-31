import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../media/deferred_subtitle.dart';
import '../utils/app_logger.dart';
import '../utils/media_server_http_client.dart' show AbortController;

enum DeferredSubtitleStatus { idle, preparing, failed }

/// How long the server remembers a failed extraction (`subtitleFailureMemory`
/// in `internal/transcode/subtitles.go`). Within it the same `502` comes straight
/// back and nothing is tried, so "Opnieuw" waits it out.
const Duration deferredSubtitleFailureMemory = Duration(seconds: 15);

/// Owns the one deferred subtitle of a player: the wait, the attach, the file.
///
/// The film plays on throughout. A new [start] replaces the previous track, so
/// choosing another track or leaving it is what stops the wait.
class DeferredSubtitleLoader extends ChangeNotifier {
  DeferredSubtitleLoader({required this.attach, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final Future<void> Function(File file, DeferredSubtitle subtitle) attach;
  final DateTime Function() _now;

  DeferredSubtitleStatus _status = DeferredSubtitleStatus.idle;
  DeferredSubtitle? _subtitle;
  AbortController? _abort;
  File? _file;
  int _generation = 0;
  bool _disposed = false;
  DateTime? _failedAt;

  DeferredSubtitleStatus get status => _status;

  /// Stops the wait and leaves an attached track alone, for a reload that may still fail.
  void abortPending() {
    if (_status != DeferredSubtitleStatus.preparing) return;
    _generation++;
    _abort?.abort();
    _abort = null;
    _subtitle = null;
    _setStatus(DeferredSubtitleStatus.idle);
  }

  /// Replaces the current track with [subtitle]. [ready] holds the attach back
  /// until the player has a file loaded; a track cannot be added before that.
  ///
  /// [wait] holds the first request back; a new [start] ends it.
  Future<void> start(DeferredSubtitle? subtitle, {Future<void>? ready, Duration wait = Duration.zero}) async {
    if (_disposed) return;
    final generation = ++_generation;
    _abort?.abort();
    final previous = _file;
    _file = null;
    _subtitle = subtitle;
    _delete(previous);
    if (subtitle == null) {
      _abort = null;
      _setStatus(DeferredSubtitleStatus.idle);
      return;
    }
    final abort = AbortController();
    _abort = abort;
    _setStatus(DeferredSubtitleStatus.preparing);
    bool current() => generation == _generation && !_disposed;
    File? file;
    try {
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
        if (!current()) return;
      }
      file = await subtitle.load(abort);
      if (!current()) return _delete(file);
      await ready;
      if (!current()) return _delete(file);
      await attach(file, subtitle);
      if (!current()) return _delete(file);
      _file = file;
      _setStatus(DeferredSubtitleStatus.idle);
    } catch (e) {
      _delete(file);
      if (!current()) return;
      appLogger.w('Deferred subtitle failed', error: e);
      _failedAt = _now();
      _setStatus(DeferredSubtitleStatus.failed);
    }
  }

  /// The "Opnieuw" of a failed track.
  void retry() {
    if (_status != DeferredSubtitleStatus.failed) return;
    final failedAt = _failedAt;
    final elapsed = failedAt == null ? deferredSubtitleFailureMemory : _now().difference(failedAt);
    unawaited(start(_subtitle, wait: deferredSubtitleFailureMemory - elapsed));
  }

  /// A backend switch gives the player an empty track list; the file is still good.
  Future<void> reattach() async {
    final file = _file;
    final subtitle = _subtitle;
    if (file == null || subtitle == null) return;
    await attach(file, subtitle);
  }

  void _setStatus(DeferredSubtitleStatus status) {
    if (_status == status || _disposed) return;
    _status = status;
    notifyListeners();
  }

  void _delete(File? file) {
    if (file == null) return;
    unawaited(
      file.delete().then<void>(
        (_) {},
        onError: (Object e) => appLogger.d('Could not delete a temporary subtitle', error: e),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _abort?.abort();
    _delete(_file);
    _file = null;
    super.dispose();
  }
}
