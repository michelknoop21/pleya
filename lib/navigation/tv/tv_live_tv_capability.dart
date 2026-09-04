/// Remembers, per profile, that Live TV exists — so the navigation item does
/// not come and go with the network.
///
/// Hoofdstuk 19 of docs/tvos-unified-experience.md: "Bekende Live TV-capability
/// wordt per profiel onthouden, zodat het navigatie-item niet bij iedere
/// tijdelijke netwerkdip verdwijnt." On a vertical rail a row that vanishes is
/// a row that vanishes; in a horizontal bar it drags Mijn Pleya and everything
/// between it sideways under the user's thumb, and the pill they were aiming at
/// is now somewhere else. That is the concrete harm this store prevents.
///
/// The rule is deliberately asymmetric, because the evidence is:
///
/// * **Remember on any sighting.** One reachable DVR proves the capability.
/// * **Forget only on a conclusive check.** A poll that found nothing proves
///   nothing unless every expected server was online and answered —
///   [MultiServerProvider.lastLiveTvCheckWasConclusive]. Anything less is a
///   statement about the network, not about the profile.
///
/// Storage follows `PreferredServerStore`: a `SettingsService` `JsonPref` map
/// keyed by `StorageService.activeUserScope()`, one entry per profile, written
/// under a single lock. There is no expiry — a capability that stops existing
/// is retired by a conclusive check, and ageing it out on a timer would just
/// reintroduce the flicker on a slower schedule.
library;

import 'dart:async';

import '../../services/settings_service.dart';
import '../../services/storage_service.dart';
import '../../utils/app_logger.dart';

class TvLiveTvCapabilityStore {
  TvLiveTvCapabilityStore._();

  static Future<void> _writeLock = Future<void>.value();

  /// `whenComplete`, not `then`: a failing write must still release the queue.
  static Future<T> _locked<T>(Future<T> Function() action) {
    final previous = _writeLock;
    final completer = Completer<void>();
    _writeLock = completer.future;
    return previous.then((_) => action()).whenComplete(completer.complete);
  }

  /// An empty scope (no active profile) is a namespace of its own, so a
  /// signed-out session never reads or writes a signed-in profile's entry.
  static Future<String> _scope() async {
    final storage = await StorageService.getInstance();
    return storage.activeUserScope() ?? '';
  }

  /// Whether this profile is known to have Live TV.
  ///
  /// Failure reads as "not known". A store that cannot be read must not be able
  /// to add a destination — an item that opens a page saying the source is
  /// unreachable is worse than an item that is simply absent.
  static Future<bool> read() async {
    try {
      final settings = await SettingsService.getInstance();
      return settings.read(SettingsService.tvLiveTvCapability)[await _scope()] ?? false;
    } catch (e) {
      appLogger.w('Failed to read Live TV capability', error: e);
      return false;
    }
  }

  /// Records that this profile has Live TV.
  static Future<void> remember() => _write(true);

  /// Records that this profile does not have Live TV.
  ///
  /// Only call this for a conclusive check. The whole point of the store is
  /// that an inconclusive negative never reaches here.
  static Future<void> forget() => _write(false);

  static Future<void> _write(bool value) {
    return _locked(() async {
      try {
        final settings = await SettingsService.getInstance();
        final scope = await _scope();
        final stored = settings.read(SettingsService.tvLiveTvCapability);
        if (stored[scope] == value) return;
        await settings.write(SettingsService.tvLiveTvCapability, {...stored, scope: value});
      } catch (e) {
        appLogger.w('Failed to store Live TV capability', error: e);
      }
    });
  }

  /// Drops [profileScope]'s entry when a profile is deleted, for the same
  /// reason `PreferredServerStore.clearForProfileScope` exists (hoofdstuk 22):
  /// what a profile's servers offer goes with the profile.
  static Future<void> clearForProfileScope(String profileScope) {
    return _locked(() async {
      try {
        final settings = await SettingsService.getInstance();
        final stored = settings.read(SettingsService.tvLiveTvCapability);
        if (!stored.containsKey(profileScope)) return;
        await settings.write(SettingsService.tvLiveTvCapability, {...stored}..remove(profileScope));
      } catch (e) {
        appLogger.w('Failed to clear Live TV capability for profile', error: e);
      }
    });
  }
}

/// Whether the Live TV destination should be in the bar, and what should be
/// stored afterwards.
///
/// Split out as a pure function because it is the actual product rule and it
/// has four cases that are easy to get subtly wrong in a widget. [remembered]
/// is what the store holds, [available] the live poll, [conclusive] whether
/// that poll could see the whole profile.
({bool visible, bool? store}) resolveLiveTvCapability({
  required bool remembered,
  required bool available,
  required bool conclusive,
}) {
  if (available) return (visible: true, store: remembered ? null : true);
  // Nothing found. Only a check that saw every expected server may retire a
  // remembered capability; otherwise the item stays exactly where it was.
  if (conclusive) return (visible: false, store: remembered ? false : null);
  return (visible: remembered, store: null);
}
