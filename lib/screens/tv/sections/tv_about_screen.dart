/// Mijn Pleya ▸ Over on TV.
///
/// The mobile screen draws a centred app logo, a large centred tagline and a
/// stack of desktop settings cards. In the TV shell that composition put its
/// tagline underneath the page heading, sliced mid-glyph, and gave the page two
/// card insets (1.54% and 3.07%) on top of the shell's own 1.61% heading. This
/// is the approved `about-a` layout instead: version and device as the group
/// label, the four destinations as tiles, and the licence notice below them.
///
/// Nothing is dropped. Source code, upstream, privacy policy and the licence
/// list open the same URLs and the same screen as before, and the GPL notice is
/// a licence requirement rather than decoration, so it keeps a full-width place
/// of its own rather than being shortened to fit a tile.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../focus/focus_memory_tracker.dart';
import '../../../i18n/strings.g.dart';
import '../../../navigation/tv/tv_content_route_registry.dart';
import '../../../utils/layout_constants.dart';
import '../../../widgets/tv/tv_menu_grid.dart';
import '../../../widgets/tv/tv_page_surface.dart';
import '../../../widgets/tv/tv_unified_layout.dart';
import '../../settings/about_screen.dart';
import '../../settings/licenses_screen.dart';

class TvAboutScreen extends StatefulWidget {
  const TvAboutScreen({super.key});

  @override
  State<TvAboutScreen> createState() => _TvAboutScreenState();
}

class _TvAboutScreenState extends State<TvAboutScreen> {
  final FocusMemoryTracker _nodes = FocusMemoryTracker(debugLabelPrefix: 'tvAbout');
  String? _version;
  String? _build;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform()
        .then((info) {
          if (!mounted) return;
          setState(() {
            _version = info.version;
            _build = info.buildNumber;
          });
        })
        .catchError((_) => null);
  }

  @override
  void dispose() {
    _nodes.dispose();
    super.dispose();
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // SYS-1e: `TvAboutScreen` is mounted through `tvMyPleyaNestedRoute`, which
  // has no `Navigator` of its own, so a bare `Navigator.push` resolves to the
  // profile navigator above the shell and draws over the top bar entirely.
  // Same fix as SYS-1d's catalog opener: route through the shell when one is
  // listening, fall back to the plain push everywhere else (off TV, tests).
  void _openLicenses() {
    Widget builder(BuildContext _) => const LicensesScreen();
    final nested = openTvContentRoute(id: 'tvAboutLicenses', builder: builder);
    if (nested == null) {
      Navigator.push(context, MaterialPageRoute<void>(builder: builder));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final version = _version == null ? t.app.title : t.about.versionLabel(version: _version!);
    final label = [version, if (_build != null && _build!.isNotEmpty) '(${_build!})'].join(' ');

    return TvPageSurface(
      title: t.about.title,
      automationInstance: 'about',
      children: [
        TvMenuGrid(
          nodes: _nodes,
          columns: 2,
          automationInstance: 'about',
          sections: [
            TvMenuSection(
              label: label,
              items: [
                TvMenuItem(
                  key: 'about_source',
                  icon: Symbols.code_rounded,
                  title: t.about.sourceCode,
                  subtitle: t.about.sourceCodeDescription,
                  onSelect: () => _open(AboutScreen.sourceUrl),
                ),
                TvMenuItem(
                  key: 'about_upstream',
                  icon: Symbols.alt_route_rounded,
                  title: t.about.basedOnPlezy,
                  subtitle: t.about.upstreamProject,
                  onSelect: () => _open(AboutScreen.upstreamUrl),
                ),
                TvMenuItem(
                  key: 'about_privacy',
                  icon: Symbols.privacy_tip_rounded,
                  title: t.about.privacyPolicy,
                  onSelect: () => _open(AboutScreen.privacyUrl),
                ),
                TvMenuItem(
                  key: 'about_licenses',
                  icon: Symbols.description_rounded,
                  title: t.about.openSourceLicenses,
                  subtitle: t.about.viewLicensesDescription,
                  onSelect: _openLicenses,
                ),
              ],
            ),
          ],
        ),
        SizedBox(height: TvMyPleyaLayout.groupGap * scale),
        TvPageGroupLabel(t.about.licence),
        // Verbatim, and unfocusable: this is the attribution and
        // corresponding-source offer the GPL requires, not a control.
        TvPageBlock.text(AboutScreen.licenceNotice),
      ],
    );
  }
}
