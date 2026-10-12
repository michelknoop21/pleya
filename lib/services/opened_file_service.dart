import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../utils/app_logger.dart';
import '../utils/platform_detector.dart';

/// Video files the system hands to Pleya: "Open in…" and the share sheet on
/// iPhone and iPad, "Open with" and a double click on the Mac.
///
/// The native side keeps every path until Dart takes it, so a file that
/// started the app waits for the first listener instead of getting lost.
class OpenedFileService {
  OpenedFileService._({bool? supported, MethodChannel? channel})
    : _supported = supported ?? ((Platform.isIOS && !PlatformDetector.isAppleTV()) || Platform.isMacOS),
      _channel = channel ?? const MethodChannel('com.pleya/open_file') {
    if (_supported) _channel.setMethodCallHandler(_handleCall);
  }

  static final instance = OpenedFileService._();

  @visibleForTesting
  factory OpenedFileService.forTesting({required bool supported, MethodChannel? channel}) =>
      OpenedFileService._(supported: supported, channel: channel);

  final bool _supported;
  final MethodChannel _channel;
  void Function(String path)? _listener;

  /// Paths a listener handed back because it could not play them yet.
  final List<String> _deferred = [];

  /// Makes [listener] the one that plays an opened file and hands it what is
  /// already waiting. Without a listener the paths stay on the native side.
  void attach(void Function(String path) listener) {
    _listener = listener;
    redeliver();
  }

  /// Lets go of [listener], but only while it is still the current one: when
  /// the profile session remounts, the outgoing screen is disposed after the
  /// incoming one attached, and must not take that one's listener with it.
  void detach(void Function(String path) listener) {
    // Equal, not identical: two tear-offs of one method are never identical.
    if (_listener == listener) _listener = null;
  }

  /// Keeps [path] for later: the listener got it at a moment it cannot play
  /// (a route covers it, the screen is going away). [redeliver] or the next
  /// [attach] offers it again.
  void defer(String path) => _deferred.add(path);

  /// Offers the deferred paths, and anything new on the native side, again.
  void redeliver() => unawaited(_drain());

  /// Players per path. Counted: the same file can be opened a second time
  /// while its first player is still being replaced.
  final Map<String, int> _playing = {};

  /// A player is about to start on [path]. The returned function says it is
  /// gone, and may be called more than once. Once no player has the file, the
  /// native side lets go of it: the security scope of a file opened in place,
  /// and the copy the system put in the Inbox, which would otherwise stay on
  /// the device until the next file arrives.
  VoidCallback markPlaying(String path) {
    _playing.update(path, (count) => count + 1, ifAbsent: () => 1);
    var done = false;
    return () {
      if (done) return;
      done = true;
      final left = (_playing[path] ?? 1) - 1;
      if (left > 0) {
        _playing[path] = left;
        return;
      }
      _playing.remove(path);
      _release([path]);
    };
  }

  /// Releases asked for while [_drain] waits for the native list. A path in
  /// that list is on its way to a player and in no bookkeeping yet, so the
  /// decision waits until the list has been handed out.
  final List<String> _releaseAfterDrain = [];
  // Counted: two reads can overlap (a native signal during a redelivery).
  int _draining = 0;

  void _release(Iterable<String> paths) {
    if (_draining > 0) {
      _releaseAfterDrain.addAll(paths);
      return;
    }
    // A path that still waits to be played, or plays, keeps its file.
    final free = paths.where((path) => !_playing.containsKey(path) && !_deferred.contains(path)).toSet().toList();
    if (!_supported || free.isEmpty) return;
    unawaited(
      _channel.invokeMethod<void>('releaseFiles', free).catchError((Object e) {
        appLogger.w('Opened files: could not release ${free.length} file(s)', error: e);
      }),
    );
  }

  Future<dynamic> _handleCall(MethodCall call) async {
    if (call.method == 'onFilesAvailable') await _drain();
  }

  Future<void> _drain() async {
    if (_listener == null) return;
    try {
      final List<String>? taken;
      _draining++;
      try {
        taken = _supported ? await _channel.invokeListMethod<String>('takePendingFiles') : null;
      } finally {
        _draining--;
      }
      // Emptied only after the call: a failed read must not cost the deferred paths.
      final paths = [..._deferred, ...?taken];
      _deferred.clear();
      final listener = _listener;
      if (paths.isEmpty || listener == null) {
        _deferred.addAll(paths);
        _releaseWaiting();
        return;
      }
      // One player: of several files opened together the last one plays.
      if (paths.length > 1) appLogger.i('Opened files: ${paths.length} received, playing the last');
      listener(paths.last);
      // The others are never played; nothing else would ever let go of them.
      _release(paths.take(paths.length - 1).where((path) => path != paths.last));
      _releaseWaiting();
    } catch (e) {
      appLogger.w('Opened files: could not read the pending list', error: e);
      _releaseWaiting();
    }
  }

  void _releaseWaiting() {
    if (_draining > 0 || _releaseAfterDrain.isEmpty) return;
    final waiting = List<String>.of(_releaseAfterDrain);
    _releaseAfterDrain.clear();
    _release(waiting);
  }
}

/// On the root navigator: when a route there goes away (profile chooser,
/// dialog, a settings page), a file that waited behind it is offered again.
class OpenedFileRouteObserver extends NavigatorObserver {
  OpenedFileRouteObserver([OpenedFileService? service]) : _service = service;

  final OpenedFileService? _service;

  void _uncovered() => (_service ?? OpenedFileService.instance).redeliver();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _uncovered();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _uncovered();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _uncovered();
}
