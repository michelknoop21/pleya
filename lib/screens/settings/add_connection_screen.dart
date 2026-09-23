import 'package:flutter/material.dart';
import 'package:pleya/widgets/app_icon.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focusable_wrapper.dart';
import '../../focus/focus_memory_tracker.dart';
import '../../navigation/tv/tv_nested_surface.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_backend.dart';
import '../../profiles/profile.dart';
import '../../widgets/backend_badge.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/tv/tv_menu_grid.dart';
import '../../widgets/tv/tv_page_surface.dart';
import '../../utils/platform_detector.dart';
import '../profile/borrow_connection_screen.dart';
import 'add_jellyfin_screen.dart';
import 'add_local_folder_screen.dart';
import 'add_pleya_server_screen.dart';
import 'add_plex_account_screen.dart';
import 'pleya_share_join_screen.dart';

/// Picker shown when the user taps "Add connection".
///
/// When [targetProfile] is provided, also offers a "Borrow from another
/// profile" option that opens [BorrowConnectionScreen] for the target. The
/// global Connections screen invokes this without a target — Plex auto-
/// surfaces its Home users as new profiles, Jellyfin binds to the active
/// profile via [AddJellyfinScreen].
///
/// Pops with `true` after the underlying flow succeeds so the parent list
/// refreshes; pops with `null` (the default) when the user backs out.
class AddConnectionScreen extends StatefulWidget {
  final Profile? targetProfile;

  const AddConnectionScreen({super.key, this.targetProfile});

  @override
  State<AddConnectionScreen> createState() => _AddConnectionScreenState();
}

class _AddConnectionScreenState extends State<AddConnectionScreen> {
  final FocusMemoryTracker _nodes = FocusMemoryTracker(debugLabelPrefix: 'addConnection');

  @override
  void dispose() {
    _nodes.dispose();
    super.dispose();
  }

  Future<void> _openOption(WidgetBuilder builder) async {
    final added = await Navigator.push<bool>(context, MaterialPageRoute(builder: builder));
    if (added != true || !mounted) return;
    final nested = TvNestedRouteScope.readOf(context);
    if (nested != null) {
      nested.dismiss(true);
    } else {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final targetProfile = widget.targetProfile;
    final scoped = targetProfile != null;
    final options = <_BackendOption>[
      _BackendOption(
        key: 'plex',
        tvIcon: Symbols.play_arrow_rounded,
        backend: MediaBackend.plex,
        title: t.addServer.signInWithPlexCard,
        subtitle: scoped ? t.addServer.signInWithPlexCardSubtitleScoped : t.addServer.signInWithPlexCardSubtitle,
        builder: (_) => AddPlexAccountScreen(targetProfile: targetProfile),
      ),
      _BackendOption(
        key: 'jellyfin',
        tvIcon: Symbols.tv_rounded,
        backend: MediaBackend.jellyfin,
        title: t.addServer.connectToJellyfinCard,
        subtitle: scoped
            ? t.addServer.connectToJellyfinCardSubtitleScoped(name: targetProfile.displayName)
            : t.addServer.connectToJellyfinCardSubtitle,
        builder: (_) => AddJellyfinScreen(targetProfile: targetProfile),
      ),
      _BackendOption(
        key: 'pleya_server',
        tvIcon: Symbols.dns_rounded,
        backend: MediaBackend.pleyaServer,
        title: t.addServer.connectToPleyaServerCard,
        subtitle: scoped
            ? t.addServer.connectToPleyaServerCardSubtitleScoped(name: targetProfile.displayName)
            : t.addServer.connectToPleyaServerCardSubtitle,
        builder: (_) => AddPleyaServerScreen(targetProfile: targetProfile),
      ),
      _BackendOption(
        key: 'local_folder',
        tvIcon: Symbols.folder_rounded,
        backend: MediaBackend.local,
        title: t.addLocalFolder.cardTitle,
        subtitle: t.addLocalFolder.cardSubtitle,
        builder: (_) => AddLocalFolderScreen(targetProfile: targetProfile),
      ),
      _BackendOption(
        key: 'pleya_share',
        tvIcon: Symbols.devices_rounded,
        backend: MediaBackend.local,
        title: t.pleyaShare.cardTitle,
        subtitle: t.pleyaShare.cardSubtitle,
        builder: (_) => PleyaShareJoinScreen(targetProfile: targetProfile),
        icon: Symbols.devices_rounded,
      ),
    ];
    if (PlatformDetector.isTV()) {
      return TvPageSurface(
        title: t.addServer.addConnectionTitle,
        automationInstance: 'add_connection',
        children: [
          TvMenuGrid(
            nodes: _nodes,
            columns: 2,
            automationInstance: 'add_connection',
            sections: [
              TvMenuSection(
                label: scoped ? t.addServer.addConnectionTitleScoped(name: targetProfile.displayName) : null,
                items: [
                  for (final option in options)
                    TvMenuItem(
                      key: option.key,
                      icon: option.tvIcon,
                      title: option.title,
                      subtitle: option.subtitle,
                      onSelect: () => _openOption(option.builder),
                    ),
                  if (scoped)
                    TvMenuItem(
                      key: 'borrow',
                      icon: Symbols.share_rounded,
                      title: t.addServer.borrowFromAnotherProfile,
                      subtitle: t.addServer.borrowFromAnotherProfileSubtitle,
                      onSelect: () => _openOption((_) => BorrowConnectionScreen(targetProfile: targetProfile)),
                    ),
                ],
              ),
            ],
          ),
        ],
      );
    }
    return FocusedScrollScaffold(
      title: Text(
        scoped ? t.addServer.addConnectionTitleScoped(name: targetProfile.displayName) : t.addServer.addConnectionTitle,
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _BackendCard(
                  leading: options[i].icon != null
                      ? AppIcon(options[i].icon!, fill: 1, size: 28)
                      : BackendBadge(backend: options[i].backend, size: 28),
                  title: options[i].title,
                  subtitle: options[i].subtitle,
                  onTap: () => _openOption(options[i].builder),
                ),
              ],
              if (scoped) ...[
                const SizedBox(height: 12),
                _BackendCard(
                  leading: const AppIcon(Symbols.share_rounded, fill: 1, size: 28),
                  title: t.addServer.borrowFromAnotherProfile,
                  subtitle: t.addServer.borrowFromAnotherProfileSubtitle,
                  onTap: () => _openOption((_) => BorrowConnectionScreen(targetProfile: targetProfile)),
                ),
              ],
            ]),
          ),
        ),
      ],
    );
  }
}

class _BackendOption {
  final String key;
  final IconData tvIcon;
  final MediaBackend backend;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;

  /// Overrides the backend badge — used by Pleya Share, which shares
  /// [MediaBackend.local] but needs its own visual identity in this picker.
  final IconData? icon;

  const _BackendOption({
    required this.key,
    required this.tvIcon,
    required this.backend,
    required this.title,
    required this.subtitle,
    required this.builder,
    this.icon,
  });
}

class _BackendCard extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _BackendCard({required this.leading, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusableWrapper(
      disableScale: true,
      borderRadius: 12,
      descendantsAreFocusable: false,
      onSelect: onTap,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                const AppIcon(Symbols.chevron_right_rounded, fill: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
