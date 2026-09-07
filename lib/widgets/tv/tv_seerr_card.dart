/// One Aanvragen title on TV, in the catalog language
/// ([DEC-108](../../../docs/DECISIONS.md#dec-108), mockup 35).
///
/// Two adapters over one [TvCatalogCard], because Aanvragen shows the same
/// title in two roles and they are genuinely different objects:
///
/// * [TvSeerrMediaCard] is a discover row or a search hit — a TMDB title the
///   viewer might ask for. Its capsule says whether it has already been asked
///   for, which is `mediaInfo.status`.
/// * [TvSeerrRequestCard] is a filed request. Its capsule says where that
///   request stands, and it carries the one extra line the rest of the app's
///   cards do not: who asked for it.
///
/// ## The capsule, and why the status stays Seerr's
///
/// [DEC-108] (3) is explicit that "de aanvraagstatus blijft Seerr-state (PB-3)".
/// So nothing here reconciles a request against what the servers actually hold:
/// a request that Seerr calls approved reads as approved even if the file has
/// since appeared, and the only place the two meet is `mediaStatus`, which is
/// Seerr's own answer to the same question.
///
/// ## What the capsule costs, and what it bought
///
/// `SeerrStatusBadge` — the mobile badge — is a solid amber or green pill with
/// dark text and a drop shadow. On a wall of twelve posters that reads as twelve
/// coloured stickers, which is exactly the "afwijkende kaarttaal" CAT11 was
/// about. The capsule here is the catalog's own dark badge with a coloured dot:
/// the colour still carries the state at a glance, and the card still looks like
/// every other card in the app. The mobile badge is untouched.
library;

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../models/seerr/seerr_media.dart';
import '../../models/seerr/seerr_request.dart';
import '../../services/seerr/seerr_constants.dart';
import '../../theme/mono_theme.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import 'tv_catalog_card.dart';
import 'tv_unified_layout.dart';

/// A TMDB title on Ontdekken or in a Seerr search result.
class TvSeerrMediaCard extends StatelessWidget {
  const TvSeerrMediaCard({
    super.key,
    required this.media,
    required this.width,
    required this.onSelect,
    this.focusNode,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onBack,
    this.onFocusChange,
  });

  final SeerrMedia media;
  final double width;
  final VoidCallback onSelect;
  final FocusNode? focusNode;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;

  /// Menu on this card — see [TvCatalogCard.onBack].
  final VoidCallback? onBack;

  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) {
    final status = tvSeerrMediaStatusLabel(media.status);

    return TvCatalogCard(
      width: width,
      artwork: TvSeerrArtwork(url: media.posterUrl),
      topLeftMarker: status == null ? null : TvSeerrStatusCapsule(status: status),
      title: media.title,
      meta: tvSeerrMetaLine(year: media.year, isMovie: media.isMovie),
      onSelect: onSelect,
      focusNode: focusNode,
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
      onNavigateLeft: onNavigateLeft,
      onNavigateRight: onNavigateRight,
      onBack: onBack,
      onFocusChange: onFocusChange,
      semanticLabel: [media.title, ?media.year, ?status?.label].join(', '),
    );
  }
}

/// One filed request on Alle aanvragen (mockup 35 C1).
class TvSeerrRequestCard extends StatelessWidget {
  const TvSeerrRequestCard({
    super.key,
    required this.request,
    required this.width,
    required this.onSelect,
    this.focusNode,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onFocusChange,
  });

  final SeerrRequest request;
  final double width;
  final VoidCallback onSelect;
  final FocusNode? focusNode;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) {
    final status = tvSeerrRequestStatusLabel(request);
    final by = request.requestedByName;
    final title = request.mediaTitle ?? '';

    return TvCatalogCard(
      width: width,
      artwork: TvSeerrArtwork(url: SeerrConstants.tmdbPosterUrl(request.posterPath)),
      topLeftMarker: TvSeerrStatusCapsule(status: status),
      title: title,
      meta: tvSeerrMetaLine(year: request.mediaYear, isMovie: request.mediaType == 'movie'),
      // The one thing the list form had that a 281-wide card cannot also carry
      // is the date ("3 dagen geleden"); DEC-108 gives that up deliberately and
      // keeps the requester, which is the half that says whose request this is.
      tertiary: by == null ? null : t.seerr.requestedBy(name: by),
      onSelect: onSelect,
      focusNode: focusNode,
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
      onNavigateLeft: onNavigateLeft,
      onNavigateRight: onNavigateRight,
      onFocusChange: onFocusChange,
      semanticLabel: [
        title,
        ?request.mediaYear,
        status.label,
        if (by != null) t.seerr.requestedBy(name: by),
      ].join(', '),
    );
  }
}

/// The line under the title on an Aanvragen card: the year and what kind of
/// thing it is.
///
/// Not the genre the catalog card shows, and that is a data fact rather than a
/// design one: `SeerrMedia` parses no genres off a discover row, and a request
/// payload carries none at all. Mockup 35 A draws "2024 · Actie" and 35 C1 draws
/// "2024 · Film"; the second is the one the payload can actually answer, so it
/// is the one both use. A genre here would mean a second TMDB round trip per
/// card on a page of twelve.
String tvSeerrMetaLine({required String? year, required bool isMovie}) {
  final kind = isMovie ? t.seerr.kindMovie : t.seerr.kindShow;
  return [if (year != null && year.isNotEmpty) year, kind].join('  ·  ');
}

/// What a capsule says and which colour its dot is.
class TvSeerrStatus {
  const TvSeerrStatus(this.label, this.color, {this.prominent = false});

  final String label;
  final Color color;

  /// Whether the label reads at full ink. Reserved for Beschikbaar: it is the
  /// one status that is good news, and mockup 35 brightens it so it separates
  /// from the waiting ones without needing a second shape.
  final bool prominent;
}

/// What Seerr knows about a TMDB title the viewer has not filed a request for
/// from this screen — or null when it knows nothing worth a capsule.
///
/// `unknown` really is nothing: it is the state of every title nobody has ever
/// asked for, which is most of a discover row. A capsule on all twelve would
/// say only that the page loaded.
TvSeerrStatus? tvSeerrMediaStatusLabel(SeerrMediaStatus status) => switch (status) {
  SeerrMediaStatus.unknown => null,
  SeerrMediaStatus.pending => TvSeerrStatus(t.seerr.requested, kAccentAlt),
  SeerrMediaStatus.processing => TvSeerrStatus(t.seerr.processing, kAccentAlt),
  SeerrMediaStatus.partiallyAvailable => TvSeerrStatus(t.seerr.partiallyAvailable, kSuccess),
  SeerrMediaStatus.available => TvSeerrStatus(t.seerr.available, kSuccess, prominent: true),
};

/// Where a filed request stands.
///
/// Availability wins over the request's own status, because it is the later
/// fact: a request that Seerr approved and has since fulfilled is one the viewer
/// can watch, and "Goedgekeurd" on a title that is already there is the sort of
/// stale answer a request list is judged on.
TvSeerrStatus tvSeerrRequestStatusLabel(SeerrRequest request) {
  if (request.mediaStatus.isAvailable) return TvSeerrStatus(t.seerr.available, kSuccess, prominent: true);
  return switch (request.status) {
    SeerrRequestStatus.pending => TvSeerrStatus(t.seerr.pending, kAccentAlt),
    SeerrRequestStatus.approved => TvSeerrStatus(t.seerr.approved, kAccentAlt),
    SeerrRequestStatus.declined => TvSeerrStatus(t.seerr.declined, kAccent),
    SeerrRequestStatus.failed => TvSeerrStatus(t.seerr.failed, kAccent),
    SeerrRequestStatus.completed => TvSeerrStatus(t.seerr.completed, kSuccess, prominent: true),
  };
}

/// The capsule itself — the catalog's badge with a coloured dot in front.
class TvSeerrStatusCapsule extends StatelessWidget {
  const TvSeerrStatusCapsule({super.key, required this.status});

  final TvSeerrStatus status;

  @override
  Widget build(BuildContext context) =>
      TvCatalogArtworkBadge.status(label: status.label, dotColor: status.color, muted: !status.prominent);
}

/// A TMDB poster.
///
/// Straight `CachedNetworkImage` rather than `OptimizedMediaImage`: a TMDB URL
/// is already a complete, unsigned, size-suffixed address
/// ([SeerrConstants.tmdbImageBase]), so there is no client to resolve and no
/// token to keep out of a cache key — the one thing the media-server path exists
/// to handle.
class TvSeerrArtwork extends StatelessWidget {
  const TvSeerrArtwork({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const TvCatalogArtworkFill(child: _ArtworkFallback());
    return TvCatalogArtworkFill(
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        // No fade: the grid builds every card at once, so a per-card animation
        // turns opening the page into twelve things moving, and hoofdstuk 10.2b
        // asks this grid to hold still.
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        errorBuilder: (context, _, _) => const _ArtworkFallback(),
      ),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback();

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return Center(
      child: Icon(
        Symbols.movie_rounded,
        color: tk.text.withValues(alpha: TvCatalogLayout.inkTertiary),
        size: TvCatalogLayout.cardTitleFontSize * 2 * TvLayoutConstants.scaleOf(context),
      ),
    );
  }
}
