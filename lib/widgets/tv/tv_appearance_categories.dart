import 'package:flutter/material.dart';

import '../../automation/automation_ids.dart';
import '../settings_section.dart';
import 'tv_settings_categories.dart';

export 'tv_settings_categories.dart'
    show kTvAppearanceColumnsTopPt, kTvAppearanceLabelGapPt, kTvCategoryGapPt, kTvCategoryPillInsetPt;

/// TV presentation for the existing Appearance rows. The original widgets
/// remain the sole owners of their preferences, callbacks and platform gates.
///
/// The flat list is split at each [SettingsSectionHeader]; every header
/// becomes a category on [TvSettingsCategories], the layout the main settings
/// page shares.
class TvAppearanceCategories extends StatelessWidget {
  const TvAppearanceCategories({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final sections = <({String title, List<Widget> rows})>[];
    String? currentTitle;
    var currentRows = <Widget>[];
    for (final child in children) {
      if (child is SettingsSectionHeader) {
        if (currentTitle != null) sections.add((title: currentTitle, rows: currentRows));
        currentTitle = child.title;
        currentRows = [];
      } else {
        currentRows.add(child);
      }
    }
    if (currentTitle != null) sections.add((title: currentTitle, rows: currentRows));

    return TvSettingsCategories(
      title: title,
      automationInstance: 'appearance',
      categoryAutomationId: AutomationIds.settingsAppearanceCategory,
      categories: [
        for (final (index, section) in sections.indexed)
          TvSettingsCategory(
            // A section title can repeat in principle; the index keeps ids apart.
            id: '$index:${section.title}',
            title: section.title,
            body: SettingsGroup(children: section.rows),
          ),
      ],
    );
  }
}
