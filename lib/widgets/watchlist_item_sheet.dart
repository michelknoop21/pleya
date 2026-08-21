import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../i18n/strings.g.dart';
import '../media/watchlist_entry.dart';
import '../providers/watchlist_provider.dart';
import 'overlay_sheet.dart';

/// What the sheet was closed with.
enum WatchlistSheetAction { request, remove, cancel }

/// The sheet behind a watchlist title that cannot be played from here.
///
/// A tap opens this rather than jumping straight into the Seerr request flow.
/// A tap must not set a write to an external server in motion, and this sheet
/// is also the only place such a title can still be removed from the list.
///
/// Three variants, driven entirely by [WatchlistProvider.requestability]:
///
/// * [WatchlistRequestability.ready] puts Request up front. Every server
///   answered and none of them has it.
/// * [WatchlistRequestability.resolvable] keeps Request available but
///   secondary, and says why: a server could not be reached, so the title may
///   well be sitting on it. Leading with Request there would turn one offline
///   server into a pile of duplicate requests.
/// * [WatchlistRequestability.unsupported] leaves Request out. No Seerr, or
///   nothing to request.
Future<WatchlistSheetAction?> showWatchlistItemSheet(
  BuildContext context, {
  required WatchlistEntry entry,
  required WatchlistRequestability requestability,
}) {
  return OverlaySheetController.showAdaptive<WatchlistSheetAction>(
    context,
    builder: (sheetContext) => WatchlistItemSheet(entry: entry, requestability: requestability),
  );
}

class WatchlistItemSheet extends StatelessWidget {
  const WatchlistItemSheet({super.key, required this.entry, required this.requestability});

  final WatchlistEntry entry;
  final WatchlistRequestability requestability;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canRequest = requestability != WatchlistRequestability.unsupported;
    final requestIsPrimary = requestability == WatchlistRequestability.ready;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(entry.item.title ?? '', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            if (entry.item.year != null) ...[
              const SizedBox(height: 4),
              Text(
                '${entry.item.year}',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 12),
            Text(_statusLine, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            if (canRequest && requestIsPrimary)
              FilledButton.icon(
                onPressed: () => OverlaySheetController.closeAdaptive(context, WatchlistSheetAction.request),
                icon: const Icon(Symbols.playlist_add_rounded),
                label: Text(t.seerr.request),
              ),
            if (canRequest && !requestIsPrimary)
              OutlinedButton.icon(
                onPressed: () => OverlaySheetController.closeAdaptive(context, WatchlistSheetAction.request),
                icon: const Icon(Symbols.playlist_add_rounded),
                label: Text(t.seerr.request),
              ),
            if (canRequest) const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => OverlaySheetController.closeAdaptive(context, WatchlistSheetAction.remove),
              icon: const Icon(Symbols.delete_rounded),
              label: Text(t.watchlist.remove),
              style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => OverlaySheetController.closeAdaptive(context, WatchlistSheetAction.cancel),
              child: Text(t.common.cancel),
            ),
          ],
        ),
      ),
    );
  }

  /// Says exactly what was checked, and no more.
  ///
  /// "Not in any of your libraries" would overclaim: a local folder and a
  /// Pleya Share cannot answer a catalogue lookup at all, so even a complete
  /// sweep across Plex and Jellyfin does not cover everything the user has.
  String get _statusLine {
    if (!entry.coverageComplete && entry.availability == WatchlistAvailability.notFound) {
      return t.watchlist.coverageIncomplete;
    }
    return switch (entry.availability) {
      WatchlistAvailability.notFound => t.watchlist.notFoundOnServers,
      WatchlistAvailability.checking => t.watchlist.checking,
      _ => t.watchlist.notFoundOnServers,
    };
  }
}
