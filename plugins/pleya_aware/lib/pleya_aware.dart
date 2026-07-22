import 'dart:async';

import 'package:flutter/services.dart';

/// A Pleya Share host discovered over Wi-Fi Aware.
class AwareHost {
  final int peerId;

  /// Opaque service info the host advertises (Pleya: the relayHostId).
  final String serviceInfo;

  const AwareHost({required this.peerId, required this.serviceInfo});
}

/// A bidirectional byte stream to/from an Aware peer. Write/close are
/// injectable so tests can link two streams in-process.
class AwareStream {
  final int id;
  final Stream<Uint8List> input;
  final Future<void> Function(Uint8List bytes)? _write;
  final Future<void> Function()? _close;

  AwareStream({
    required this.id,
    required this.input,
    Future<void> Function(Uint8List bytes)? write,
    Future<void> Function()? close,
  })  : _write = write,
        _close = close;

  Future<void> write(Uint8List bytes) =>
      _write?.call(bytes) ?? PleyaAware._channel.invokeMethod('write', {'streamId': id, 'bytes': bytes});

  Future<void> close() => _close?.call() ?? PleyaAware._channel.invokeMethod('closeStream', {'streamId': id});
}

/// Wi-Fi Aware transport: routerless peer-to-peer Wi-Fi (Android 8+ with
/// Aware hardware; iOS 26+ on iPhone 12 and newer). Purely additive next to
/// LAN/hotspot/cable/relay: callers must gate on [isSupported].
class PleyaAware {
  PleyaAware._();

  static const _channel = MethodChannel('pleya_aware');
  static const _events = EventChannel('pleya_aware/events');

  static Stream<Map<Object?, Object?>>? _eventStream;
  static final Map<int, StreamController<Uint8List>> _streamData = {};
  static final _incoming = StreamController<AwareStream>.broadcast();
  static final _discovered = StreamController<AwareHost>.broadcast();

  static Stream<Map<Object?, Object?>> get _rawEvents =>
      _eventStream ??= _events.receiveBroadcastStream().cast<Map<Object?, Object?>>()..listen(_dispatch);

  static void _dispatch(Map<Object?, Object?> event) {
    switch (event['type'] as String?) {
      case 'accepted':
        final id = event['streamId'] as int;
        // ignore: close_sinks — closed via the 'closed' event / close().
        final controller = _streamData[id] = StreamController<Uint8List>();
        _incoming.add(AwareStream(id: id, input: controller.stream));
      case 'data':
        _streamData[event['streamId'] as int]?.add(event['bytes'] as Uint8List);
      case 'closed':
        _streamData.remove(event['streamId'] as int)?.close();
      case 'discovered':
        _discovered.add(AwareHost(peerId: event['peerId'] as int, serviceInfo: event['serviceInfo'] as String? ?? ''));
    }
  }

  static Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── Host ──

  /// Advertise the Pleya Share service; [serviceInfo] identifies this host
  /// (the relayHostId). Incoming byte streams arrive on [incomingStreams].
  static Future<void> startPublishing(String serviceInfo) async {
    _rawEvents; // ensure listener attached
    await _channel.invokeMethod('startPublishing', {'serviceInfo': serviceInfo});
  }

  static Future<void> stopPublishing() => _channel.invokeMethod('stopPublishing');

  static Stream<AwareStream> get incomingStreams => _incoming.stream;

  // ── Guest ──

  /// Discover nearby Pleya Share hosts for [timeout]. Also leaves the
  /// subscriber session open so [connect] can reach the found peers.
  static Future<List<AwareHost>> discover({Duration timeout = const Duration(seconds: 4)}) async {
    _rawEvents;
    final found = <int, AwareHost>{};
    final sub = _discovered.stream.listen((host) => found[host.peerId] = host);
    try {
      await _channel.invokeMethod('startDiscovery');
      await Future<void>.delayed(timeout);
    } finally {
      await sub.cancel();
    }
    return found.values.toList();
  }

  static Future<void> stopDiscovery() => _channel.invokeMethod('stopDiscovery');

  /// Open a byte stream to a discovered host.
  static Future<AwareStream> connect(AwareHost host) async {
    _rawEvents;
    final id = await _channel.invokeMethod<int>('connect', {'peerId': host.peerId});
    if (id == null) throw StateError('aware connect failed');
    // ignore: close_sinks — closed via the 'closed' event / close().
    final controller = _streamData[id] = StreamController<Uint8List>();
    return AwareStream(id: id, input: controller.stream);
  }

  /// iOS only: present the system Wi-Fi Aware pairing sheet (DeviceDiscoveryUI).
  /// No-op on Android (no pairing requirement there).
  static Future<void> presentPairing({required bool asHost}) async {
    try {
      await _channel.invokeMethod('presentPairing', {'asHost': asHost});
    } catch (_) {}
  }
}
