import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../screens/settings/settings_utils.dart';
import '../services/settings_service.dart';
import '../theme/mono_tokens.dart';
import 'app_icon.dart';
import 'clickable_cursor.dart';
import 'settings_section.dart';

/// Reactive setting tiles bound to a [Pref] via [SettingsService.listenable].
/// Eliminates the field-mirror + setState + manual reload pattern that used to
/// surround every settings row.

class _TileBase {
  static SettingsService get _svc => SettingsService.instance;
}

/// SwitchListTile bound to a [Pref<bool>].
class SettingSwitchTile extends StatelessWidget {
  final Pref<bool> pref;
  final IconData icon;
  final String title;
  final String? subtitle;
  final FutureOr<void> Function(bool)? onAfterWrite;
  final bool enabled;
  final FocusNode? focusNode;

  const SettingSwitchTile({
    super.key,
    required this.pref,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onAfterWrite,
    this.enabled = true,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final svc = _TileBase._svc;
    return ValueListenableBuilder<bool>(
      valueListenable: svc.listenable(pref),
      builder: (_, value, _) => SettingRowFocus(
        enabled: enabled,
        focusNode: focusNode,
        onSelect: () => _write(svc, !value),
        child: ClickableCursor(
          enabled: enabled,
          child: SwitchListTile(
            contentPadding: kSettingRowPadding,
            secondary: SettingsIconBadge(icon),
            title: Text(title),
            subtitle: subtitle != null ? Text(subtitle!) : null,
            value: value,
            onChanged: enabled ? (v) => _write(svc, v) : null,
          ),
        ),
      ),
    );
  }

  Future<void> _write(SettingsService svc, bool value) async {
    await svc.write(pref, value);
    final callback = onAfterWrite;
    if (callback != null) await callback(value);
  }
}

/// A switch row that looks exactly like [SettingSwitchTile] but is driven by an
/// explicit value instead of a [Pref].
///
/// For state that deliberately does not live in preferences: the Tautulli
/// history policy belongs to the server's integration record, next to the
/// credential it authorises, so it survives a disconnect and cannot be flipped
/// by hand-editing a plain preference key.
class SettingSwitchRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool enabled;
  final FocusNode? focusNode;

  const SettingSwitchRow({
    super.key,
    required this.value,
    required this.onChanged,
    required this.icon,
    required this.title,
    this.subtitle,
    this.enabled = true,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final active = enabled && onChanged != null;
    return SettingRowFocus(
      enabled: active,
      focusNode: focusNode,
      onSelect: () => onChanged?.call(!value),
      child: ClickableCursor(
        enabled: active,
        child: SwitchListTile(
          contentPadding: kSettingRowPadding,
          secondary: SettingsIconBadge(icon),
          title: Text(title),
          subtitle: subtitle != null ? Text(subtitle!) : null,
          value: value,
          onChanged: active ? onChanged : null,
        ),
      ),
    );
  }
}

/// Standard settings row that navigates to another screen.
class SettingNavigationTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final WidgetBuilder? destinationBuilder;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final IconData trailingIcon;

  const SettingNavigationTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.destinationBuilder,
    this.onTap,
    this.focusNode,
    this.trailingIcon = Symbols.chevron_right_rounded,
  }) : assert(destinationBuilder != null || onTap != null);

  @override
  Widget build(BuildContext context) {
    void activate() {
      final handler = onTap;
      if (handler != null) {
        handler();
        return;
      }
      Navigator.push(context, MaterialPageRoute(builder: destinationBuilder!));
    }

    return SettingRowFocus(
      focusNode: focusNode,
      onSelect: activate,
      child: ClickableCursor(
        child: ListTile(
          contentPadding: kSettingRowPadding,
          leading: SettingsIconBadge(icon),
          title: Text(title),
          subtitle: subtitle != null ? Text(subtitle!) : null,
          trailing: AppIcon(trailingIcon, fill: 1, size: 20, color: tokens(context).textMuted),
          onTap: activate,
        ),
      ),
    );
  }
}

/// ListTile that opens [showNumericInputDialog] and writes back.
class SettingNumberTile extends StatelessWidget {
  final Pref<int> pref;
  final IconData icon;
  final String title;
  final String Function(int) subtitleBuilder;
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
    required this.labelText,
    required this.suffixText,
    required this.min,
    required this.max,
    this.onAfterWrite,
  });

  @override
  Widget build(BuildContext context) {
    final svc = _TileBase._svc;
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

        return SettingRowFocus(
          onSelect: activate,
          child: ClickableCursor(
            child: ListTile(
              leading: SettingsIconBadge(icon),
              contentPadding: kSettingRowPadding,
              title: Text(title),
              subtitle: Text(subtitleBuilder(value)),
              trailing: AppIcon(Symbols.chevron_right_rounded, fill: 1, size: 20, color: tokens(context).textMuted),
              onTap: activate,
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
  final String Function(T) subtitleBuilder;
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
    required this.options,
    required this.decode,
    required this.encode,
    this.onAfterWrite,
  });

  @override
  Widget build(BuildContext context) {
    final svc = _TileBase._svc;
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

        return SettingRowFocus(
          onSelect: activate,
          child: ClickableCursor(
            child: ListTile(
              leading: SettingsIconBadge(icon),
              contentPadding: kSettingRowPadding,
              title: Text(title),
              subtitle: Text(subtitleBuilder(value)),
              trailing: AppIcon(Symbols.chevron_right_rounded, fill: 1, size: 20, color: tokens(context).textMuted),
              onTap: activate,
            ),
          ),
        );
      },
    );
  }
}

/// ListTile that opens [showRegexInputDialog] for a [Pref<String>].
class SettingRegexTile extends StatelessWidget {
  final Pref<String> pref;
  final IconData icon;
  final String title;
  final String subtitle;
  final String defaultValue;
  final FutureOr<void> Function(String)? onAfterWrite;

  const SettingRegexTile({
    super.key,
    required this.pref,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.defaultValue,
    this.onAfterWrite,
  });

  @override
  Widget build(BuildContext context) {
    final svc = _TileBase._svc;
    return ValueListenableBuilder<String>(
      valueListenable: svc.listenable(pref),
      builder: (_, value, _) {
        void activate() => showRegexInputDialog(
          context: context,
          title: title,
          currentValue: value,
          defaultValue: defaultValue,
          onSave: (v) async {
            await svc.write(pref, v);
            final callback = onAfterWrite;
            if (callback != null) await callback(v);
          },
        );

        return SettingRowFocus(
          onSelect: activate,
          child: ClickableCursor(
            child: ListTile(
              leading: SettingsIconBadge(icon),
              contentPadding: kSettingRowPadding,
              title: Text(title),
              subtitle: Text(subtitle),
              trailing: AppIcon(Symbols.chevron_right_rounded, fill: 1, size: 20, color: tokens(context).textMuted),
              onTap: activate,
            ),
          ),
        );
      },
    );
  }
}

/// SegmentedSetting bound to a [Pref<T>]. Use [encode]/[decode] when the
/// stored type differs from the segment type (e.g. bool stored, segments
/// over enum).
class SettingSegmentedTile<T, S> extends StatelessWidget {
  final Pref<S> pref;
  final IconData icon;
  final String title;
  final List<ButtonSegment<T>> segments;
  final T Function(S) decode;
  final S Function(T) encode;
  final FutureOr<void> Function(T)? onAfterWrite;

  const SettingSegmentedTile({
    super.key,
    required this.pref,
    required this.icon,
    required this.title,
    required this.segments,
    required this.decode,
    required this.encode,
    this.onAfterWrite,
  });

  @override
  Widget build(BuildContext context) {
    final svc = _TileBase._svc;
    return ValueListenableBuilder<S>(
      valueListenable: svc.listenable(pref),
      builder: (_, raw, _) {
        final value = decode(raw);
        return SegmentedSetting<T>(
          icon: icon,
          title: title,
          segments: segments,
          selected: value,
          onChanged: (v) async {
            await svc.write(pref, encode(v));
            final callback = onAfterWrite;
            if (callback != null) await callback(v);
          },
        );
      },
    );
  }
}

/// ListTile that opens [showColorInputDialog] for a hex-string [Pref].
/// Trailing widget is a small color swatch.
class SettingColorTile extends StatelessWidget {
  final Pref<String> pref;
  final IconData icon;
  final String title;
  final String? subtitle;
  final FutureOr<void> Function(String hex)? onAfterWrite;

  const SettingColorTile({
    super.key,
    required this.pref,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onAfterWrite,
  });

  @override
  Widget build(BuildContext context) {
    final svc = _TileBase._svc;
    return ValueListenableBuilder<String>(
      valueListenable: svc.listenable(pref),
      builder: (_, hex, _) {
        void activate() => showColorInputDialog(
          context: context,
          title: title,
          currentHex: hex,
          onSave: (v) async {
            await svc.write(pref, v);
            final callback = onAfterWrite;
            if (callback != null) await callback(v);
          },
        );

        return SettingRowFocus(
          onSelect: activate,
          child: ClickableCursor(
            child: ListTile(
              leading: SettingsIconBadge(icon),
              contentPadding: kSettingRowPadding,
              title: Text(title),
              subtitle: subtitle != null ? Text(subtitle!) : null,
              trailing: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: hexToColor(hex),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
              ),
              onTap: activate,
            ),
          ),
        );
      },
    );
  }
}
