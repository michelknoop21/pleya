import 'package:flutter/material.dart';

import '../i18n/strings.g.dart';
import '../focus/focusable_button.dart';
import '../focus/focusable_wrapper.dart';
import '../models/seerr/seerr_media.dart';
import '../models/seerr/seerr_request.dart';
import '../screens/seerr/seerr_media_detail_screen.dart';
import '../services/seerr/seerr_constants.dart';
import '../services/settings_service.dart';
import '../theme/mono_theme.dart';
import '../theme/mono_tokens.dart';
import 'pressable.dart';
import 'seerr_poster_card.dart';
import 'seerr_status_badge.dart';

/// One request row: media icon, season pills, availability badge, lifecycle
/// status, requester, and discrete focusable action buttons.
class SeerrRequestRow extends StatelessWidget {
  const SeerrRequestRow({super.key, required this.request, this.onApprove, this.onDecline, this.onCancel});

  final SeerrRequest request;
  final VoidCallback? onApprove;
  final VoidCallback? onDecline;
  final VoidCallback? onCancel;

  /// The tapped row opens the graphical media detail — the same screen the
  /// discover posters open — so a request is never a dead end.
  void _openDetail(BuildContext context) {
    final tmdbId = request.tmdbId;
    if (tmdbId == null) return;
    final media = SeerrMedia(
      tmdbId: tmdbId,
      mediaType: request.mediaType,
      title: request.mediaTitle ?? '',
      year: request.mediaYear?.toString(),
      posterPath: request.posterPath,
      backdropPath: request.backdropPath,
      status: request.mediaStatus,
    );
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SeerrMediaDetailScreen(media: media)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTv = request.mediaType == 'tv';
    // No stand-in title. Naming the media type where the title belongs told the
    // user nothing about what was actually requested.
    final title = request.mediaTitle;
    final posterUrl = SeerrConstants.tmdbPosterUrl(request.posterPath);
    final canOpen = request.tmdbId != null;

    // Compact list thumbnail that follows the size slider (libraryDensity).
    final f = LibraryDensity.factor(SettingsService.instance.read(SettingsService.libraryDensity));
    final thumbW = 44 + f * 28; // 44→72
    final thumbH = thumbW * 1.5;

    final card = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.all(Radius.circular(tokens(context).radiusSm)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(tokens(context).radiusSm)),
            child: SizedBox(
              width: thumbW,
              height: thumbH,
              // The shared poster widget already falls back to a placeholder on
              // an empty or failing URL, so there is no second artwork path
              // here to keep in step with the grids.
              child: SeerrPosterImage(url: posterUrl),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                const SizedBox(height: 2),
                // Kind and year sit under the title rather than inside it, so a
                // long title has both lines to itself.
                Text(
                  _kindAndYear(isTv),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _lifecycleChip(theme),
                    // Availability is a second dimension, not a second opinion:
                    // it only earns a chip where it says something the lifecycle
                    // chip does not. "Completed" and "Available" are the same
                    // news to a user, so the pair never appears.
                    if (_availabilityAddsMeaning) SeerrStatusBadge(status: request.mediaStatus, compact: true),
                    if (request.is4k) _plainPill(theme, t.seerr.fourKBadge),
                  ],
                ),
                if (_seasonsLabel case final seasons?) ...[
                  const SizedBox(height: 6),
                  Text(
                    seasons,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
                if (request.requestedByName case final name? when name.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    t.seerr.requestedBy(name: name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          if (onApprove != null || onDecline != null || onCancel != null) ...[
            const SizedBox(width: 12),
            _actions(context),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: FocusableWrapper(
        onSelect: canOpen ? () => _openDetail(context) : null,
        child: Pressable(onTap: canOpen ? () => _openDetail(context) : null, child: card),
      ),
    );
  }

  Widget _actions(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        if (onApprove != null)
          _actionButton(onApprove!, FilledButton(onPressed: onApprove, child: Text(t.seerr.approve))),
        if (onDecline != null)
          _actionButton(onDecline!, OutlinedButton(onPressed: onDecline, child: Text(t.seerr.decline))),
        if (onCancel != null)
          _actionButton(onCancel!, TextButton(onPressed: onCancel, child: Text(t.seerr.cancelRequest))),
      ],
    );
  }

  Widget _actionButton(VoidCallback onPressed, Widget child) {
    return FocusableButton(onPressed: onPressed, child: child);
  }

  String _kindAndYear(bool isTv) {
    final kind = isTv ? t.discover.tvShow : t.discover.movie;
    final year = request.mediaYear;
    return year == null ? kind : '$kind · $year';
  }

  /// Whether the availability badge tells the user something the lifecycle chip
  /// has not already said. Partially available always does; fully available
  /// only while the request itself is not yet reported as completed.
  bool get _availabilityAddsMeaning => switch (request.mediaStatus) {
    SeerrMediaStatus.partiallyAvailable => true,
    SeerrMediaStatus.available => request.status != SeerrRequestStatus.completed,
    _ => false,
  };

  /// Seasons as one compact line: "Seizoen 3", "Seizoenen 18-22", or the count
  /// once the request is spread over too many separate runs to name them.
  String? get _seasonsLabel {
    final seasons = request.seasons;
    if (seasons.isEmpty) return null;
    if (seasons.length == 1) return t.seerr.season(number: seasons.first);
    final range = seerrSeasonRanges(seasons);
    return range == null ? t.seerr.seasonsCount(count: seasons.length) : t.seerr.seasonsRange(range: range);
  }

  Widget _lifecycleChip(ThemeData theme) {
    final (color, label) = switch (request.status) {
      SeerrRequestStatus.pending => (kAccentAlt, t.seerr.pending),
      SeerrRequestStatus.approved => (kSuccess, t.seerr.approved),
      SeerrRequestStatus.declined => (theme.colorScheme.error, t.seerr.declined),
      SeerrRequestStatus.completed => (kSuccess, t.seerr.completed),
      SeerrRequestStatus.failed => (theme.colorScheme.error, t.seerr.failed),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _plainPill(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
      child: Text(text, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}
