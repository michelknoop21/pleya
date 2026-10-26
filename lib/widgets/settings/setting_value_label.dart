import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/mono_tokens.dart';
import '../settings_section.dart' show kSettingsMaxWidth, kSettingsStudioValueSize;
import 'settings_icon_badge.dart';
import 'settings_studio_style.dart';
import 'settings_studio_theme.dart';

/// Where a settings row off TV shows its current value (A-24, Apple TV+
/// Studio on iOS).
enum SettingValuePlacement {
  /// Right-aligned before the chevron: a row without a description.
  trailing,

  /// At the end of the title line, so a description under the title keeps
  /// the full width of the text column instead of being squeezed beside it.
  titleLine,

  /// On the line under the title, as before A-24: the value does not fit
  /// beside the title, and cutting it would hide what the row says.
  subtitle,
}

/// Where [value] goes on a row titled [title]. The title wins, as in iOS
/// Settings: the value only gets what the title leaves on its line, never
/// more than [kSettingsValueMaxFraction] of the card. A value that would be
/// ellipsized there moves to the subtitle, whole.
///
/// Computed from the screen width rather than a `LayoutBuilder`: a `ListTile`
/// lays out its slots with loose constraints that say nothing about the row,
/// and asks for intrinsics a `LayoutBuilder` cannot answer.
SettingValuePlacement settingValuePlacement(
  BuildContext context, {
  required String title,
  required String value,
  required bool hasDescription,
}) {
  final placement = hasDescription ? SettingValuePlacement.titleLine : SettingValuePlacement.trailing;
  final room = _valueRoom(context, title, placement);
  final width = _textWidth(context, value, _valueStyle(context));
  return width <= room ? placement : SettingValuePlacement.subtitle;
}

/// The current value of a settings row, in the muted ink, one line. Only
/// placed where [settingValuePlacement] said it fits; the bound here is the
/// same room, so a rounding difference ellipsizes instead of overflowing.
class SettingValueLabel extends StatelessWidget {
  const SettingValueLabel(
    this.value, {
    super.key,
    required this.title,
    this.placement = SettingValuePlacement.trailing,
  });

  final String value;

  /// The row's title, which keeps priority over the value.
  final String title;

  /// [SettingValuePlacement.trailing] or [SettingValuePlacement.titleLine].
  final SettingValuePlacement placement;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: math.max(0, _valueRoom(context, title, placement))),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        style: _valueStyle(context),
      ),
    );
  }
}

/// A row title with the value at the end of its line
/// ([SettingValuePlacement.titleLine]). The title takes the rest of the line
/// and wraps there if it must; the value keeps its natural width.
class SettingTitleWithValue extends StatelessWidget {
  const SettingTitleWithValue({super.key, required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: Text(title)),
        const SizedBox(width: _kTitleValueGap),
        SettingValueLabel(value, title: title, placement: SettingValuePlacement.titleLine),
      ],
    );
  }
}

TextStyle? _valueStyle(BuildContext context) => Theme.of(context).textTheme.bodyMedium?.copyWith(
  color: tokens(context).textMuted,
  // A-24b: the Studio rows' smaller value inside Instellingen.
  fontSize: SettingsStudioTheme.isActive(context) ? kSettingsStudioValueSize : null,
);

double _textWidth(BuildContext context, String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// The width a value may take on its row: what the title leaves, capped at
/// [kSettingsValueMaxFraction] of the card. The card is the settings column
/// less SettingsGroup's 16 pt margins; before the text come the row inset,
/// the icon slot and the title gap ([settingsRowTextInset]).
double _valueRoom(BuildContext context, String title, SettingValuePlacement placement) {
  final card = math.min(MediaQuery.sizeOf(context).width, kSettingsMaxWidth) - 32;
  final chrome = switch (placement) {
    SettingValuePlacement.titleLine => _kChevronChrome + _kTitleValueGap,
    _ => _kChevronChrome + _kTrailingValueGap,
  };
  final text = card - settingsRowTextInset(context) - chrome;
  final tileTheme = ListTileTheme.of(context);
  final base = tileTheme.titleTextStyle ?? Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
  final titleStyle = base.copyWith(fontSize: (tileTheme.dense ?? false) ? 13 : null);
  // One point of slack: text measured at exactly its box width wraps.
  final titleWidth = _textWidth(context, title, titleStyle) + 1;
  return math.min(text - titleWidth, card * kSettingsValueMaxFraction);
}

/// After the text column of a value row: the tile's title gap, the 20 pt
/// chevron and the 16 pt row inset.
const double _kChevronChrome = 16 + 20 + 16;

/// Between a trailing value and its chevron.
const double _kTrailingValueGap = 8;

/// Between the title and the value on a title line.
const double _kTitleValueGap = 12;
