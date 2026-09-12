import 'package:flutter/material.dart';

import '../i18n/strings.g.dart';
import '../widgets/focused_scroll_scaffold.dart';
import 'settings/connections_section.dart';

/// Mijn Pleya ▸ Servers on mobile, per northstar 18.
///
/// Same registry, same actions as the settings screen's own connections
/// block ([ConnectionsSection]) and the same wrap TV already did in
/// `TvServersPage` — a screen just mounts the one existing section, so
/// server management stays in one place instead of growing a second copy.
class ServersScreen extends StatelessWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FocusedScrollScaffold(
      title: Text(t.tvMyPleya.servers),
      slivers: const [
        SliverPadding(
          padding: EdgeInsets.only(top: 8),
          sliver: SliverToBoxAdapter(child: ConnectionsSection()),
        ),
      ],
    );
  }
}
