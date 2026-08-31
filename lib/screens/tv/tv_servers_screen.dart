/// Mijn Pleya ▸ Servers on TV (hoofdstuk 18.2).
///
/// The connection list already exists as [ConnectionsSection] — it is the one
/// part of the settings screen with real behaviour behind it, and it was split
/// out precisely so it could be mounted on its own. This gives it a page on TV
/// instead of asking a remote to scroll to it inside Instellingen.
///
/// Nothing new: same widget, same registry, same add/remove flows.
library;

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../widgets/tv/tv_unified_layout.dart';
import '../settings/connections_section.dart';

class TvServersScreen extends StatelessWidget {
  const TvServersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final tk = tokens(context);
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: TvTopNavLayout.pageInset * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t.tvMyPleya.servers,
            style: TextStyle(
              color: tk.text,
              fontSize: TvMyPleyaLayout.pageTitleFontSize * scale,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          SizedBox(height: TvMyPleyaLayout.titleGap * scale),
          const ConnectionsSection(),
        ],
      ),
    );
  }
}
