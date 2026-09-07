/// The titles behind "Recent gezocht" (mockup 36 A).
///
/// The search screen already keeps a history, but of *queries*: fifteen strings
/// a viewer typed. Mockup 36 A draws something else — the titles they actually
/// opened — and on a 10-foot surface that is the useful half. A row of past
/// query strings asks a viewer to remember what "dune" got them; a row of
/// posters is the thing itself, one press away.
///
/// Both stay. The chips are what desktop and mobile show, where re-running a
/// query is cheap and the keyboard is right there; this is what TV shows.
///
/// Items are stored whole rather than as an id per server, because the row has
/// to draw before any server has answered — the point of it is that Zoeken is
/// not empty when you arrive. A stored item can be stale (renamed, removed,
/// a server that is now offline); activating it goes through the same path a
/// fresh result does, so a title that is gone fails there the way any other
/// stale reference does, rather than being silently dropped from the row.
library;

import 'dart:convert';

import '../media/media_item.dart';
import '../services/settings_service.dart';
import '../utils/app_logger.dart';

/// How many titles the row keeps.
///
/// Six is what fits on one screen at catalog width without scrolling, which is
/// what mockup 36 A draws. A row you have to scroll to see the end of is not a
/// shortcut any more.
const int searchRecentsLimit = 6;

/// Reads the row, oldest entries dropped and unreadable ones skipped.
///
/// A decode failure is not fatal here: the pref survives app versions, and one
/// entry written by an older model should cost that entry rather than the whole
/// row.
List<MediaItem> readSearchRecents() {
  final raw = SettingsService.instance.read(SettingsService.searchRecentItems);
  final items = <MediaItem>[];
  for (final entry in raw) {
    try {
      final decoded = jsonDecode(entry);
      if (decoded is Map<String, dynamic>) items.add(MediaItem.fromJson(decoded));
    } catch (error) {
      appLogger.d('searchRecents: dropping an unreadable entry ($error)');
    }
  }
  return items;
}

/// Puts [item] at the front, removing any earlier appearance of the same thing.
///
/// Identity is `globalKey` — server plus id — so the same film on two servers
/// keeps two entries, which is correct: they are two things to open, and the
/// row is about what you opened, not about what the title is.
List<MediaItem> rememberSearchRecent(MediaItem item) {
  final next = [item, ...readSearchRecents().where((existing) => existing.globalKey != item.globalKey)];
  if (next.length > searchRecentsLimit) next.removeRange(searchRecentsLimit, next.length);
  SettingsService.instance.write(SettingsService.searchRecentItems, [
    for (final entry in next) jsonEncode(entry.toJson()),
  ]);
  return next;
}

/// Empties the row. Shares its button with the query chips: "Wissen" on Zoeken
/// clears what the page shows, and on TV that is this.
void clearSearchRecents() {
  SettingsService.instance.write(SettingsService.searchRecentItems, const <String>[]);
}
