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
    final tk = tokens(context);
    final handheld = PlatformDetector.isHandheldIOS(context);
    final phone = handheld && PlatformDetector.isPhone(context);
    final tv = PlatformDetector.isTV();
    final inset = tv ? TvLayoutConstants.horizontalInset : 16.0;
    final artwork = media.backdropUrl.isEmpty ? media.posterUrl : media.backdropUrl;
    final top = handheld ? MediaQuery.paddingOf(context).top : 0.0;
    final surface = theme.scaffoldBackgroundColor;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = phone ? (width * 1.15).clamp(300.0, 510.0) : (width * 0.46).clamp(280.0, 590.0);
        final centered = phone;
        final content = Stack(
          children: [
            if (artwork.isNotEmpty)
              Positioned.fill(
                child: ExcludeSemantics(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: artwork,
                        fit: BoxFit.cover,
                        alignment: phone ? Alignment.topCenter : Alignment.centerRight,
                        errorBuilder: (_, _, _) => ColoredBox(color: surface),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: phone ? 0.45 : 0.08),
                              Colors.transparent,
                              surface,
                              surface,
                            ],
                            stops: const [0, 0.28, 0.91, 1],
                          ),
                        ),
                      ),
                      if (!centered)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [surface, surface.withValues(alpha: 0.76), surface.withValues(alpha: 0)],
                              stops: const [0, 0.38, 1],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                inset,
                artwork.isEmpty ? (handheld ? top + 64 : 24) : height * (phone ? 0.78 : 0.55),
                inset,
                12,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: tv ? double.infinity : 560),
                child: Column(
                  crossAxisAlignment: centered ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      media.title,
                      textAlign: centered ? TextAlign.center : TextAlign.start,
                      style: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    _MetaChips(media: media, detail: detail, centered: centered),
                    if (media.status != SeerrMediaStatus.unknown) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: centered ? Alignment.center : Alignment.centerLeft,
                        child: SeerrStatusBadge(status: media.status),
                      ),
                    ],
                    if (note case final note?) ...[
                      const SizedBox(height: 8),
                      Text(note, style: theme.textTheme.bodySmall?.copyWith(color: tk.textMuted)),
                    ],
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      if (centered)
                        for (var i = 0; i < actions.length; i++)
                          Padding(
                            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                            child: _ActionButton(action: actions[i], primary: i == 0, busy: busy),
                          )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (var i = 0; i < actions.length; i++)
                              _ActionButton(action: actions[i], primary: i == 0, busy: busy),
                          ],
                        ),
                    ],
                  ],
                ),
              ),
            ),
            if (handheld)
              PositionedDirectional(
                top: top + 6,
                start: 12,
                child: BackButton(
                  style: IconButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white),
                ),
              ),
          ],
        );
        return handheld
            ? AnnotatedRegion(
                value: artwork.isEmpty && tk.isLight ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
                child: content,
              )
            : content;
      },
    );
  }
}

/// Hero metadata as one flat text line (match · year · runtime · genres),
/// matching the app-wide "meta is text, not chips" rule.
class _MetaChips extends StatelessWidget {
  const _MetaChips({required this.media, required this.detail, required this.centered});

  final bool centered;
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
      textAlign: centered ? TextAlign.center : TextAlign.start,
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
