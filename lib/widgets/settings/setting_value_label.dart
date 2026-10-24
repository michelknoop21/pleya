import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/mono_tokens.dart';
import '../settings_rows.dart';
import '../settings_section.dart' show kSettingsMaxWidth;
import 'settings_studio_style.dart';

/// The current value of a settings row, right-aligned before its chevron
/// (A-24, Apple TV+ Studio on iOS).
///
/// One line in the muted ink, ellipsized, because a value is often user data
/// (a server name, a language) and a `ListTile`'s trailing slot otherwise takes
/// whatever width it asks for and pushes the title off a phone.
///
/// The title wins, as in iOS Settings: given the row's [title], the value only
/// gets what the title leaves, never more than [kSettingsValueMaxFraction] of
/// the card and never less than [_kMinShareOfText] of the room both share. On a
/// 320 pt phone that keeps a one-word title on one line instead of breaking it
/// letter by letter.
///
/// The bound is computed from the screen width rather than a `LayoutBuilder`:
/// a `ListTile` lays out its trailing slot with loose constraints that say
/// nothing about the row.
class SettingValueLabel extends StatelessWidget {
  const SettingValueLabel(this.value, {super.key, this.title, this.besideDescription = false});

  final String value;

  /// The row's title, when the row has one beside the value.
  final String? title;

  /// The row has explanatory text under its title. That text shares the
  /// column with the title, so the value takes at most
  /// [_kDescribedRowValueShare] of the room and the description does not
  /// stack into five short lines.
  final bool besideDescription;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: _maxWidth(context)),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: tokens(context).textMuted),
      ),
    );
  }

  double _maxWidth(BuildContext context) {
    // The card: the settings column less SettingsGroup's 16 pt margins.
    final card = math.min(MediaQuery.sizeOf(context).width, kSettingsMaxWidth) - 32;
    final cap = card * kSettingsValueMaxFraction;
    final title = this.title;
    if (title == null) return cap;
    // Row inset, badge and title gap before the title; the gaps, chevron and
    // row inset after the value.
    final text = card - kSettingsSeparatorIndent - _kTrailingChrome;
    if (text <= 0) return cap;
    final tileTheme = ListTileTheme.of(context);
    final base = tileTheme.titleTextStyle ?? Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
    final painter = TextPainter(
      text: TextSpan(
        text: title,
        style: base.copyWith(fontSize: (tileTheme.dense ?? false) ? 13 : null),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final titleWidth = painter.width;
    painter.dispose();
    final floor = text * _kMinShareOfText;
    final ceiling = besideDescription ? math.min(cap, text * _kDescribedRowValueShare) : cap;
    return math.max(floor, math.min(text - titleWidth, ceiling));
  }
}

/// What a value row draws after the value: the title gap, the 8 pt gap, the
/// 20 pt chevron and the 16 pt row inset.
const double _kTrailingChrome = 16 + 8 + 20 + 16;

/// The least share of the title-and-value room a value keeps.
const double _kMinShareOfText = 0.25;

/// The most a value takes of that room on a row with a description.
const double _kDescribedRowValueShare = 0.5;
