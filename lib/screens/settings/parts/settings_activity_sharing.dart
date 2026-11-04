/// Mijn activiteit delen: one row per server that carries the choice, on the
/// Privacy group of the TV page and of the phone's Geavanceerd page. A server
/// without `capabilities.item_activity` has no such route and no row.
part of '../settings_screen.dart';

mixin _SettingsActivitySharing<W extends StatefulWidget> on State<W> {
  final Map<String, ActivitySharingController> _activitySharing = {};

  /// What the rows draw. Called from a build: a server that just came online
  /// starts its read here, and one that left takes its row with it.
  List<ActivitySharingController> _syncActivitySharing(MultiServerProvider? servers) {
    final online = servers?.serverManager.onlineClients ?? const {};
    final clients = {
      for (final MapEntry(key: id, value: client) in online.entries)
        if (client is HouseholdActivityClient && client.capabilities.itemActivity) id: client,
    };
    _activitySharing.removeWhere((id, controller) {
      if (clients.containsKey(id)) return false;
      controller.dispose();
      return true;
    });
    for (final MapEntry(key: id, value: client) in clients.entries) {
      if (_activitySharing.containsKey(id)) continue;
      final controller = ActivitySharingController(client: client, serverName: client.serverName)
        ..addListener(_onActivitySharingChanged);
      _activitySharing[id] = controller;
      unawaited(controller.load());
    }
    return _activitySharing.values.toList(growable: false);
  }

  void _onActivitySharingChanged() {
    if (mounted) setState(() {});
  }

  String _activitySharingTitle(ActivitySharingController controller) {
    final name = controller.serverName;
    return _activitySharing.length > 1 && name != null
        ? t.settings.shareActivityServer(server: name)
        : t.settings.shareActivity;
  }

  Future<void> _toggleActivitySharing(ActivitySharingController controller) async {
    final saved = await controller.toggle();
    if (!saved && mounted) showErrorSnackBar(context, t.settings.shareActivitySaveFailed);
  }

  /// A switch on a value, or the row that tries the read again.
  Widget _buildActivitySharingRow(ActivitySharingController controller) {
    final value = controller.value;
    if (controller.unreadable) {
      return SettingNavigationTile(
        icon: Symbols.group_rounded,
        title: _activitySharingTitle(controller),
        trailingLabel: t.common.retry,
        trailingIcon: Symbols.refresh_rounded,
        onTap: () => unawaited(controller.load()),
      );
    }
    return SettingSwitchRow(
      value: value ?? false,
      onChanged: value == null ? null : (_) => unawaited(_toggleActivitySharing(controller)),
      icon: Symbols.group_rounded,
      title: _activitySharingTitle(controller),
      subtitle: t.settings.shareActivityDescription,
    );
  }

  TvMenuItem _tvActivitySharingItem(ActivitySharingController controller) {
    final value = controller.value;
    return TvMenuItem(
      // By position, not id: the row's automation instance is what a scenario
      // walks to, and a server's id differs per run.
      key: 'activity_sharing_${_activitySharing.values.toList().indexOf(controller)}',
      icon: Symbols.group_rounded,
      title: _activitySharingTitle(controller),
      value: controller.unreadable
          ? t.settings.shareActivityUnreadable
          : value == null
          ? null
          : (value ? t.common.on : t.common.off),
      toggled: value,
      onSelect: controller.unreadable
          ? () => unawaited(controller.load())
          : () => unawaited(_toggleActivitySharing(controller)),
    );
  }

  @override
  void dispose() {
    for (final controller in _activitySharing.values) {
      controller.dispose();
    }
    super.dispose();
  }
}
