import 'package:flutter/foundation.dart';

/// A focus request that waits for the layer above it (info panel, sheet) to let
/// go. [ask] runs [request] at once when nothing blocks, else keeps one pending
/// request that [retry] replays after the release. [cancel] drops it.
class DeferredFocusGate {
  DeferredFocusGate({required this.isBlocked, required this.request});

  final bool Function() isBlocked;
  final VoidCallback request;
  bool _pending = false;

  bool get pending => _pending;

  void ask() {
    if (isBlocked()) {
      _pending = true;
      return;
    }
    request();
  }

  void retry() {
    if (!_pending || isBlocked()) return;
    _pending = false;
    request();
  }

  void cancel() => _pending = false;
}
