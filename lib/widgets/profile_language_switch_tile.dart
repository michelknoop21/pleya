import 'package:flutter/material.dart';

import '../media/pleya_profile_language_preferences.dart';
import '../services/pleya_profile_language_preference_store.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import 'setting_tile.dart';

/// A settings switch backed by the Pleya profile's language preference rather
/// than by a device-wide `BoolPref`.
///
/// [SettingSwitchTile] binds straight to a [Pref], which is exactly what these
/// two rows must not do any more: "Onthoud keuzes per serie" and "Spiegel naar
/// Plex" belong to the profile now (DEC-096 lid 5), so two Plex Home users on
/// one Apple TV keep their own answer. The value still comes off a
/// `SettingsService` listenable — the whole map is one pref — so a change made
/// on another device through iCloud repaints this row without a reload.
class ProfileLanguageSwitchTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool enabled;
  final FocusNode? focusNode;

  /// Reads the bool this row shows out of the profile's preference.
  final bool Function(PleyaProfileLanguagePreferences) selector;

  /// Folds the new value back into the profile's preference.
  final PleyaProfileLanguagePreferences Function(PleyaProfileLanguagePreferences current, bool value) apply;

  const ProfileLanguageSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    required this.selector,
    required this.apply,
    this.subtitle,
    this.enabled = true,
    this.focusNode,
  });

  @override
  State<ProfileLanguageSwitchTile> createState() => _ProfileLanguageSwitchTileState();
}

class _ProfileLanguageSwitchTileState extends State<ProfileLanguageSwitchTile> {
  /// Resolved once: the scope only changes on a profile switch, which rebuilds
  /// the settings tree anyway. Null until the first resolve, and the row shows
  /// the all-default preference in the meantime rather than an empty gap.
  String? _scope;

  @override
  void initState() {
    super.initState();
    StorageService.getInstance().then((storage) {
      if (mounted) setState(() => _scope = storage.activeUserScope() ?? '');
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, PleyaProfileLanguagePreferences>>(
      valueListenable: SettingsService.instance.listenable(SettingsService.pleyaProfileLanguagePreferences),
      builder: (_, stored, _) {
        final scope = _scope;
        final preferences = (scope == null ? null : stored[scope]) ?? const PleyaProfileLanguagePreferences();
        return SettingSwitchRow(
          icon: widget.icon,
          title: widget.title,
          subtitle: widget.subtitle,
          value: widget.selector(preferences),
          focusNode: widget.focusNode,
          onChanged: widget.enabled
              ? (value) => PleyaProfileLanguagePreferenceStore.update((current) => widget.apply(current, value))
              : null,
        );
      },
    );
  }
}
