import 'package:flutter/material.dart';

import '../../services/settings_service.dart';
import '../../widgets/settings_builder.dart';
import 'mobile_tab_bar.dart';

/// The phone/iPad shell around the tab roots: [body], the optional offline
/// [reconnectStrip] and the [tabBar] under it.
///
/// Rebuilds on the Liquid Glass toggle. With glass on ([mobileTabBarFloats])
/// the body runs under the floating bar (`extendBody`), and the Scaffold
/// hands the bar's height to the tab roots as `MediaQuery` bottom padding;
/// the reconnect strip then floats too, as a pill with the capsule's side
/// margins. With glass off this is the Scaffold `MainScreen` always had.
class MobileMainScaffold extends StatelessWidget {
  const MobileMainScaffold({super.key, required this.body, required this.tabBar, this.reconnectStrip});

  final Widget body;
  final Widget tabBar;
  final Widget? reconnectStrip;

  @override
  Widget build(BuildContext context) {
    return SettingValueBuilder<bool>(
      pref: SettingsService.liquidGlass,
      builder: (context, _, _) {
        final floats = mobileTabBarFloats(context);
        final strip = reconnectStrip;
        return Scaffold(
          extendBody: floats,
          body: body,
          bottomNavigationBar: Column(
            mainAxisSize: .min,
            children: [
              if (strip != null)
                floats
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: ClipPath(
                          clipper: const ShapeBorderClipper(shape: StadiumBorder()),
                          child: strip,
                        ),
                      )
                    : strip,
              tabBar,
            ],
          ),
        );
      },
    );
  }
}
