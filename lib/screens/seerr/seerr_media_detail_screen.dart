import 'dart:async';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/focusable_button.dart';
import '../../i18n/strings.g.dart';
import '../../models/seerr/seerr_media.dart';
import '../../providers/seerr_provider.dart';
import '../../services/seerr/seerr_client.dart';
import '../../services/seerr/seerr_constants.dart';
import '../../services/settings_service.dart';
import '../../theme/mono_theme.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/collapsible_text.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/pressable.dart';
import '../../widgets/seerr_poster_card.dart';
import '../../widgets/seerr_request_sheet.dart';
import '../../widgets/seerr_status_badge.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/state_view.dart';

/// A graphical detail page for a Jellyseerr / Overseerr media item, styled to
/// match the app's own [MediaDetailScreen] (hero backdrop + poster + metadata +
/// action). Loads the full detail (genres, runtime, cast) on open and offers a
/// recommendations row, so browsing seerr results feels like browsing the
/// library instead of a bare list.
class SeerrMediaDetailScreen extends StatefulWidget {
  const SeerrMediaDetailScreen({super.key, required this.media});

  /// The search/discover row that was tapped. Its poster/title render instantly
  /// while the full detail loads.
  final SeerrMedia media;

  @override
  State<SeerrMediaDetailScreen> createState() => _SeerrMediaDetailScreenState();
}

class _SeerrMediaDetailScreenState extends State<SeerrMediaDetailScreen> {
  SeerrMediaDetail? _detail;
  List<SeerrMedia> _recommendations = const [];
  bool _loading = true;
  bool _errored = false;
  bool _network = false;

  SeerrMedia get _base => _detail?.media ?? widget.media;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final client = context.read<SeerrProvider>().client;
    if (client == null) {
      setState(() {
        _loading = false;
        _errored = true;
      });
      return;
    }
    setState(() {
      _loading = true;
      _errored = false;
    });
    try {
      final detail = await client.getMediaDetail(tmdbId: widget.media.tmdbId, isMovie: widget.media.isMovie);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
      unawaited(_loadRecommendations(client));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errored = true;
        _network = e is SeerrException && e.isNetwork;
      });
    }
  }

  Future<void> _loadRecommendations(SeerrClient client) async {
    try {
      final page = await client.getRecommendations(tmdbId: widget.media.tmdbId, isMovie: widget.media.isMovie);
      if (!mounted) return;
      setState(() => _recommendations = page.items);
    } catch (_) {
      // Recommendations are a nicety — silently skip on failure.
    }
  }

  Future<void> _openRequest() async {
    final requested = await SeerrRequestSheet.show(context, media: _base);
    if (requested == true && mounted) {
      // Refresh so the status badge/action reflect the new request.
      unawaited(_load());
    }
  }

  void _openMedia(SeerrMedia media) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SeerrMediaDetailScreen(media: media)));
  }

  @override
  Widget build(BuildContext context) {
    return FocusedScrollScaffold(
      title: Text(_base.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      slivers: _buildSlivers(),
    );
  }

  List<Widget> _buildSlivers() {
    if (_loading && _detail == null) {
      return [
        SliverToBoxAdapter(
          child: _HeroHeader(media: widget.media, detail: null, onRequest: _openRequest),
        ),
        const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.all(24), child: _DetailSkeleton()),
        ),
      ];
    }

    if (_errored && _detail == null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: StateView.error(
            title: _network ? t.seerr.errorNetwork : t.seerr.errorGeneric,
            icon: Symbols.cloud_off_rounded,
            onRetry: _load,
            retryLabel: t.common.retry,
          ),
        ),
      ];
    }

    final detail = _detail;
    final inset = PlatformDetector.isTV() ? TvLayoutConstants.horizontalInset : 12.0;
    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: _HeroHeader(media: _base, detail: detail, onRequest: _openRequest),
      ),
    ];

    if ((_base.overview ?? '').isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(inset, 16, inset, 8),
            child: CollapsibleText(text: _base.overview!),
          ),
        ),
      );
    }

    if (detail != null && detail.cast.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: _CastRow(cast: detail.cast, inset: inset),
        ),
      );
    }

    if (_recommendations.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: _PosterRow(
            title: t.seerr.recommendations,
            items: _recommendations,
            inset: inset,
            onTapItem: _openMedia,
          ),
        ),
      );
    }

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));
    return slivers;
  }
}

/// Section header styled like the discover rows / app `HubSection`: `titleLarge`
/// w700, bumped to 26 on TV for across-the-room legibility.
TextStyle? _sectionHeaderStyle(BuildContext context) {
  final base = Theme.of(context).textTheme.titleLarge;
  if (PlatformDetector.isTV()) {
    return base?.copyWith(fontSize: 26, fontWeight: FontWeight.w700);
  }
  return base?.copyWith(fontWeight: FontWeight.w700);
}

// -----------------------------------------------------------------------------
// Hero header
// -----------------------------------------------------------------------------

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.media, required this.detail, required this.onRequest});

  final SeerrMedia media;
  final SeerrMediaDetail? detail;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Melt the backdrop into the actual page background (like TvSpotlightBackground),
    // not a hardcoded black — correct in light, dark and OLED themes.
    final surface = theme.scaffoldBackgroundColor;
    final inset = PlatformDetector.isTV() ? TvLayoutConstants.horizontalInset : 12.0;
    final backdropHeight = MediaQuery.sizeOf(context).width * 9 / 16;
    final maxBackdrop = PlatformDetector.isTV() ? 520.0 : 320.0;
    final height = backdropHeight.clamp(200.0, maxBackdrop);
    // How far the content overlaps up into the backdrop. The content still takes
    // real layout space below, so nothing clips or overlaps the next sliver.
    const overlap = 56.0;

    final Widget backdrop = media.backdropUrl.isEmpty
        ? ColoredBox(color: scheme.surfaceContainerHighest)
        : CachedNetworkImage(
            imageUrl: media.backdropUrl,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => ColoredBox(color: scheme.surfaceContainerHighest),
          );

    // Stack sizes to the non-positioned child (the padded content), so the total
    // height accounts for the poster/title/action — the request button is always
    // fully on screen.
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SizedBox(
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                backdrop,
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, surface.withValues(alpha: 0.6), surface],
                      stops: const [0.0, 0.7, 1.0],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: height - overlap, left: inset, right: inset),
          child: _HeroContent(media: media, detail: detail, onRequest: onRequest),
        ),
      ],
    );
  }
}

class _HeroContent extends StatelessWidget {
  const _HeroContent({required this.media, required this.detail, required this.onRequest});

  final SeerrMedia media;
  final SeerrMediaDetail? detail;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(tokens(context).radiusMd),
          child: SizedBox(width: 110, height: 165, child: SeerrPosterImage(url: media.posterUrl)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                media.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              _MetaChips(media: media, detail: detail),
              if (media.status != SeerrMediaStatus.unknown) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SeerrStatusBadge(status: media.status),
                ),
              ],
              const SizedBox(height: 12),
              _RequestButton(status: media.status, onRequest: onRequest),
            ],
          ),
        ),
      ],
    );
  }
}

/// Hero metadata as pill chips, matching the app detail screen: an amber
/// "XX% match" derived from the vote, then year / runtime / genre chips.
class _MetaChips extends StatelessWidget {
  const _MetaChips({required this.media, required this.detail});

  final SeerrMedia media;
  final SeerrMediaDetail? detail;

  @override
  Widget build(BuildContext context) {
    final isTv = PlatformDetector.isTV();
    final vote = detail?.voteAverage;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (vote != null)
          Text(
            '${(vote * 10).round()}% match',
            style: TextStyle(color: kAccentAlt, fontWeight: FontWeight.w700, fontSize: isTv ? 16 : 14),
          ),
        if (media.year != null) _chip(context, media.year!),
        if (detail?.runtimeMinutes != null) _chip(context, _formatRuntime(detail!.runtimeMinutes!)),
        for (final g in (detail?.genres ?? const <String>[]).take(3)) _chip(context, g),
      ],
    );
  }

  Widget _chip(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    final isTv = PlatformDetector.isTV();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isTv ? 14 : 12, vertical: isTv ? 8 : 6),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.8),
        borderRadius: const BorderRadius.all(Radius.circular(100)),
      ),
      child: Text(
        text,
        style: TextStyle(color: cs.onSecondaryContainer, fontSize: isTv ? 16 : 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  String _formatRuntime(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
    return '${m}m';
  }
}

class _RequestButton extends StatelessWidget {
  const _RequestButton({required this.status, required this.onRequest});

  final SeerrMediaStatus status;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final available = status.isAvailable;
    final isTv = PlatformDetector.isTV();
    final tvScale = TvLayoutConstants.scaleOf(context);
    final onPressed = available ? null : onRequest;
    // App action-button styling: default Material radius, bold label, TV-scaled.
    final style = FilledButton.styleFrom(
      textStyle: TextStyle(fontSize: isTv ? 17 * tvScale : 16, fontWeight: FontWeight.w700),
      padding: EdgeInsets.symmetric(horizontal: isTv ? 20 * tvScale : 20, vertical: isTv ? 12 * tvScale : 12),
    );
    return FocusableButton(
      autofocus: true,
      useBackgroundFocus: true,
      onPressed: onPressed,
      child: Pressable(
        onTap: onPressed,
        child: FilledButton.icon(
          onPressed: onPressed,
          style: style,
          icon: AppIcon(
            available ? Symbols.check_circle_rounded : Symbols.playlist_add_rounded,
            fill: 1,
            size: isTv ? 22 * tvScale : 20,
          ),
          label: Text(available ? t.seerr.available : t.seerr.request),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Cast row
// -----------------------------------------------------------------------------

class _CastRow extends StatelessWidget {
  const _CastRow({required this.cast, required this.inset});

  final List<SeerrCastMember> cast;
  final double inset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: Text(t.seerr.cast, style: _sectionHeaderStyle(context)),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: inset),
              itemCount: cast.length > 20 ? 20 : cast.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) => _CastCard(member: cast[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class _CastCard extends StatelessWidget {
  const _CastCard({required this.member});

  final SeerrCastMember member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Avatar follows the size slider (libraryDensity), like the native cast row.
    final f = LibraryDensity.factor(SettingsService.instance.read(SettingsService.libraryDensity));
    final img = 72 + f * 32; // 72→104
    return SizedBox(
      width: img + 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(tokens(context).radiusSm),
            child: SizedBox(
              width: img,
              height: img,
              child: member.profileUrl.isEmpty
                  ? ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: Icon(Symbols.person_rounded, color: scheme.onSurfaceVariant),
                    )
                  : CachedNetworkImage(
                      imageUrl: member.profileUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(Symbols.person_rounded, color: scheme.onSurfaceVariant),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            member.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (member.character != null && member.character!.isNotEmpty)
            Text(
              member.character!,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Poster row (recommendations)
// -----------------------------------------------------------------------------

class _PosterRow extends StatelessWidget {
  const _PosterRow({required this.title, required this.items, required this.inset, required this.onTapItem});

  final String title;
  final List<SeerrMedia> items;
  final double inset;
  final ValueChanged<SeerrMedia> onTapItem;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: Text(title, style: _sectionHeaderStyle(context)),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = seerrRowCardWidthOf(context, constraints.maxWidth);
              return SizedBox(
                height: cardWidth * 3 / 2 + seerrCardTextExtent,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: inset),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final media = items[index];
                    return SeerrPosterCard(media: media, onTap: () => onTapItem(media), width: cardWidth);
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [SkeletonHubRow(cardWidth: seerrPosterWidth, rowHeight: seerrPosterHeight + 16)],
    );
  }
}
