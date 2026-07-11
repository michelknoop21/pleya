import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/focusable_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../services/saf_storage_service.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../connection/connection.dart';
import '../../profiles/profile.dart';
import '../../profiles/profile_connection.dart';
import '../../services/multi_server_manager.dart';
import 'connection_persistence.dart';

/// Screen for adding a local folder as a media source.
///
/// The user picks a directory via SAF (Android), gives it a name, and selects
/// a library type (Movies / TV Shows / Mixed). The connection is persisted
/// and bound to the active profile.
class AddLocalFolderScreen extends StatefulWidget {
  final Profile? targetProfile;

  const AddLocalFolderScreen({super.key, this.targetProfile});

  @override
  State<AddLocalFolderScreen> createState() => _AddLocalFolderScreenState();
}

class _AddLocalFolderScreenState extends State<AddLocalFolderScreen> {
  String? _directoryUri;
  String _displayName = '';
  String _libraryType = 'movies';
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusedScrollScaffold(
      title: Text(t.addLocalFolder.title),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Text(
                t.addLocalFolder.description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 24),

              // Library type selector
              Text(t.addLocalFolder.libraryType, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _LibraryTypeChip(
                label: t.addLocalFolder.typeMovies,
                selected: _libraryType == 'movies',
                onTap: () => setState(() => _libraryType = 'movies'),
              ),
              _LibraryTypeChip(
                label: t.addLocalFolder.typeTvShows,
                selected: _libraryType == 'tvshows',
                onTap: () => setState(() => _libraryType = 'tvshows'),
              ),
              _LibraryTypeChip(
                label: t.addLocalFolder.typeMixed,
                selected: _libraryType == 'mixed',
                onTap: () => setState(() => _libraryType = 'mixed'),
              ),
              const SizedBox(height: 24),

              // Directory picker
              Text(t.addLocalFolder.directory, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              FocusableWrapper(
                disableScale: true,
                borderRadius: 12,
                onSelect: _pickDirectory,
                child: Material(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: _pickDirectory,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            Symbols.folder_open_rounded,
                            fill: 1,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _directoryUri ?? t.addLocalFolder.chooseDirectory,
                              style: theme.textTheme.bodyMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Display name
              Text(t.addLocalFolder.nameLabel, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  hintText: t.addLocalFolder.nameHint,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _displayName = value),
              ),
              const SizedBox(height: 32),

              // Save button
              FilledButton.icon(
                onPressed: _canSave() ? _save : null,
                icon: const Icon(Symbols.check_rounded, fill: 1),
                label: Text(t.addLocalFolder.save),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  bool _canSave() => _directoryUri != null && _displayName.trim().isNotEmpty && !_saving;

  Future<void> _pickDirectory() async {
    final uri = await SafStorageService.instance.pickDirectory();
    if (uri != null) {
      setState(() {
        _directoryUri = uri;
        if (_displayName.isEmpty) {
          _displayName = 'Local Folder';
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_canSave()) return;
    setState(() => _saving = true);
    try {
      final id = 'local-${DateTime.now().millisecondsSinceEpoch}';
      final connection = LocalFolderConnection(
        id: id,
        directoryUri: _directoryUri!,
        displayName: _displayName.trim(),
        libraryType: _libraryType,
        createdAt: DateTime.now(),
      );

      final profile = widget.targetProfile;
      final bindToProfile = profile != null
          ? ProfileConnection(profileId: profile.id, connectionId: connection.id, userIdentifier: connection.id)
          : null;

      final added = await persistAndBindConnection(
        context: context,
        connection: connection,
        bindToProfile: bindToProfile,
        addToManager: () async {
          final manager = context.read<MultiServerManager>();
          return manager.addLocalSource(connection);
        },
        visibleServerId: connection.id,
      );

      if (added && mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.addLocalFolder.saveError)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _LibraryTypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LibraryTypeChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FocusableWrapper(
        disableScale: true,
        borderRadius: 12,
        onSelect: onTap,
        child: Material(
          color: selected ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 20,
                    color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 12),
                  Text(label, style: theme.textTheme.bodyLarge),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}