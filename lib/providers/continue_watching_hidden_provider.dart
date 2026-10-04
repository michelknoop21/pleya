import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../services/storage_service.dart';
import '../utils/app_logger.dart';
import '../utils/formatters.dart';

/// One title the viewer hid from Verder kijken on this device.
///
/// Carries its own title and place because the hidden list has to name the
/// entry without the item: a hidden item is by definition not in the list the
/// rest of the app holds.
@immutable
class HiddenContinueWatchingEntry {
  const HiddenContinueWatchingEntry({
    required this.globalKey,
    required this.title,
    this.subtitle,
    required this.hiddenAt,
  });

  final String globalKey;
  final String title;
  final String? subtitle;
  final int hiddenAt;

  String encode() => jsonEncode({'key': globalKey, 'title': title, 'subtitle': ?subtitle, 'hiddenAt': hiddenAt});

  static HiddenContinueWatchingEntry? decode(String line) {
    try {
      final json = jsonDecode(line);
      if (json is! Map<String, dynamic>) return null;
      final key = json['key'];
      final title = json['title'];
      if (key is! String || key.isEmpty || title is! String) return null;
      final subtitle = json['subtitle'];
      final hiddenAt = json['hiddenAt'];
      return HiddenContinueWatchingEntry(
        globalKey: key,
        title: title,
        subtitle: subtitle is String ? subtitle : null,
        hiddenAt: hiddenAt is int ? hiddenAt : 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// The titles hidden from Verder kijken on this device, per profile (DEC-144
/// fase 3).
///
/// This is what "Verbergen uit Verder kijken · Alleen op dit apparaat" writes
/// for a source that cannot remove server-side (Jellyfin, Emby, local folders).
/// It never syncs (`preference_sync_policy.dart`), nothing here deletes
/// anything on a server, and [restore] puts a title back.
class ContinueWatchingHiddenProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  ContinueWatchingHiddenProvider({StorageService? storageService, this.profileId}) : _storage = storageService {
    _initFuture = _load();
  }

  StorageService? _storage;
  final String? profileId;
  late final Future<void> _initFuture;
  List<HiddenContinueWatchingEntry> _entries = const [];

  Future<void> ensureInitialized() => _initFuture;

  /// Newest first: the one just hidden is the one most likely wanted back.
  List<HiddenContinueWatchingEntry> get entries => List.unmodifiable(_entries);

  Set<String> get keys => {for (final e in _entries) e.globalKey};

  int get count => _entries.length;

  /// Never throws: a store that cannot be read is an empty hidden list, not a
  /// Home that fails to load.
  Future<void> _load() async {
    try {
      final storage = _storage ??= await StorageService.getInstance();
      _entries = [
        for (final line in storage.getHiddenContinueWatching(profileId)) ?HiddenContinueWatchingEntry.decode(line),
      ];
    } catch (e, st) {
      appLogger.w('ContinueWatchingHiddenProvider: could not read the hidden list', error: e, stackTrace: st);
    }
    safeNotifyListeners();
  }

  Future<void> hide(MediaItem item) async {
    await ensureInitialized();
    final key = item.globalKey;
    final place = item.isEpisode
        ? [?formatSeasonEpisodeLabel(item.parentIndex, item.index), ?item.displaySubtitle].join(' · ')
        : null;
    _entries = [
      HiddenContinueWatchingEntry(
        globalKey: key,
        title: item.displayTitle,
        subtitle: place == null || place.isEmpty ? null : place,
        hiddenAt: DateTime.now().millisecondsSinceEpoch,
      ),
      for (final e in _entries)
        if (e.globalKey != key) e,
    ];
    await _save();
  }

  /// No-op for a key that is not hidden, so a caller can restore blindly.
  Future<void> restore(String globalKey) async {
    await ensureInitialized();
    final remaining = [
      for (final e in _entries)
        if (e.globalKey != globalKey) e,
    ];
    if (remaining.length == _entries.length) return;
    _entries = remaining;
    await _save();
  }

  Future<void> _save() async {
    safeNotifyListeners();
    final storage = _storage ??= await StorageService.getInstance();
    await storage.saveHiddenContinueWatching(profileId, [for (final e in _entries) e.encode()]);
  }
}
