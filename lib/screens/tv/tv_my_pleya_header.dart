part of 'tv_my_pleya_screen.dart';

/// Avatar, name, how many servers answered, and the one action that belongs to
/// an identity rather than to a section.
///
/// Hoofdstuk 18.4 is the rule on the right-hand list: one server down among
/// several healthy ones is a line in this list, not a banner over the content,
/// and an auth failure is an amber line rather than a blocking red one.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.servers,
    required this.scale,
    required this.node,
    required this.onSwitchProfile,
    required this.onExitUp,
    required this.onNavigateDown,
  });

  final Profile? profile;
  final MultiServerProvider servers;
  final double scale;
  final FocusNode node;
  final VoidCallback onSwitchProfile;
  final VoidCallback onExitUp;
  final VoidCallback onNavigateDown;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final total = servers.totalServerCount;
    final online = servers.onlineServerCount;

    // VIS-0925-C: no tinted box of its own. On the tv the header's fill read
    // as a loose grey bar under the navigation; the avatar, name and action
    // sit on the page like the title above them.
    return Padding(
      padding: EdgeInsets.symmetric(vertical: TvMyPleyaLayout.headerPadding / 2 * scale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ExcludeSemantics(
            child: ProfileAvatar(profile: profile, size: TvMyPleyaLayout.avatarSize * scale),
          ),
          SizedBox(width: TvMyPleyaLayout.headerGap * scale),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                profile?.displayName ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tk.text,
                  fontSize: TvMyPleyaLayout.headerNameFontSize * scale,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                total == 0 ? t.tvMyPleya.noServers : t.tvMyPleya.serversOnline(online: '$online', total: '$total'),
                style: TextStyle(
                  color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
                  fontSize: TvMyPleyaLayout.headerMetaFontSize * scale,
                ),
              ),
            ],
          ),
          SizedBox(width: TvMyPleyaLayout.headerGap * scale),
          _SwitchProfileAction(
            node: node,
            scale: scale,
            onSelect: onSwitchProfile,
            onNavigateUp: onExitUp,
            onNavigateDown: onNavigateDown,
          ),
          const Spacer(),
          Flexible(
            child: _ServerStatusList(servers: servers, scale: scale),
          ),
        ],
      ),
    );
  }
}

class _SwitchProfileAction extends StatelessWidget {
  const _SwitchProfileAction({
    required this.node,
    required this.scale,
    required this.onSelect,
    required this.onNavigateUp,
    required this.onNavigateDown,
  });

  final FocusNode node;
  final double scale;
  final VoidCallback onSelect;
  final VoidCallback onNavigateUp;
  final VoidCallback onNavigateDown;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    const shape = StadiumBorder();
    return FocusableWrapper(
      focusNode: node,
      onSelect: onSelect,
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
      focusShapeBorder: shape,
      disableScale: true,
      semanticLabel: t.screens.switchProfile,
      child: Container(
        // The ring gap as a margin rather than a Padding around this Container:
        // a Container lays out margin, then decoration, then padding, so the two
        // are the same picture with one widget less.
        margin: EdgeInsets.all(TvTopNavLayout.focusRingGap * scale),
        decoration: ShapeDecoration(
          shape: shape,
          color: tk.text.withValues(alpha: TvMyPleyaLayout.tileFocusedFillAlpha),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: TvTopNavLayout.pillPaddingHorizontal * scale,
          vertical: TvTopNavLayout.pillPaddingVertical * scale,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.switch_account_rounded,
              size: TvMyPleyaLayout.tileIconSize * scale,
              color: tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
            ),
            SizedBox(width: TvCatalogLayout.actionIconGap * scale),
            Text(
              t.screens.switchProfile,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tk.text,
                fontSize: TvTopNavLayout.itemFontSize * scale,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The right-hand server list: a dot per server, and the auth line underneath.
///
/// Not focusable. It is a status readout, and a remote that has to walk past
/// three servers to reach the first tile is a remote fighting the page. It is
/// still announced, as one node, so a VoiceOver user hears the same summary a
/// sighted user reads.
class _ServerStatusList extends StatelessWidget {
  const _ServerStatusList({required this.servers, required this.scale});

  final MultiServerProvider servers;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final rows = servers.serverIds
        .map(
          (id) => (
            id: id,
            name: servers.serverManager.serverDisplayName(ServerId(id)),
            online: servers.onlineServerIds.contains(id),
          ),
        )
        .toList();
    if (rows.isEmpty) return const SizedBox.shrink();

    final authErrors = servers.authErrorServers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows)
          Padding(
            padding: EdgeInsets.only(bottom: TvMyPleyaLayout.serverRowGap * scale),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  // Keyed on the server id, not the name: two servers can share a
                  // display name, and a rename must not orphan this key (TOK2).
                  key: ValueKey('tv.my-pleya.server-dot.${row.id}.${row.online ? 'online' : 'offline'}'),
                  width: TvMyPleyaLayout.serverDotSize * scale,
                  height: TvMyPleyaLayout.serverDotSize * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // Red here is a status dot on a status list, not navigation
                    // chrome — hoofdstuk 33 reserves the brand red for the
                    // progress line and small semantic marks, and this is one.
                    // Groen komt uit dezelfde autoriteit als rood: `kSuccess` in
                    // mono_theme.dart. Hier stond `#3FBF5F`, de laatste losse
                    // statuskleur in lib (TOK2, na TOK-1 en TOK-3).
                    color: row.online ? kSuccess : kAccent,
                  ),
                ),
                SizedBox(width: TvMyPleyaLayout.serverRowGap * scale),
                Text(
                  row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tk.text,
                    fontSize: TvMyPleyaLayout.serverRowFontSize * scale,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: TvMyPleyaLayout.serverRowGap * scale),
                Text(
                  row.online ? t.tvMyPleya.statusOnline : t.tvMyPleya.statusOffline,
                  style: TextStyle(
                    color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
                    fontSize: TvMyPleyaLayout.serverRowFontSize * scale,
                  ),
                ),
              ],
            ),
          ),
        // Hoofdstuk 18.4: amber, one line, and never a blocking banner over the
        // content.
        if (authErrors.isNotEmpty)
          Text(
            authErrors.length == 1
                ? t.connections.sessionExpiredOne(name: authErrors.first.displayName)
                : t.connections.sessionExpiredMany(count: '${authErrors.length}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: kAccentAlt, fontSize: TvMyPleyaLayout.serverRowFontSize * scale),
          ),
      ],
    );
  }
}
