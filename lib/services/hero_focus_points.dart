/// Where to crop the iPhone Home hero card: the backdrop is landscape, the
/// card portrait, so `BoxFit.cover` keeps only a slice of its width. The
/// native side (`ios/Runner/AppDelegate.swift`, `com.pleya/hero_focus`) asks
/// Apple Vision for the salient region once per image; this keeps the answer
/// per artwork cache key in shared preferences, so the next launch does not
/// run Vision again.
library;

import 'dart:convert';

import 'package:cached_network_image_ce/cached_network_image.dart' show FileInfo;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import 'base_shared_preferences_service.dart';
import 'image_cache_service.dart';

/// The salient centre of an image, normalised (top-left origin), plus the
/// image's own width / height.
class HeroFocus {
  final double x;
  final double aspect;

  const HeroFocus(this.x, this.aspect);
}

/// The `BoxFit.cover` alignment that puts [focus] in the middle of a box with
/// [boxAspect] (width / height), clamped so the crop never leaves the image.
/// Vertically it stays at the top, as the hero always was.
Alignment heroFocusAlignment(HeroFocus? focus, {required double boxAspect}) {
  if (focus == null || focus.aspect <= 0 || boxAspect <= 0) return Alignment.topCenter;
  // The share of the image's width that stays on screen.
  final visible = boxAspect / focus.aspect;
  if (visible >= 1) return Alignment.topCenter;
  final left = (focus.x - visible / 2).clamp(0.0, 1 - visible);
  return Alignment(left / (1 - visible) * 2 - 1, -1);
}

class HeroFocusPoints {
  HeroFocusPoints({
    Future<HeroFocus?> Function(String path)? detect,
    Future<String> Function(String url, String key)? localFile,
    Future<String?> Function()? readStore,
    Future<void> Function(String json)? writeStore,
  }) : _detect = detect ?? _detectNative,
       _localFile = localFile ?? _cachedArtworkFile,
       _readStore = readStore ?? _readPrefs,
       _writeStore = writeStore ?? _writePrefs;

  static final HeroFocusPoints instance = HeroFocusPoints();

  static const _channel = MethodChannel('com.pleya/hero_focus');
  static const prefsKey = 'hero_focus_points_v1';

  /// ponytail: oldest entry goes first, not least recently used. A hero set
  /// is a handful of films; raise this if the carousel ever grows large.
  static const maxEntries = 200;

  final Future<HeroFocus?> Function(String path) _detect;
  final Future<String> Function(String url, String key) _localFile;
  final Future<String?> Function() _readStore;
  final Future<void> Function(String json) _writeStore;

  /// Null as a value: looked at this session and nothing came back. Not
  /// persisted, so a failure is retried on the next launch.
  final Map<String, HeroFocus?> _known = {};
  final Map<String, Future<HeroFocus?>> _running = {};

  Future<HeroFocus?> resolve({required String url, required String key}) {
    if (_known.containsKey(key)) return Future.value(_known[key]);
    // Block body on purpose: `=> _running.remove(key)` would return this very
    // future to whenComplete, which then waits on itself forever.
    return _running[key] ??= _lookup(url, key).whenComplete(() {
      _running.remove(key);
    });
  }

  Future<HeroFocus?> _lookup(String url, String key) async {
    try {
      final hit = (await _readStored())[key];
      if (hit != null) return _known[key] = hit;
      final found = _known[key] = await _detect(await _localFile(url, key));
      if (found != null) await _store(key, found);
      return found;
    } catch (_) {
      // No channel (tests, other platforms), no file, no network, no prefs:
      // keep the plain crop.
      return _known[key] = null;
    }
  }

  /// Insertion-ordered (a map literal is a LinkedHashMap), oldest first.
  Future<Map<String, HeroFocus>> _readStored() async {
    final map = <String, HeroFocus>{};
    final raw = await _readStore();
    if (raw == null) return map;
    try {
      (jsonDecode(raw) as Map<String, dynamic>).forEach((key, value) {
        final pair = (value as List).cast<num>();
        map[key] = HeroFocus(pair[0].toDouble(), pair[1].toDouble());
      });
    } catch (_) {
      map.clear(); // A corrupt entry costs one Vision pass, not the hero.
    }
    return map;
  }

  Future<void> _store(String key, HeroFocus focus) async {
    final map = await _readStored()
      ..remove(key)
      ..[key] = focus;
    while (map.length > maxEntries) {
      map.remove(map.keys.first);
    }
    await _writeStore(
      jsonEncode({
        for (final e in map.entries) e.key: [e.value.x, e.value.aspect],
      }),
    );
  }

  static Future<String?> _readPrefs() async => (await BaseSharedPreferencesService.sharedCache()).getString(prefsKey);

  static Future<void> _writePrefs(String json) async =>
      (await BaseSharedPreferencesService.sharedCache()).setString(prefsKey, json);

  static Future<HeroFocus?> _detectNative(String path) async {
    final result = await _channel.invokeMapMethod<String, double>('focusPoint', path);
    if (result == null) return null;
    final x = result['x'];
    final aspect = result['aspect'];
    return x == null || aspect == null ? null : HeroFocus(x, aspect);
  }

  /// The file the hero image itself loads from. Already on disk in the usual
  /// case; the first sight of a new backdrop may fetch it a second time
  /// alongside the image widget, once, because the result is then stored.
  static Future<String> _cachedArtworkFile(String url, String key) async {
    final response = await PlexImageCacheManager.instance.getFileStream(url, key: key).firstWhere((r) => r is FileInfo);
    return (response as FileInfo).file.path;
  }
}
