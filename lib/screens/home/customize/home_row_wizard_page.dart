/// The row wizard as its own full-height page on iPhone (mockup 44 G to J).
/// On iPad and Mac the wizard sits beside the list instead
/// (`HomeCustomizeScreen`).
library;

import 'package:flutter/material.dart';

import '../../../services/unified_catalog/home_custom_row.dart';
import '../../../services/unified_catalog/home_row_editing.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/platform_detector.dart';
import '../../../widgets/overlay_sheet.dart';
import 'home_row_wizard_view.dart';

/// Opens the wizard and returns the row to save, or null when the viewer backed
/// out. Nothing is written here; the caller owns the storage.
Future<HomeCustomRow?> showHomeRowWizardPage(
  BuildContext context, {
  required HomeRowEditing editing,
  HomeCustomRow? initial,
}) {
  return Navigator.of(context).push<HomeCustomRow>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (pageContext) => _HomeRowWizardPage(editing: editing, initial: initial),
    ),
  );
}

class _HomeRowWizardPage extends StatelessWidget {
  const _HomeRowWizardPage({required this.editing, this.initial});

  final HomeRowEditing editing;
  final HomeCustomRow? initial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: tokens(context).bg,
      body: SafeArea(
        // Its own host, as the filter sheets the wizard opens need one above
        // them and this route is a sibling of the screen that holds the other.
        child: OverlaySheetHost(
          canPop: PlatformDetector.isHandheldIOS(context),
          onSystemBack: () {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) navigator.pop();
          },
          child: HomeRowWizardView(
            editing: editing,
            initial: initial,
            onCancel: () => Navigator.of(context).pop(),
            onSave: (row) => Navigator.of(context).pop(row),
          ),
        ),
      ),
    );
  }
}
