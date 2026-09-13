import 'dart:io';

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../services/download_storage_service.dart';
import '../../services/file_picker_service.dart';
import '../../services/saf_storage_service.dart';
import '../../services/settings_service.dart' as settings;
import '../../utils/dialogs.dart';
import '../../utils/platform_detector.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/dialog_action_button.dart';

/// The download-location picker: current path, "select folder", and (when a
/// custom path is set) "reset to default". Shared by the TV settings menu
/// (its own dialog-driven row) and [DownloadsSettingsScreen] (a screen row on
/// mobile/desktop) — one flow, two entry points, not two implementations.
/// Calls [onChanged] after a change or reset so the caller can `setState`.
Future<void> showDownloadLocationDialog(BuildContext context, {required VoidCallback onChanged}) async {
  final storageService = DownloadStorageService.instance;
  final isCustom = storageService.isUsingCustomPath();

  await showScopedDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(t.settings.downloads),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.settings.downloadLocationDescription),
          const SizedBox(height: 16),
          FutureBuilder<String>(
            future: storageService.getCurrentDownloadPathDisplay(),
            builder: (context, snapshot) {
              return Text(
                t.settings.currentPath(path: snapshot.data ?? '...'),
                style: Theme.of(context).textTheme.bodySmall,
              );
            },
          ),
        ],
      ),
      actions: [
        if (isCustom)
          DialogActionButton(
            onPressed: () async {
              // Run the async work first, then pop — popping first leaves
              // the reset racing against the already-dismissed dialog (and
              // any re-opened instance).
              await _resetDownloadLocation(context, onChanged: onChanged);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            label: t.settings.resetToDefault,
          ),
        DialogActionButton(onPressed: () => Navigator.pop(dialogContext), label: t.common.cancel),
        DialogActionButton(
          onPressed: () async {
            await _selectDownloadLocation(context, onChanged: onChanged);
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
          label: t.settings.selectFolder,
          isPrimary: true,
        ),
      ],
    ),
  );
}

Future<void> _selectDownloadLocation(BuildContext context, {required VoidCallback onChanged}) async {
  final settingsService = settings.SettingsService.instance;
  try {
    String? selectedPath;
    String pathType = 'file';

    if (Platform.isAndroid) {
      final safService = SafStorageService.instance;
      selectedPath = await safService.pickDirectory();
      if (selectedPath != null) {
        pathType = 'saf';
      } else if (PlatformDetector.isTV()) {
        if (context.mounted) showErrorSnackBar(context, t.settings.downloadLocationSelectError);
        return;
      }
    } else {
      selectedPath = await FilePickerService.instance.getDirectoryPath(dialogTitle: t.settings.selectFolder);
    }

    if (selectedPath != null) {
      if (pathType == 'file') {
        final dir = Directory(selectedPath);
        final isWritable = await DownloadStorageService.instance.isDirectoryWritable(dir);
        if (!isWritable) {
          if (context.mounted) showErrorSnackBar(context, t.settings.downloadLocationInvalid);
          return;
        }
      }

      await settingsService.write(settings.SettingsService.customDownloadPath, selectedPath);
      await settingsService.write(settings.SettingsService.customDownloadPathType, pathType);
      await DownloadStorageService.instance.refreshCustomPath();

      if (context.mounted) {
        onChanged();
        showSuccessSnackBar(context, t.settings.downloadLocationChanged);
      }
    }
  } catch (e) {
    if (context.mounted) showErrorSnackBar(context, t.settings.downloadLocationSelectError);
  }
}

Future<void> _resetDownloadLocation(BuildContext context, {required VoidCallback onChanged}) async {
  final settingsService = settings.SettingsService.instance;
  await settingsService.write(settings.SettingsService.customDownloadPath, null);
  await settingsService.write(settings.SettingsService.customDownloadPathType, null);
  await DownloadStorageService.instance.refreshCustomPath();

  if (context.mounted) {
    onChanged();
    showAppSnackBar(context, t.settings.downloadLocationReset);
  }
}
