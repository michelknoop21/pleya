import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../screens/settings/settings_utils.dart';
import '../../services/settings_service.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/platform_detector.dart';
import '../app_icon.dart';
import '../clickable_cursor.dart';
import '../settings_section.dart';
import 'setting_value_label.dart';

/// The two settings rows that show a current value and open a dialog to
/// change it, bound to a [Pref] like the rest of `setting_tile.dart` (which
/// re-exports this file, so call sites import nothing new).

/// Title, subtitle and trailing slot of a row that shows a current value.
///
/// A-24 (Apple TV+ Studio on iOS), off TV, per [settingValuePlacement]: the
/// value stands right-aligned before the chevron on a row without
/// [description]; on a row with one it ends the title line, so the
/// description keeps the full text width under it; and a value that would be
/// cut there falls back to [valueLine] under the title, whole, as before.
/// On TV nothing changes: [valueLine] stays the value line under the title,
/// as `TvSettingsDensity` sizes it.
({Widget title, Widget? subtitle, Widget trailing}) _valueRowParts(
  BuildContext context, {
  required String title,
  required String valueLine,
  required String value,
  String? description,
}) {
  final chevron = AppIcon(Symbols.chevron_right_rounded, fill: 1, size: 20, color: tokens(context).textMuted);
  if (PlatformDetector.isTV()) return (title: Text(title), subtitle: Text(valueLine), trailing: chevron);
  // A-24b Studio rows leave the explanation off screen (read as the hint).
  final shown = settingsRowDescription(context, description);
  return switch (settingValuePlacement(context, title: title, value: value, hasDescription: shown != null)) {
    SettingValuePlacement.trailing => (
      title: Text(title),
      subtitle: null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SettingValueLabel(value, title: title),
          const SizedBox(width: 8),
          chevron,
        ],
      ),
    ),
    SettingValuePlacement.titleLine => (
      title: SettingTitleWithValue(title: title, value: value),
      subtitle: Text(shown!),
      trailing: chevron,
    ),
    // The value line joins the description; with that hidden, the value alone.
    SettingValuePlacement.subtitle => (
      title: Text(title),
      subtitle: Text(shown == null && description != null ? value : valueLine),
      trailing: chevron,
    ),
  };
}

/// ListTile that opens [showNumericInputDialog] and writes back.
class SettingNumberTile extends StatelessWidget {
  final Pref<int> pref;
  final IconData icon;
  final String title;

  /// The value line on TV, and the value off TV unless [valueBuilder] is set.
  final String Function(int) subtitleBuilder;

  /// The short value off TV, when [subtitleBuilder] says more than the value.
  final String Function(int)? valueBuilder;

  /// Explanatory text under the title off TV. Null means no subtitle there.
  final String? Function(int)? descriptionBuilder;
  final String labelText;
  final String suffixText;
  final int min;
  final int max;
  final FutureOr<void> Function(int)? onAfterWrite;

  const SettingNumberTile({
    super.key,
    required this.pref,
    required this.icon,
    required this.title,
    required this.subtitleBuilder,
    this.valueBuilder,
    this.descriptionBuilder,
    required this.labelText,
    required this.suffixText,
    required this.min,
    required this.max,
    this.onAfterWrite,
  });

  @override
  Widget build(BuildContext context) {
    final svc = SettingsService.instance;
    return ValueListenableBuilder<int>(
      valueListenable: svc.listenable(pref),
      builder: (_, value, _) {
        void activate() => showNumericInputDialog(
          context: context,
          title: title,
          labelText: labelText,
          suffixText: suffixText,
          min: min,
          max: max,
          currentValue: value,
          onSave: (v) async {
            await svc.write(pref, v);
            final callback = onAfterWrite;
            if (callback != null) await callback(v);
          },
        );

        final line = subtitleBuilder(value);
        final description = descriptionBuilder?.call(value);
        final parts = _valueRowParts(
          context,
          title: title,
          valueLine: line,
          value: valueBuilder?.call(value) ?? line,
          description: description,
        );
        return SettingRowFocus(
          onSelect: activate,
          // The same `setting.<key>` id a switch row registers under.
          automationInstance: 'setting.${pref.key}',
          automationState: () => {'value': '$value'},
          child: ClickableCursor(
            child: settingsRowWithHint(
              settingsRowHint(context, description),
              ListTile(
                leading: settingsRowLeading(context, icon),
                contentPadding: settingRowPadding(),
                title: parts.title,
                subtitle: parts.subtitle,
                trailing: parts.trailing,
                onTap: activate,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// ListTile that opens [showSelectionDialog] and writes the chosen value.
/// [encode]/[decode] map between the [Pref<S>] storage type and the option
/// type [T] (e.g. enum-stored-as-string preset → [TranscodeQualityPreset]).
class SettingSelectionTile<T, S> extends StatelessWidget {
  final Pref<S> pref;
  final IconData icon;
  final String title;

  /// The value line on TV, and the value off TV unless [valueBuilder] is set.
  final String Function(T) subtitleBuilder;

  /// The short value off TV, when [subtitleBuilder] says more than the value.
  final String Function(T)? valueBuilder;

  /// Explanatory text under the title off TV. Null means no subtitle there.
  final String? Function(T)? descriptionBuilder;
  final List<DialogOption<T>> options;
  final T Function(S) decode;
  final S Function(T) encode;
  final FutureOr<void> Function(T)? onAfterWrite;

  const SettingSelectionTile({
    super.key,
    required this.pref,
    required this.icon,
    required this.title,
    required this.subtitleBuilder,
    this.valueBuilder,
    this.descriptionBuilder,
    required this.options,
    required this.decode,
    required this.encode,
    this.onAfterWrite,
  });

  @override
  Widget build(BuildContext context) {
    final svc = SettingsService.instance;
    return ValueListenableBuilder<S>(
      valueListenable: svc.listenable(pref),
      builder: (_, raw, _) {
        final value = decode(raw);
        Future<void> activate() async {
          final picked = await showSelectionDialog<T>(
            context: context,
            title: title,
            options: options,
            currentValue: value,
          );
          if (picked == null) return;
          await svc.write(pref, encode(picked));
          final callback = onAfterWrite;
          if (callback != null) await callback(picked);
        }

        final line = subtitleBuilder(value);
        final description = descriptionBuilder?.call(value);
        final parts = _valueRowParts(
          context,
          title: title,
          valueLine: line,
          value: valueBuilder?.call(value) ?? line,
          description: description,
        );
        return SettingRowFocus(
          onSelect: activate,
          // The same `setting.<key>` id a switch row registers under.
          automationInstance: 'setting.${pref.key}',
          automationState: () => {'value': '$value'},
          child: ClickableCursor(
            child: settingsRowWithHint(
              settingsRowHint(context, description),
              ListTile(
                leading: settingsRowLeading(context, icon),
                contentPadding: settingRowPadding(),
                title: parts.title,
                subtitle: parts.subtitle,
                trailing: parts.trailing,
                onTap: activate,
              ),
            ),
          ),
        );
      },
    );
  }
}
