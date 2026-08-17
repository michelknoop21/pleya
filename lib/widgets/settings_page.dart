import 'package:flutter/material.dart';

import 'focused_scroll_scaffold.dart';
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

  const SettingsPage({
    super.key,
    required this.title,
    required List<Widget> this.children,
    this.actions,
    this.padding,
    this.pinned = true,
    this.automaticallyImplyLeading = true,
    this.onBackPressed,
  }) : slivers = null;

  const SettingsPage.slivers({
    super.key,
    required this.title,
    required List<Widget> this.slivers,
    this.actions,
    this.pinned = true,
    this.automaticallyImplyLeading = true,
    this.onBackPressed,
  }) : children = null,
       padding = null;

  @override
  Widget build(BuildContext context) {
    final pageSlivers = slivers ?? [_buildListSliver()];
    return FocusedScrollScaffold(
      title: title,
      actions: actions,
      pinned: pinned,
      automaticallyImplyLeading: automaticallyImplyLeading,
      onBackPressed: onBackPressed,
      slivers: pageSlivers,
    );
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
  List<Widget> _grouped() {
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
      } else {
        rows.add(child);
      }
    }
    flush();
    return out.map((w) => SettingsWidthLimit(child: w)).toList(growable: false);
  }
}
