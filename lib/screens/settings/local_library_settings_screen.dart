import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_screen.dart';
import '../../i18n/strings.g.dart';
import '../../providers/local_library_provider.dart';
import '../../widgets/settings_page.dart';
import 'local_library_rows.dart';

class LocalLibrarySettingsScreen extends StatefulWidget {
  const LocalLibrarySettingsScreen({super.key});
  @override
  State<LocalLibrarySettingsScreen> createState() => _LocalLibrarySettingsScreenState();
}

class _LocalLibrarySettingsScreenState extends State<LocalLibrarySettingsScreen>
    with LocalLibraryRowsHost<LocalLibrarySettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LocalLibraryProvider>();
    return AutomationScreen(
      id: AutomationIds.screenLocalLibrary,
      readiness: () => provider.initialized ? const AutomationReadiness.ready() : const AutomationReadiness.loading(),
      child: SettingsPage(title: Text(t.localLibrary.title), children: buildLocalLibraryRows(provider)),
    );
  }
}
