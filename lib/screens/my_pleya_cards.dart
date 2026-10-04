part of 'my_pleya_screen.dart';

/// Avatar, name and the server-status line from northstar 18. Deliberately
/// compact so the kijklijst rail lands in the first screenful instead of
/// below the fold, and so the account actions at the bottom stay secondary to
/// the content between them.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile, required this.onSwitchProfile, required this.serversLine});

  final Profile? profile;
  final VoidCallback onSwitchProfile;
  final String serversLine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
      child: Row(
        children: [
          // The avatar and the name read as an identity, not as a control, so
          // what it does is said out loud for anyone who cannot see that
          // tapping it leads to the profile picker.
          Semantics(
            button: true,
            label: t.screens.switchProfile,
            child: InkWell(
              onTap: onSwitchProfile,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    ProfileAvatar(profile: profile, size: 40),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(profile?.displayName ?? '', style: theme.textTheme.titleMedium),
                        Text(serversLine, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

/// The small caps section heading above a card row or list group
/// ("MIJN CONTENT", "BIBLIOTHEKEN EN BRONNEN", "PLEYA" in northstar 18).
class _MyPleyaGroupLabel extends StatelessWidget {
  const _MyPleyaGroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: tokens(context).textMuted, letterSpacing: 0.5),
      ),
    );
  }
}

/// Up to three [_MyPleyaCard]s side by side, evenly split. Fewer cards than
/// three still fill the row rather than leaving a gap on the right, which
/// only happens when a section (Aanvragen, Activiteit) is conditionally gone.
class _MyPleyaCardRow extends StatelessWidget {
  const _MyPleyaCardRow({required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      // IntrinsicHeight, not a bare stretch Row: this row sits in a sliver,
      // where the incoming height constraint is unbounded, and stretch alone
      // asks every card to fill that infinity.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: cards[i])],
          ],
        ),
      ),
    );
  }
}

/// One "Mijn content" / "Bibliotheken en bronnen" tile: icon, optional count
/// top-right, title, subtitle. `surfaceElevated` plus an outline, never a
/// Material container color — those collapse onto the page background in
/// this theme (see [[mono-theme-material-collisions]] in the tvOS gotchas).
class _MyPleyaCard extends StatelessWidget {
  const _MyPleyaCard({required this.tile, required this.onTap, this.onLongPress, this.icon});

  final TvMyPleyaTile tile;

  /// In place of the tile's line icon.
  final Widget? icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semanticsLabel = tile.count == null
        ? t.tvMyPleya.semantics.tile(title: tile.title, subtitle: tile.subtitle)
        : t.tvMyPleya.semantics.tileWithCount(title: tile.title, subtitle: tile.subtitle, count: '${tile.count}');

    // Same id/instance convention TV's tile uses (`myPleyaTile[<section
    // name>]`, `logout` for the sign-out tile). This screen re-buckets TV's
    // tiles into card rows, not a second taxonomy, so it reuses their ids too.
    return AutomationNode(
      id: AutomationIds.myPleyaTile,
      instance: tile.section?.name ?? 'logout',
      role: 'grid.item',
      child: Semantics(
        button: true,
        label: semanticsLabel,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tokens(context).surfaceElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: settingsOutlineColor(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    icon ?? Icon(tile.icon, size: 22),
                    if (tile.count != null) Text('${tile.count}', style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  tile.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: .bold),
                ),
                const SizedBox(height: 2),
                Text(
                  tile.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: tokens(context).textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
