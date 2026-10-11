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

  /// Who plays an opened file. Setting it hands over what is already waiting;
  /// without a listener the paths stay on the native side.
  set listener(void Function(String path)? value) {
    _listener = value;
    if (value != null) unawaited(_drain());
  }

  Future<dynamic> _handleCall(MethodCall call) async {
    if (call.method == 'onFilesAvailable') await _drain();
  }

  Future<void> _drain() async {
    if (!_supported || _listener == null) return;
    try {
      final paths = await _channel.invokeListMethod<String>('takePendingFiles') ?? const <String>[];
      if (paths.isEmpty) return;
      // One player: of several files opened together the last one plays.
      if (paths.length > 1) appLogger.i('Opened files: ${paths.length} received, playing the last');
      _listener?.call(paths.last);
    } catch (e) {
      appLogger.w('Opened files: could not read the pending list', error: e);
    }
  }
}
