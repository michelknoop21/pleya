/// The two pages of Filteren op in the iPhone library look (Michel, 30 October
/// 2026, references e2b9c485 and 20e126cc): the list of quick choices and
/// categories, and the values of one category. Presentation only: the state and
/// what a choice writes stay in `FiltersBottomSheet`.
library;

import 'package:flutter/material.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../focus/focusable_button.dart';
import '../../i18n/strings.g.dart';
import '../../media/library_menu_definition.dart';
import '../../media/media_filter.dart';
import '../../widgets/mobile/library_phone_look.dart';
import '../../widgets/mobile/library_phone_sheet.dart';
import '../../widgets/skeletons.dart';

/// Alles and the quick choices, the rule, then the categories. Nothing here
/// decides what exists: [filters] is what the server lists, so an option no
/// backend can run has no row. A library without quick choices has no Alles
/// either, because there is nothing for it to be the opposite of.
class LibraryPhoneFilterMenu extends StatelessWidget {
  const LibraryPhoneFilterMenu({
    super.key,
    required this.filters,
    required this.selected,
    required this.displayValue,
    required this.onAll,
    required this.onToggle,
    required this.onCategory,
    required this.onClear,
  });

  final List<MediaFilter> filters;
  final Map<String, String> selected;
  final String? Function(MediaFilter filter) displayValue;
  final VoidCallback onAll;
  final ValueChanged<MediaFilter> onToggle;
  final ValueChanged<MediaFilter> onCategory;

  /// Clears everything, the categories too. Null while nothing is set.
  final VoidCallback? onClear;

  bool _isOn(MediaFilter filter) => selected[filter.filter] == '1';

  @override
  Widget build(BuildContext context) {
    final quick = [
      for (final filter in filters)
        if (filter.filterType == 'boolean') filter,
    ];
    final categories = [
      for (final filter in filters)
        if (filter.filterType != 'boolean') filter,
    ];
    final clear = onClear;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AutomationNode(
          id: AutomationIds.sheetLibraryFilter,
          role: 'sheet',
          child: LibraryPhoneSheetHeading(
            title: t.libraries.filterBy,
            action: clear == null
                ? null
                : FocusableButton(
                    onPressed: clear,
                    child: TextButton(onPressed: clear, child: Text(t.common.clear)),
                  ),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: LibraryPhoneMetrics.sheetListPaddingOf(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (quick.isNotEmpty)
                  LibraryPhoneSheetRow(
                    title: libraryQuickFilterLabel(LibraryQuickFilter.all),
                    selected: !quick.any(_isOn),
                    onTap: onAll,
                  ),
                for (final filter in quick)
                  LibraryPhoneSheetRow(title: filter.title, selected: _isOn(filter), onTap: () => onToggle(filter)),
                if (quick.isNotEmpty && categories.isNotEmpty) const LibraryPhoneSheetDivider(),
                for (final filter in categories)
                  LibraryPhoneSheetRow(
                    title: filter.title,
                    selected: false,
                    value: displayValue(filter),
                    onTap: () => onCategory(filter),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The values of one category, one level per list: back leads to the menu.
class LibraryPhoneFilterValues extends StatelessWidget {
  const LibraryPhoneFilterValues({
    super.key,
    required this.filter,
    required this.values,
    required this.isLoading,
    required this.selectedValue,
    required this.valueOf,
    required this.scrollController,
    required this.firstRowKey,
    required this.onBack,
    required this.onChosen,
  });

  static const int _skeletonRows = 6;

  final MediaFilter filter;
  final List<MediaFilterValue> values;
  final bool isLoading;
  final String? selectedValue;
  final String Function(MediaFilterValue value) valueOf;
  final ScrollController scrollController;
  final Key firstRowKey;
  final VoidCallback onBack;

  /// Null is the first row: this category not set.
  final ValueChanged<MediaFilterValue?> onChosen;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LibraryPhoneSheetHeading(title: filter.title, onBack: onBack),
        Flexible(
          child: isLoading
              ? ListView.builder(
                  primary: false,
                  shrinkWrap: true,
                  padding: LibraryPhoneMetrics.sheetListPaddingOf(context),
                  itemCount: _skeletonRows,
                  itemBuilder: (_, _) => const SkeletonListTile(),
                )
              : ListView.builder(
                  controller: scrollController,
                  primary: false,
                  shrinkWrap: true,
                  padding: LibraryPhoneMetrics.sheetListPaddingOf(context),
                  itemCount: values.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return LibraryPhoneSheetRow(
                        key: firstRowKey,
                        title: t.libraries.all,
                        selected: selectedValue == null,
                        onTap: () => onChosen(null),
                      );
                    }
                    final value = values[index - 1];
                    return LibraryPhoneSheetRow(
                      title: value.title,
                      selected: selectedValue == valueOf(value),
                      onTap: () => onChosen(value),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
