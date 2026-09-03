import 'dart:io';
import '../../media/ids.dart';

import 'package:flutter/material.dart';
import '../../utils/future_extensions.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../mixins/mounted_set_state_mixin.dart';
import '../../focus/focusable_button.dart';
import '../../focus/focus_memory_tracker.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/tv/tv_menu_grid.dart';
import '../../widgets/tv/tv_page_surface.dart';
import '../../widgets/tv/tv_unified_layout.dart';
import '../../focus/focusable_text_field.dart';
import '../../focus/focusable_wrapper.dart';
import '../../profiles/active_profile_provider.dart';
import '../../services/settings_service.dart';
import '../../utils/app_logger.dart';
import '../../utils/dialogs.dart';
import '../../utils/error_message_utils.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/notice/notice_controller.dart';
import '../../widgets/dialog_action_button.dart';
import '../../utils/video_player_navigation.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/app_menu.dart';
import '../../widgets/overlay_sheet.dart';
import '../models/watch_session.dart';
import '../providers/watch_together_provider.dart';
import '../services/recent_rooms_service.dart';
import '../services/watch_together_peer_service.dart';
import '../widgets/join_session_dialog.dart';
import '../../widgets/loading_indicator_box.dart';

class WatchTogetherScreen extends StatelessWidget {
  const WatchTogetherScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<WatchTogetherProvider>(
      builder: (context, watchTogether, child) {
        final canGoBack = watchTogether.isHost || !watchTogether.isInSession;
        // The host owns sheet + system back: a back with the actions sheet open
        // closes it; otherwise the route pops only when [canGoBack] (a guest in
        // an active session can't leave). canGoBack==true also preserves the iOS
        // interactive swipe-back.
        // The TV branch is here, above the sliver scaffold, and not one level
        // down inside [_NotInSessionView] where the presentation lives.
        //
        // That is not a stylistic preference. `SliverFillRemaining` hands its
        // child the viewport's remaining extent, and a `TvPageSurface` is a
        // `SingleChildScrollView`: nesting one inside the scaffold's own
        // scrollable gives the page no height to lay out in. The first attempt
        // did exactly that and the evidence was unambiguous — the section's
        // node was registered in `/v1/ui_tree` and reported no bounds at all.
        // So on TV the shell's scaffold is not built; the page is the scroll.
        //
        // Only the not-in-session half branches. The active session keeps the
        // shared presentation: it was not part of the audit of 2 September and
        // has no approved TV layout, and a page that is mostly a participant
        // list and two destructive buttons is not improved by guessing at one.
        if (PlatformDetector.isTV() && !watchTogether.isInSession) {
          return OverlaySheetHost(
            canPop: canGoBack,
            child: _NotInSessionView(watchTogether: watchTogether),
          );
        }

        return OverlaySheetHost(
          canPop: canGoBack,
          child: FocusedScrollScaffold(
            title: Text(t.watchTogether.title),
            automaticallyImplyLeading: canGoBack,
            slivers: watchTogether.isInSession
                ? _buildActiveSessionSlivers(watchTogether)
                : [SliverFillRemaining(hasScrollBody: false, child: _NotInSessionView(watchTogether: watchTogether))],
          ),
        );
      },
    );
  }

  List<Widget> _buildActiveSessionSlivers(WatchTogetherProvider watchTogether) {
    return [
      SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: _ActiveSessionContent(watchTogether: watchTogether),
            ),
          ),
        ),
      ),
    ];
  }
}

/// View shown when not in a session
class _NotInSessionView extends StatefulWidget {
  final WatchTogetherProvider watchTogether;

  const _NotInSessionView({required this.watchTogether});

  @override
  State<_NotInSessionView> createState() => _NotInSessionViewState();
}

class _NotInSessionViewState extends State<_NotInSessionView> with MountedSetStateMixin {
  bool _isCreating = false;
  bool _isJoining = false;
  String? _enteringRoomCode;
  bool? _healthOk;
  String? _customRelayUrl;
  List<RecentRoom> _recentRooms = [];

  /// Owned by the State, not rebuilt per frame: the health check and every
  /// room mutation call `setState`, and a node rebuilt underneath the remote
  /// is a remote that lands nowhere.
  final FocusMemoryTracker _nodes = FocusMemoryTracker(debugLabelPrefix: 'tvWatchTogether');

  @override
  void dispose() {
    _nodes.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _customRelayUrl = SettingsService.instanceOrNull?.read(SettingsService.customRelayUrl);
    _recentRooms = RecentRoomsService.getRecentRooms();
    _checkHealth();
  }

  bool get _isBusy => _isCreating || _isJoining || _enteringRoomCode != null;

  String? get _plexDisplayName => context.read<ActiveProfileProvider>().active?.displayName;

  Future<void> _checkHealth() async {
    final client = HttpClient();
    try {
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(Uri.parse(WatchTogetherPeerService.healthUrlFor(_customRelayUrl)));
      final response = await request.close().namedTimeout(
        const Duration(seconds: 5),
        operation: 'WatchTogether health check',
      );
      final body = await response.transform(const SystemEncoding().decoder).join();
      if (!mounted) return;
      setState(() => _healthOk = response.statusCode == 200 && body.trim() == 'ok');
    } catch (e) {
      appLogger.w('Watch Together health check failed', error: e);
      if (!mounted) return;
      setState(() => _healthOk = false);
    } finally {
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (PlatformDetector.isTV()) return _buildTv(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: .min,
            children: [
              Icon(Symbols.group_rounded, size: 80, color: theme.colorScheme.primary),
              const SizedBox(height: 24),
              Text(t.watchTogether.title, style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                t.watchTogether.description,
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              if (_healthOk == false) ...[
                const SizedBox(height: 24),
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Symbols.warning_rounded, color: theme.colorScheme.onErrorContainer),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            t.watchTogether.relayUnreachable,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: FocusableButton(
                  autofocus: _recentRooms.isEmpty,
                  onPressed: _isBusy ? null : _createSession,
                  child: FilledButton.icon(
                    onPressed: _isBusy ? null : _createSession,
                    icon: _isCreating ? const LoadingIndicatorBox(size: 20) : const Icon(Symbols.add_rounded),
                    label: Text(_isCreating ? t.watchTogether.creating : t.watchTogether.createSession),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FocusableButton(
                  onPressed: _isBusy ? null : _joinSession,
                  child: OutlinedButton.icon(
                    onPressed: _isBusy ? null : _joinSession,
                    icon: _isJoining ? const LoadingIndicatorBox(size: 20) : const Icon(Symbols.group_add_rounded),
                    label: Text(_isJoining ? t.watchTogether.joining : t.watchTogether.joinSession),
                  ),
                ),
              ),
              if (_recentRooms.isNotEmpty) ...[
                const SizedBox(height: 32),
                Align(
                  alignment: .centerLeft,
                  child: Text(t.watchTogether.recentRooms, style: theme.textTheme.titleSmall),
                ),
                const SizedBox(height: 8),
                ..._recentRooms.map(
                  (room) => _RecentRoomTile(
                    room: room,
                    isBusy: _isBusy,
                    isEntering: _enteringRoomCode == room.code,
                    onTap: () => _enterRoom(room),
                    onRename: () => _renameRoom(room),
                    onRemove: () => _removeRoom(room),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The approved `watch-together-a` page.
  ///
  /// What the audit measured here was a phone screen blown up: the shell's own
  /// heading, then a second centred one under it, then two buttons a third of
  /// the screen wide floating in the middle of 1080 lines. On TV the eye starts
  /// top left, which is where every other page in this product starts.
  ///
  /// So the second heading goes, the description becomes the group label above
  /// the actions it describes, and the two actions become tiles on the
  /// canonical page edge. Recent rooms are the same rooms the mobile list has
  /// always shown, in the tile language and with the same held-SELECT menu
  /// behind them; when there are none the page says so rather than ending.
  Widget _buildTv(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final tk = tokens(context);

    return TvPageSurface(
      title: t.watchTogether.title,
      automationInstance: 'watch_together',
      children: [
        if (_healthOk == false) ...[
          TvPageBlock(
            child: Row(
              crossAxisAlignment: .start,
              children: [
                // The theme maps every container colour onto the surface
                // underneath it (DEC-053), so an `errorContainer` card would
                // be a rectangle nobody can see. The glyph carries the warning.
                Icon(
                  Symbols.warning_rounded,
                  size: TvMyPleyaLayout.tileIconSize * scale,
                  color: Theme.of(context).colorScheme.error,
                ),
                SizedBox(width: TvMyPleyaLayout.tilePadding * scale),
                Expanded(
                  child: Text(
                    t.watchTogether.relayUnreachable,
                    style: tvPageBodyStyle(context, alpha: TvMyPleyaLayout.inkSecondary),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: TvMyPleyaLayout.groupGap * scale),
        ],
        TvMenuGrid(
          nodes: _nodes,
          columns: 2,
          automationInstance: 'watch_together',
          sections: [
            TvMenuSection(
              label: t.watchTogether.description,
              items: [
                TvMenuItem(
                  key: 'watch_together_create',
                  icon: Symbols.add_rounded,
                  title: _isCreating ? t.watchTogether.creating : t.watchTogether.createSession,
                  subtitle: t.watchTogether.createSessionHint,
                  onSelect: _isBusy ? null : _createSession,
                ),
                TvMenuItem(
                  key: 'watch_together_join',
                  icon: Symbols.group_add_rounded,
                  title: _isJoining ? t.watchTogether.joining : t.watchTogether.joinSession,
                  subtitle: t.watchTogether.joinSessionHint,
                  onSelect: _isBusy ? null : _joinSession,
                ),
              ],
            ),
            if (_recentRooms.isNotEmpty)
              TvMenuSection(
                label: t.watchTogether.recentRooms,
                items: [
                  for (final room in _recentRooms)
                    TvMenuItem(
                      key: _tvRoomKey(room),
                      icon: Symbols.meeting_room_rounded,
                      title: room.name ?? room.code,
                      // A named room still has to show the code, because the
                      // code is what a viewer reads out to whoever is joining.
                      value: _enteringRoomCode == room.code
                          ? t.watchTogether.joining
                          : (room.name == null ? null : room.code),
                      onSelect: _isBusy ? null : () => _enterRoom(room),
                      onLongPress: () => showRecentRoomActions(
                        context,
                        onRename: () => _renameRoom(room),
                        onRemove: () => _removeRoom(room),
                      ),
                    ),
                ],
              ),
          ],
        ),
        if (_recentRooms.isEmpty) ...[
          SizedBox(height: TvMyPleyaLayout.groupGap * scale),
          TvPageGroupLabel(t.watchTogether.recentRooms),
          TvPageBlock(
            child: Column(
              crossAxisAlignment: .start,
              mainAxisSize: .min,
              children: [
                Text(
                  t.watchTogether.noRecentRooms,
                  style: TextStyle(
                    color: tk.text,
                    fontSize: TvMyPleyaLayout.tileTitleFontSize * scale,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: TvMyPleyaLayout.tileTitleSubtitleGap * scale),
                Text(t.watchTogether.noRecentRoomsHint, style: tvPageBodyStyle(context)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _createSession() async {
    final controlMode = await _showControlModeDialog();
    if (controlMode == null || !mounted) return;

    setState(() => _isCreating = true);

    try {
      final sessionId = await widget.watchTogether.createSession(
        controlMode: controlMode,
        displayName: _plexDisplayName,
      );
      await RecentRoomsService.addOrUpdateRoom(sessionId, controlMode: controlMode);
      setStateIfMounted(() => _recentRooms = RecentRoomsService.getRecentRooms());
    } catch (e) {
      if (mounted) {
        noticeController.show(noticeForError(e, context: t.watchTogether.failedToCreate));
      } else {
        appLogger.e('Failed to create session', error: e);
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  Future<ControlMode?> _showControlModeDialog() {
    return showScopedDialog<ControlMode>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.watchTogether.controlMode),
        content: Text(t.watchTogether.controlModeQuestion),
        actions: [
          DialogActionButton(onPressed: () => Navigator.pop(context), label: t.common.cancel),
          DialogActionButton(
            onPressed: () => Navigator.pop(context, ControlMode.hostOnly),
            label: t.watchTogether.hostOnly,
          ),
          DialogActionButton(
            onPressed: () => Navigator.pop(context, ControlMode.anyone),
            label: t.watchTogether.anyone,
            isPrimary: true,
          ),
        ],
      ),
    );
  }

  Future<void> _joinSession() async {
    final sessionId = await showJoinSessionDialog(context);
    if (sessionId == null || !mounted) return;

    setState(() => _isJoining = true);

    try {
      await widget.watchTogether.joinSession(sessionId, displayName: _plexDisplayName);
      await RecentRoomsService.addOrUpdateRoom(sessionId);
      setStateIfMounted(() => _recentRooms = RecentRoomsService.getRecentRooms());
    } catch (e) {
      if (mounted) {
        noticeController.show(noticeForError(e, context: t.watchTogether.failedToJoin));
      } else {
        appLogger.e('Failed to join session', error: e);
      }
    } finally {
      if (mounted) {
        setState(() => _isJoining = false);
      }
    }
  }

  Future<void> _enterRoom(RecentRoom room) async {
    setState(() => _enteringRoomCode = room.code);

    try {
      await widget.watchTogether.enterRoom(
        room.code,
        controlMode: room.controlMode ?? ControlMode.anyone,
        displayName: _plexDisplayName,
      );
      await RecentRoomsService.addOrUpdateRoom(room.code);
      setStateIfMounted(() => _recentRooms = RecentRoomsService.getRecentRooms());
    } catch (e) {
      if (mounted) {
        noticeController.show(noticeForError(e, context: t.watchTogether.failedToJoin));
      } else {
        appLogger.e('Failed to enter room', error: e);
      }
    } finally {
      if (mounted) {
        setState(() => _enteringRoomCode = null);
      }
    }
  }

  Future<void> _renameRoom(RecentRoom room) async {
    final name = await showScopedDialog<String>(
      context: context,
      builder: (_) => _RenameRoomDialog(room: room),
    );
    if (name == null || !mounted) return;

    await RecentRoomsService.renameRoom(room.code, name.isEmpty ? null : name);
    setStateIfMounted(() => _recentRooms = RecentRoomsService.getRecentRooms());
  }

  Future<void> _removeRoom(RecentRoom room) async {
    // The remote is very likely standing on this tile: forgetting a room is
    // reached by holding SELECT on it. Losing the widget under a focused node
    // hands primary focus back to the enclosing scope, which leaves the page
    // focused with no item on it — `FocusMemoryTracker.pruneExcept` carries
    // the same warning, and `side_navigation_rail.dart` recovers from it the
    // same way: work out where focus should land before the list changes.
    final survivor = _recentRooms.where((r) => r.code != room.code).firstOrNull;

    await RecentRoomsService.removeRoom(room.code);
    setStateIfMounted(() => _recentRooms = RecentRoomsService.getRecentRooms());
    if (!mounted || !PlatformDetector.isTV()) return;

    _nodes.pruneExcept({for (final r in _recentRooms) _tvRoomKey(r), 'watch_together_create', 'watch_together_join'});

    // Unconditionally, not "only if that tile still held the focus". The menu
    // that reaches this method is an overlay sheet, and opening it already
    // moved the focus off the tile, so asking afterwards always answers no.
    // The viewer is demonstrably on this page and just acted on this tile:
    // the next room along, or the first action when that was the last one.
    final target = survivor == null ? 'watch_together_create' : _tvRoomKey(survivor);
    final node = _nodes.get(target);
    if (node.canRequestFocus) node.requestFocus();
  }

  static String _tvRoomKey(RecentRoom room) => 'watch_together_room_${room.code}';
}

class _RenameRoomDialog extends StatefulWidget {
  final RecentRoom room;

  const _RenameRoomDialog({required this.room});

  @override
  State<_RenameRoomDialog> createState() => _RenameRoomDialogState();
}

class _RenameRoomDialogState extends State<_RenameRoomDialog> {
  late final _controller = TextEditingController(text: widget.room.name ?? '');
  final _fieldFocusNode = FocusNode(debugLabel: 'WatchTogetherRenameField');
  final _cancelFocusNode = FocusNode(debugLabel: 'WatchTogetherRenameCancel');
  final _saveFocusNode = FocusNode(debugLabel: 'WatchTogetherRenameSave');

  @override
  void dispose() {
    _fieldFocusNode.dispose();
    _cancelFocusNode.dispose();
    _saveFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _submit(String value) {
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.watchTogether.renameRoom),
      content: FocusableTextField(
        controller: _controller,
        focusNode: _fieldFocusNode,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.room.code),
        onNavigateDown: _saveFocusNode.requestFocus,
        onSubmitted: _submit,
      ),
      actions: [
        DialogActionButton(
          focusNode: _cancelFocusNode,
          onPressed: () => Navigator.pop(context),
          onNavigateRight: _saveFocusNode.requestFocus,
          label: t.common.cancel,
        ),
        DialogActionButton(
          focusNode: _saveFocusNode,
          onPressed: () => _submit(_controller.text),
          onNavigateLeft: _cancelFocusNode.requestFocus,
          isPrimary: true,
          label: t.common.save,
        ),
      ],
    );
  }
}

class _RecentRoomTile extends StatelessWidget {
  final RecentRoom room;
  final bool isBusy;
  final bool isEntering;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  const _RecentRoomTile({
    required this.room,
    required this.isBusy,
    required this.isEntering,
    required this.onTap,
    required this.onRename,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = room.name ?? room.code;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: FocusableWrapper(
        mode: FocusIndicatorMode.fill,
        borderRadius: 12,
        // Hold SELECT/OK to open the rename/remove menu on TV/dpad (matches media cards).
        enableLongPress: true,
        // The wrapper owns key handling; the ListTile's InkWell and the trailing
        // more_vert IconButton must not steal focus from the long-press handler.
        descendantsAreFocusable: false,
        onSelect: isBusy ? null : onTap,
        onLongPress: () => _showActions(context),
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
            leading: isEntering ? const LoadingIndicatorBox(size: 24) : const Icon(Symbols.meeting_room_rounded),
            title: Text(title, maxLines: 1, overflow: .ellipsis),
            subtitle: room.name != null
                ? Text(
                    room.code,
                    style: TextStyle(fontFamily: 'monospace', color: theme.colorScheme.onSurfaceVariant),
                  )
                : null,
            trailing: IconButton(icon: const Icon(Symbols.more_vert_rounded), onPressed: () => _showActions(context)),
            onTap: isBusy ? null : onTap,
          ),
        ),
      ),
    );
  }

  void _showActions(BuildContext context) => showRecentRoomActions(context, onRename: onRename, onRemove: onRemove);
}

/// Rename or forget a saved room. One definition, because the TV tile and the
/// mobile list tile offer the same two actions and one of them deletes.
void showRecentRoomActions(BuildContext context, {required VoidCallback onRename, required VoidCallback onRemove}) {
  OverlaySheetController.showAdaptive(
    context,
    builder: (context) => AppMenuSheet<String>(
      entries: [
        AppMenuItem(value: 'rename', icon: Symbols.edit_rounded, label: t.watchTogether.renameRoom),
        AppMenuItem(
          value: 'remove',
          icon: Symbols.delete_rounded,
          label: t.watchTogether.removeRoom,
          destructive: true,
        ),
      ],
      onSelected: (value) {
        if (value == 'rename') {
          onRename();
        } else if (value == 'remove') {
          onRemove();
        }
      },
    ),
  );
}

class _ActiveSessionContent extends StatelessWidget {
  final WatchTogetherProvider watchTogether;

  const _ActiveSessionContent({required this.watchTogether});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = watchTogether.session!;

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Row(
                  children: [
                    Icon(
                      watchTogether.isHost ? Symbols.star_rounded : Symbols.group_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: .start,
                        children: [
                          Text(
                            watchTogether.isHost ? t.watchTogether.hostingSession : t.watchTogether.inSession,
                            style: theme.textTheme.titleMedium,
                          ),
                          _SessionCodeRow(sessionId: session.sessionId),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      session.controlMode == ControlMode.anyone
                          ? Symbols.groups_rounded
                          : Symbols.admin_panel_settings_rounded,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      session.controlMode == ControlMode.anyone
                          ? t.watchTogether.anyoneCanControl
                          : t.watchTogether.hostControlsPlayback,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Row(
                  children: [
                    Icon(Symbols.people_rounded, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      '${t.watchTogether.participants} (${watchTogether.participantCount})',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...watchTogether.participants.map(
                  (participant) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          participant.isHost ? Symbols.star_rounded : Symbols.person_rounded,
                          size: 20,
                          color: participant.isHost ? Colors.amber : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Text(participant.displayName, style: theme.textTheme.bodyMedium),
                        if (participant.isHost) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              borderRadius: const BorderRadius.all(Radius.circular(12)),
                            ),
                            child: Text(
                              t.watchTogether.host,
                              style: theme.textTheme.labelSmall?.copyWith(color: Colors.amber.shade700),
                            ),
                          ),
                        ],
                        if (participant.isBuffering) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        if (!watchTogether.isHost && watchTogether.hasCurrentPlayback) ...[
          _JoinCurrentPlaybackCard(watchTogether: watchTogether),
          const SizedBox(height: 16),
        ],

        // Leave/End Session Button
        SizedBox(
          width: double.infinity,
          child: FocusableButton(
            autofocus: watchTogether.isHost || !watchTogether.hasCurrentPlayback,
            onPressed: () => _leaveSession(context),
            child: OutlinedButton.icon(
              onPressed: () => _leaveSession(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error),
              ),
              icon: Icon(watchTogether.isHost ? Symbols.close_rounded : Symbols.logout_rounded),
              label: Text(watchTogether.isHost ? t.watchTogether.endSession : t.watchTogether.leaveSession),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _leaveSession(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: watchTogether.isHost ? t.watchTogether.endSessionQuestion : t.watchTogether.leaveSessionQuestion,
      message: watchTogether.isHost ? t.watchTogether.endSessionConfirm : t.watchTogether.leaveSessionConfirm,
      confirmText: watchTogether.isHost ? t.watchTogether.end : t.watchTogether.leave,
      isDestructive: true,
    );

    if (confirmed) {
      await watchTogether.leaveSession();
    }
  }
}

class _JoinCurrentPlaybackCard extends StatefulWidget {
  final WatchTogetherProvider watchTogether;

  const _JoinCurrentPlaybackCard({required this.watchTogether});

  @override
  State<_JoinCurrentPlaybackCard> createState() => _JoinCurrentPlaybackCardState();
}

class _JoinCurrentPlaybackCardState extends State<_JoinCurrentPlaybackCard> {
  bool _isJoining = false;

  Future<void> _joinCurrentPlayback() async {
    final ratingKey = widget.watchTogether.currentMediaRatingKey;
    final serverId = widget.watchTogether.currentMediaServerId;
    if (ratingKey == null || serverId == null) return;

    setState(() => _isJoining = true);

    try {
      await navigateToWatchTogetherPlayback(
        context,
        ratingKey: ratingKey,
        serverId: ServerId(serverId),
        onBeforeNavigate: () {
          widget.watchTogether.markCurrentPlaybackHandled(ratingKey: ratingKey, serverId: ServerId(serverId));
        },
      );
    } catch (e, stackTrace) {
      appLogger.e('WatchTogether: Failed to open current playback', error: e, stackTrace: stackTrace);
      if (mounted) {
        showErrorSnackBar(context, t.watchTogether.failedToOpenCurrentPlayback);
      }
    } finally {
      if (mounted) {
        setState(() => _isJoining = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaTitle = widget.watchTogether.currentMediaTitle;
    if (widget.watchTogether.isHost || mediaTitle == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Row(
              children: [
                Icon(Symbols.play_circle_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: [
                      Text(t.watchTogether.currentPlayback, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        t.watchTogether.joinCurrentPlaybackDescription,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(mediaTitle, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FocusableButton(
                autofocus: true,
                onPressed: _isJoining ? null : _joinCurrentPlayback,
                child: FilledButton.icon(
                  onPressed: _isJoining ? null : _joinCurrentPlayback,
                  icon: _isJoining ? const LoadingIndicatorBox() : const Icon(Symbols.play_arrow_rounded),
                  label: Text(_isJoining ? t.watchTogether.joining : t.watchTogether.joinCurrentPlayback),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tappable session code row with copy functionality
class _SessionCodeRow extends StatelessWidget {
  final String sessionId;

  const _SessionCodeRow({required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FocusableWrapper(
      mode: FocusIndicatorMode.fill,
      disableScale: true,
      borderRadius: 4,
      onSelect: () => _copySessionCode(context),
      child: InkWell(
        onTap: () => _copySessionCode(context),
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: .min,
            children: [
              Text(
                '${t.watchTogether.sessionCode}: $sessionId',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Symbols.content_copy_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  void _copySessionCode(BuildContext context) {
    Clipboard.setData(ClipboardData(text: sessionId));
    showSnackBar(context, t.watchTogether.sessionCodeCopied);
  }
}
