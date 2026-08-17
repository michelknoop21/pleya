import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../i18n/strings.g.dart';
import '../media/watchlist_entry.dart';
import 'app_icon.dart';
import 'bottom_sheet_header.dart';
import 'focusable_list_tile.dart';
import 'overlay_sheet.dart';

/// Ask which order the kijklijst should be in.
///
/// A sheet rather than a second row of chips: three options are worth one
/// control, not a permanent strip that pushes the first row of posters further
/// down on every screen. `showAdaptive` gives the sheet on touch and the
/// centred dialog on desktop and TV, and closing it is the platform's own
/// gesture, so Back and Menu dismiss the sheet without touching the screen
/// behind it.
///
/// The sheet returns a choice and does nothing else. Sorting runs over the
/// entries already loaded, so there is no request to fire and nothing to wait
/// for.
Future<WatchlistSort?> showWatchlistSortSheet(BuildContext context, {required WatchlistSort current}) {
  return OverlaySheetController.showAdaptive<WatchlistSort>(
    context,
    builder: (_) => WatchlistSortSheet(current: current),
  );
}

class WatchlistSortSheet extends StatelessWidget {
  const WatchlistSortSheet({super.key, required this.current});

  final WatchlistSort current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Reuses the libraries wording. Sorting is the same act in both
          // places, and a second string for it would be a second thing to keep
          // translated for no difference the user can see.
          BottomSheetHeader(title: t.libraries.sortBy),
          for (final option in WatchlistSort.values)
            FocusableListTile(
              autofocus: option == current,
              selected: option == current,
              leading: AppIcon(
                option == current ? Symbols.radio_button_checked_rounded : Symbols.radio_button_unchecked_rounded,
                fill: 1,
              ),
              title: Text(watchlistSortLabel(option)),
              onTap: () => Navigator.of(context).pop(option),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

String watchlistSortLabel(WatchlistSort sort) => switch (sort) {
  WatchlistSort.recentlyAdded => t.watchlist.sortRecentlyAdded,
  WatchlistSort.title => t.watchlist.sortTitle,
  WatchlistSort.year => t.watchlist.sortYear,
};
