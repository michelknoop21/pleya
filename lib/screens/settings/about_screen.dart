import 'package:flutter/material.dart';
import 'package:pleya/widgets/app_icon.dart';
import 'package:pleya/widgets/pleya_logo.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../i18n/strings.g.dart';
import 'licenses_screen.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static final Future<PackageInfo> _packageInfoFuture = PackageInfo.fromPlatform();

  // Pleya is a fork of Plezy (GPL-3.0). Attribution and the corresponding-source
  // offer below are required by the licence; the public source and privacy
  // policy URLs are supplied at build time.
  static const String _upstreamUrl = 'https://github.com/edde746/plezy';
  static const String _sourceUrl = String.fromEnvironment(
    'SOURCE_REPO_URL',
    defaultValue: 'https://github.com/michelknoop21/pleya',
  );
  static const String _privacyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
    defaultValue: 'https://pleya.app/privacy',
  );

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final appName = t.app.title;

    return FutureBuilder<PackageInfo>(
      future: _packageInfoFuture,
      builder: (context, snapshot) {
        final appVersion = snapshot.data?.version ?? '';
        return FocusedScrollScaffold(
          title: Text(t.about.title),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // App Icon and Name
                  Center(
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        const PleyaLogo(size: 88),
                        const SizedBox(height: 16),
                        Text(appName, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: .bold)),
                        const SizedBox(height: 8),
                        Text(
                          t.about.versionLabel(version: appVersion),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          t.about.appDescription,
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Developer + attribution + GPL notice (licence requirement)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Developed by BuildMind.\n\n'
                        'Pleya is based on Plezy (© edde746) and is free software, '
                        'licensed under the GNU General Public License v3.0. '
                        'You may redistribute and modify it under those terms.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const AppIcon(Symbols.code_rounded, fill: 1),
                          title: Text(t.about.sourceCode),
                          subtitle: Text(t.about.sourceCodeDescription),
                          trailing: const AppIcon(Symbols.open_in_new_rounded, fill: 1),
                          onTap: () => _open(_sourceUrl),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const AppIcon(Symbols.fork_right_rounded, fill: 1),
                          title: Text(t.about.basedOnPlezy),
                          subtitle: Text(t.about.upstreamProject),
                          trailing: const AppIcon(Symbols.open_in_new_rounded, fill: 1),
                          onTap: () => _open(_upstreamUrl),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const AppIcon(Symbols.privacy_tip_rounded, fill: 1),
                          title: Text(t.about.privacyPolicy),
                          trailing: const AppIcon(Symbols.open_in_new_rounded, fill: 1),
                          onTap: () => _open(_privacyUrl),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Open Source Licenses
                  Card(
                    child: ListTile(
                      leading: const AppIcon(Symbols.description_rounded, fill: 1),
                      title: Text(t.about.openSourceLicenses),
                      subtitle: Text(t.about.viewLicensesDescription),
                      trailing: const AppIcon(Symbols.chevron_right_rounded, fill: 1),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const LicensesScreen()));
                      },
                    ),
                  ),

                  const SizedBox(height: 24),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }
}
