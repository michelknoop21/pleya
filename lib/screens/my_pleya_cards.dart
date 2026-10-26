part of 'my_pleya_screen.dart';

/// Side margin of every block on the page, as in the northstar.
const double _kMyPleyaInset = 16;

/// Large in-page title with the Pleya mark on the right (northstar 00).
class _MyPleyaTitle extends StatelessWidget {
  const _MyPleyaTitle();

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_kMyPleyaInset, 12, _kMyPleyaInset, 8),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  t.myPleya.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tk.text, fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.4),
                ),
              ),
            ),
            const ExcludeSemantics(child: PleyaLogo(size: 32)),
          ],
        ),
      ),
    );
  }
}

/// Avatar, name, the server-status line and a chevron; the whole line opens
/// the profile picker. A hairline closes it off, as in the northstar.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile, required this.onSwitchProfile, required this.serversLine});

  final Profile? profile;
  final VoidCallback onSwitchProfile;
  final String serversLine;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return Column(
      children: [
        // The avatar and the name read as an identity, not as a control, so
        // what it does is said out loud for anyone who cannot see it.
        Semantics(
          button: true,
          label: t.screens.switchProfile,
          child: InkWell(
            onTap: onSwitchProfile,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(_kMyPleyaInset, 10, _kMyPleyaInset - 4, 14),
              child: Row(
                children: [
                  ProfileAvatar(profile: profile, size: 48),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          profile?.displayName ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: tk.text, fontSize: 21, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(serversLine, style: TextStyle(color: tk.textMuted, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  Icon(Symbols.chevron_right_rounded, color: tk.text, size: 24),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kMyPleyaInset),
          child: Divider(height: 1, thickness: 1, color: tk.outline),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

/// The small caps heading above a block ("JE KIJKLIJST", "JOUW CONTENT",
/// "PLEYA"), with an optional link on the right.
class _MyPleyaGroupLabel extends StatelessWidget {
  const _MyPleyaGroupLabel(this.label, {this.action});

  final String label;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(_kMyPleyaInset, 16, action == null ? _kMyPleyaInset : 4, action == null ? 10 : 2),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: tokens(context).textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// "Bekijk alles" in the accent tint. Carries the id the old Kijklijst card
/// had (`my_pleya.tile[watchlist]`), because it is now the way in.
class _SeeAllLink extends StatelessWidget {
  const _SeeAllLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return AutomationNode(
      id: AutomationIds.myPleyaTile,
      instance: TvMyPleyaSection.watchlist.name,
      role: 'button',
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          foregroundColor: Color.lerp(tk.accent, tk.text, 0.65),
        ),
        child: Text(t.myPleya.seeAll, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// A column of [_MyPleyaRow]s with the northstar's small gap between them.
class _MyPleyaRowList extends StatelessWidget {
  const _MyPleyaRowList({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kMyPleyaInset),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[if (i > 0) const SizedBox(height: 8), rows[i]],
        ],
      ),
    );
  }
}

/// One destination as a quiet row card: icon in a circle, title, subtitle,
/// an optional count and a chevron. Sign out has no chevron (it acts, it does
/// not open a screen) and reads in the accent red.
class _MyPleyaRow extends StatelessWidget {
  const _MyPleyaRow({
    required this.instance,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
    this.count,
    this.destructive = false,
  });

  /// `my_pleya.tile[<instance>]`: the section name, or `logout`.
  final String instance;
  final IconData icon;
  final String title;
  final String subtitle;
  final int? count;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final ink = destructive ? tk.accent : tk.text;
    final label = count == null
        ? t.tvMyPleya.semantics.tile(title: title, subtitle: subtitle)
        : t.tvMyPleya.semantics.tileWithCount(title: title, subtitle: subtitle, count: '$count');
    final radius = BorderRadius.circular(12);

    return AutomationNode(
      id: AutomationIds.myPleyaTile,
      instance: instance,
      role: 'list.item',
      child: Semantics(
        button: true,
        label: label,
        // excludeSemantics also drops the InkWell's actions, so the node
        // carries them itself; otherwise VoiceOver finds nothing to activate.
        onTap: onTap,
        onLongPress: onLongPress,
        excludeSemantics: true,
        child: Material(
          color: tk.surface,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: tk.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 60),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: ink.withValues(alpha: 0.08), shape: BoxShape.circle),
                      child: Icon(icon, size: 20, color: ink),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: ink, fontSize: 14.5, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: tk.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (count != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          '$count',
                          style: TextStyle(color: tk.text, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    if (!destructive) Icon(Symbols.chevron_right_rounded, size: 20, color: tk.textMuted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Big P card: the shared [BigPCardFace] under a tap. The TV hub draws the
/// same face under the remote's focus.
class _BigPCard extends StatelessWidget {
  const _BigPCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kMyPleyaInset, 12, _kMyPleyaInset, 0),
      child: AutomationNode(
        id: AutomationIds.myPleyaTile,
        instance: TvMyPleyaSection.assistant.name,
        role: 'list.item',
        child: Semantics(
          button: true,
          label: t.tvMyPleya.semantics.tile(title: t.assistant.tileTitle, subtitle: t.myPleya.bigPSubtitle),
          onTap: onTap,
          excludeSemantics: true,
          child: Material(
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                BigPCardFace(subtitle: t.myPleya.bigPSubtitle),
                Positioned.fill(
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(onTap: onTap),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
