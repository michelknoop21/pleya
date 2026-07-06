import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../providers/hidden_libraries_provider.dart';
import '../../providers/libraries_provider.dart';
import '../../utils/content_utils.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/settings_page.dart';

/// Lets the user pick which libraries appear in the navigation menu. Toggling a
/// switch off hides the library (persisted via [HiddenLibrariesProvider]); the
/// rail rebuilds and drops it from the pinned library items.
class LibraryVisibilityScreen extends StatelessWidget {
  const LibraryVisibilityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final libraries = context.watch<LibrariesProvider>().libraries;
    final hidden = context.watch<HiddenLibrariesProvider>();

    return SettingsPage(
      title: Text(t.settings.libraryVisibility),
      children: libraries.isEmpty
          ? [Padding(padding: const EdgeInsets.all(24), child: Text(t.libraries.noLibrariesFound))]
          : [
              for (final library in libraries)
                SwitchListTile(
                  secondary: AppIcon(ContentTypeHelper.getLibraryIcon(library.kind.id), fill: 1),
                  title: Text(library.title),
                  subtitle: library.serverName != null ? Text(library.serverName!) : null,
                  value: !hidden.isLibraryHidden(library.globalKey),
                  onChanged: (visible) =>
                      visible ? hidden.unhideLibrary(library.globalKey) : hidden.hideLibrary(library.globalKey),
                ),
            ],
    );
  }
}
