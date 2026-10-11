import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
  /// (profile chooser on top, screen going away). [redeliver] or the next
  /// [attach] offers it again.
  void defer(String path) => _deferred.add(path);

  /// Offers the deferred paths, and anything new on the native side, again.
  void redeliver() => unawaited(_drain());

  Future<dynamic> _handleCall(MethodCall call) async {
    if (call.method == 'onFilesAvailable') await _drain();
  }

  Future<void> _drain() async {
    if (_listener == null) return;
    try {
      final paths = List<String>.of(_deferred);
      _deferred.clear();
      if (_supported) paths.addAll(await _channel.invokeListMethod<String>('takePendingFiles') ?? const <String>[]);
      if (paths.isEmpty) return;
      final listener = _listener;
      if (listener == null) {
        _deferred.addAll(paths);
        return;
      }
      // One player: of several files opened together the last one plays.
      if (paths.length > 1) appLogger.i('Opened files: ${paths.length} received, playing the last');
      listener(paths.last);
    } catch (e) {
      appLogger.w('Opened files: could not read the pending list', error: e);
    }
  }
}
