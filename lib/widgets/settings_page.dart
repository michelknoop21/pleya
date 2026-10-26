import 'package:flutter/material.dart';

import 'focused_scroll_scaffold.dart';
import 'settings/settings_studio_header.dart';
import 'settings_section.dart';

/// Standard scaffold for settings pages made of ordinary list rows.
class SettingsPage extends StatelessWidget {
  final Widget title;
  final List<Widget>? children;
  final List<Widget>? slivers;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? padding;
  final bool pinned;
  final bool automaticallyImplyLeading;
  final VoidCallback? onBackPressed;

  /// A-24b Studio rows inside Instellingen off TV: the rows leave their
  /// explanation off screen (VoiceOver reads it as the hint), as every page of
  /// the series draws them. False keeps the lines on a page that needs them.
  final bool hideDescriptions;

  const SettingsPage({
    super.key,
    required this.title,
    required List<Widget> this.children,
    this.actions,
    this.padding,
    this.pinned = true,
    this.automaticallyImplyLeading = true,
    this.onBackPressed,
    this.hideDescriptions = true,
  }) : slivers = null;

  const SettingsPage.slivers({
    super.key,
    required this.title,
    required List<Widget> this.slivers,
    this.actions,
    this.pinned = true,
    this.automaticallyImplyLeading = true,
    this.onBackPressed,
    this.hideDescriptions = true,
  }) : children = null,
       padding = null;

  @override
  Widget build(BuildContext context) {
    // A-24b on TV: the page's rows as a category of Instellingen, without a
    // bar or a scroll view of their own.
    if (SettingsInlineScope.isInline(context) && children != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _grouped(widthLimit: false));
    }
    final pageSlivers = slivers ?? [_buildListSliver()];
    final page = TvSettingsDensity(
      child: FocusedScrollScaffold(
        title: title,
        actions: actions,
        pinned: pinned,
        automaticallyImplyLeading: automaticallyImplyLeading,
        onBackPressed: onBackPressed,
        header: _studioHeader(context),
        slivers: pageSlivers,
      ),
    );
    // A-24b: a settings subpage in the Studio series draws its rows without
    // an icon (series `ios/02`-`14`, `tvos/01`-`12`); only the main page off
    // TV keeps line icons.
    if (!SettingsStudioTheme.isActive(context)) return page;
    return SettingsIconStyleScope(style: SettingsIconStyle.none, hideDescriptions: hideDescriptions, child: page);
  }

  /// A-24: on an iPhone every settings page opens on the Studio header, built
  /// from the page title ([settingsStudioHeaderApplies]). Elsewhere the plain
  /// bar stays, and so does a title that is not a plain [Text], rather than
  /// guessing at its string.
  Widget? _studioHeader(BuildContext context) {
    if (!settingsStudioHeaderApplies(context)) return null;
    final label = switch (title) {
      Text(:final data?) => data,
      _ => null,
    };
    return label == null ? null : SettingsWidthLimit(child: SettingsStudioHeader(title: label));
  }

  Widget _buildListSliver() {
    final list = SliverList(delegate: SliverChildListDelegate(_grouped()));
    final pagePadding = padding;
    if (pagePadding == null) return list;
    return SliverPadding(padding: pagePadding, sliver: list);
  }

  /// Turns the flat row list into grouped cards: every [SettingsSectionHeader]
  /// starts a new group and the rows after it become that card's contents.
  /// Pages keep passing a plain list, so no call site changes.
  List<Widget> _grouped({bool widthLimit = true}) {
    final out = <Widget>[];
    String? title;
    var rows = <Widget>[];

    void flush() {
      if (rows.isEmpty && title == null) return;
      out.add(SettingsGroup(title: title, children: rows));
      title = null;
      rows = <Widget>[];
    }

    for (final child in children!) {
      if (child is SettingsSectionHeader) {
        flush();
        title = child.title;
      } else if (child is SettingsStandaloneBlock) {
        // Between the cards (a footnote, a preview), not a row inside one.
        flush();
        out.add(child);
      } else {
        rows.add(child);
      }
    }
    flush();
    if (!widthLimit) return out;
    return out.map((w) => SettingsWidthLimit(child: w)).toList(growable: false);
  }
}

/// A-24b (Apple TV, series `tvos/01`-`12`): marks a settings page mounted as
/// the body of a category on the TV Instellingen page, where the series draws
/// its rows inline. Under it a [SettingsPage] builds only its grouped rows, so
/// the page keeps one definition of its rows, conditions and actions whether
/// it is opened on its own or shown in place.
class SettingsInlineScope extends InheritedWidget {
  const SettingsInlineScope({super.key, required super.child});

  static bool isInline(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsInlineScope>() != null;

  @override
  bool updateShouldNotify(SettingsInlineScope oldWidget) => false;
}
