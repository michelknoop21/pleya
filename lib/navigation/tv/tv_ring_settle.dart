import 'dart:async';

import 'package:flutter/foundation.dart';

/// How long the ring has to rest on a pill before a sweep switches the page.
///
/// Longer than the 80 ms engine repeat of a held arrow (`tvos/engine.version`,
/// docs/tvos-remote-press-pipeline.md), so a held sweep coalesces; shorter
/// than a deliberate second click, which keeps its own switch.
const Duration kTvRingSettle = Duration(milliseconds: 150);

/// Coalesces page switches while the ring sweeps the top bar (DEC-XXX).
///
/// The ring landing on a pill switches the page. A single press switches at
/// once (leading edge), so there is no visible delay. A move that lands within
/// [settle] of the previous one only restarts the window, and the page follows
/// the pill the ring rests on when the window closes (trailing edge). A held
/// sweep from Zoeken to Instellingen therefore costs two switches instead of
/// six; Home's network refresh is one of the switches it skips.
class TvRingSettle {
  TvRingSettle({required this.activate, this.settle = kTvRingSettle});

  /// Switches the page to the pill the ring is on. Must be idempotent: it also
  /// runs when the window of a single press closes.
  final VoidCallback activate;

  final Duration settle;

  Timer? _window;

  /// Whether a sweep is waiting for the ring to rest.
  bool get isPending => _window?.isActive ?? false;

  /// The ring landed on a destination pill.
  void ringMoved() {
    final sweeping = isPending;
    _window?.cancel();
    _window = Timer(settle, activate);
    if (!sweeping) activate();
  }

  /// DOWN or Select inside the window: the page has to be the ring's before
  /// the remote goes anywhere.
  void flush() {
    if (!isPending) return;
    _window!.cancel();
    activate();
  }

  void dispose() => _window?.cancel();
}
