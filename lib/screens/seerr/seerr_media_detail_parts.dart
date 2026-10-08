part of 'seerr_media_detail_screen.dart';

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
  const _HeroHeader({required this.media, required this.detail, required this.actions, this.note, this.busy = false});

  final SeerrMedia media;
  final SeerrMediaDetail? detail;
  final List<_DetailAction> actions;
  final String? note;
  final bool busy;

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
            errorBuilder: (_, _, _) => ColoredBox(color: scheme.surfaceContainerHighest),
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
                      // Using the page background is right, but the alphas are
                      // not mode-neutral: in light mode this wash is white, so
                      // it brightens the backdrop while the title overlapping
                      // it stays near-black. Light holds the wash longer.
                      colors: [
                        Colors.transparent,
                        surface.withValues(alpha: tokens(context).artworkScrimAlpha(dark: 0.6, light: 0.85)),
                        surface,
                      ],
                      stops: tokens(context).isLight ? const [0.0, 0.55, 1.0] : const [0.0, 0.7, 1.0],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: height - overlap, left: inset, right: inset),
          child: _HeroContent(media: media, detail: detail, actions: actions, note: note, busy: busy),
        ),
      ],
    );
  }
}

class _HeroContent extends StatelessWidget {
  const _HeroContent({
    required this.media,
    required this.detail,
    required this.actions,
    required this.note,
    required this.busy,
  });

  final SeerrMedia media;
  final SeerrMediaDetail? detail;
  final List<_DetailAction> actions;
  final String? note;
  final bool busy;

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
              if (note case final note?) ...[
                const SizedBox(height: 8),
                Text(note, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < actions.length; i++)
                    _ActionButton(action: actions[i], primary: i == 0, busy: busy),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Hero metadata as one flat text line (match · year · runtime · genres),
/// matching the app-wide "meta is text, not chips" rule.
class _MetaChips extends StatelessWidget {
  const _MetaChips({required this.media, required this.detail});

  final SeerrMedia media;
  final SeerrMediaDetail? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTv = PlatformDetector.isTV();
    final vote = detail?.voteAverage;
    final parts = <String>[
      if (vote != null) t.seerr.percentMatch(percent: (vote * 10).round()),
      if (media.year != null) media.year!,
      if (detail?.runtimeMinutes != null) formatDurationTextual(detail!.runtimeMinutes! * 60000),
      if ((detail?.genres ?? const <String>[]).isNotEmpty) detail!.genres.take(3).join(', '),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontSize: isTv ? 16 : 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

/// One button under the title: what it is called in a scenario, what it says,
/// and what it does.
class _DetailAction {
  const _DetailAction(this.id, this.label, this.icon, this.onPressed);

  final String id;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action, required this.primary, required this.busy});

  final _DetailAction action;
  final bool primary;

  /// A reload is running. The button keeps its place and its focus and does
  /// nothing until the answer is in.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final isTv = PlatformDetector.isTV();
    final tvScale = TvLayoutConstants.scaleOf(context);
    final onPressed = busy ? () {} : action.onPressed;
    // App action-button styling: default Material radius, bold label, TV-scaled.
    final textStyle = TextStyle(fontSize: isTv ? 17 * tvScale : 16, fontWeight: FontWeight.w700);
    final padding = EdgeInsets.symmetric(horizontal: isTv ? 20 * tvScale : 20, vertical: isTv ? 12 * tvScale : 12);
    final icon = AppIcon(action.icon, fill: 1, size: isTv ? 22 * tvScale : 20);
    final label = Text(action.label);
    return SeerrFocusNode(
      id: AutomationIds.requestsDetailAction,
      instance: action.id,
      role: 'button',
      label: action.label,
      state: () => {'primary': primary, 'busy': busy},
      builder: (_, node) => FocusableButton(
        focusNode: node,
        autofocus: primary,
        onPressed: onPressed,
        child: Pressable(
          onTap: onPressed,
          child: primary
              ? FilledButton.icon(
                  onPressed: busy ? null : action.onPressed,
                  style: FilledButton.styleFrom(textStyle: textStyle, padding: padding),
                  icon: icon,
                  label: label,
                )
              : OutlinedButton.icon(
                  onPressed: busy ? null : action.onPressed,
                  style: OutlinedButton.styleFrom(textStyle: textStyle, padding: padding),
                  icon: icon,
                  label: label,
                ),
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
                      errorBuilder: (_, _, _) => ColoredBox(
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
              final metrics = seerrRowMetricsOf(context, constraints.maxWidth);
              return SizedBox(
                height: metrics.rowHeight,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: EdgeInsets.symmetric(horizontal: inset, vertical: metrics.focusReserve),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => SizedBox(width: metrics.itemGap),
                  itemBuilder: (context, index) {
                    final media = items[index];
                    return SeerrPosterCard(media: media, onTap: () => onTapItem(media), width: metrics.cardWidth);
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
