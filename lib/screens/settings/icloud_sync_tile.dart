import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../services/icloud_sync_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/setting_tile.dart';

/// What the iCloud settings-sync tile should render for a given status.
///
/// Split out as a plain value so the availability contract can be asserted
/// without building a settings screen: the rule that a transport fault leaves
/// the control switched on is the whole point of the fix, and it is worth a
/// test that cannot rot behind a widget tree.
@immutable
class ICloudSyncTileState {
  final bool enabled;
  final String subtitle;

  const ICloudSyncTileState({required this.enabled, required this.subtitle});

  /// [status] null means the probe has not answered yet: stay enabled and show
  /// the ordinary description rather than flashing a problem the device may
  /// not have.
  factory ICloudSyncTileState.forStatus(ICloudSyncStatus? status) => switch (status) {
    null || ICloudSyncStatus.ok => ICloudSyncTileState(enabled: true, subtitle: t.settings.icloudSyncDescription),
    // Health, not availability. The store is reachable in principle, so
    // leaving the toggle on is the honest state; the subtitle carries the
    // problem instead of pretending nobody is signed in.
    ICloudSyncStatus.error => ICloudSyncTileState(enabled: true, subtitle: t.settings.icloudSyncError),
    ICloudSyncStatus.warning => ICloudSyncTileState(enabled: true, subtitle: t.settings.icloudSyncWarning),
    ICloudSyncStatus.signedOut => ICloudSyncTileState(enabled: false, subtitle: t.settings.icloudSyncUnavailable),
    ICloudSyncStatus.unsupported => ICloudSyncTileState(enabled: false, subtitle: t.settings.icloudSyncNotSupported),
  };
}

/// The iCloud settings-sync switch.
///
/// Apple-only, and that includes tvOS — an Apple TV reports itself as iOS and
/// carries the key-value-store entitlement, so it gets the tile like any other
/// Apple device. See [ICloudSyncStatus] for why availability and health are
/// tracked apart.
class ICloudSyncTile extends StatefulWidget {
  final FocusNode? focusNode;
  final Future<void> Function() onToggleFailed;

  const ICloudSyncTile({super.key, required this.onToggleFailed, this.focusNode});

  /// tvOS reports as iOS, so this covers iPhone, iPad, Apple TV and Mac.
  static bool get isPlatformSupported => Platform.isIOS || Platform.isMacOS;

  @override
  State<ICloudSyncTile> createState() => _ICloudSyncTileState();
}

class _ICloudSyncTileState extends State<ICloudSyncTile> {
  /// null until the first probe returns.
  ICloudSyncStatus? _status;

  /// Held rather than looked up again: the listener has to come off the same
  /// notifier it went on, whatever the singleton points at by then.
  ICloudSyncService? _service;

  @override
  void initState() {
    super.initState();
    final svc = _service = ICloudSyncService.instance;
    if (svc == null) return;
    svc.status.addListener(_onStatusChanged);
    unawaited(svc.isAvailable());
  }

  @override
  void dispose() {
    _service?.status.removeListener(_onStatusChanged);
    super.dispose();
  }

  void _onStatusChanged() {
    if (!mounted) return;
    setState(() => _status = _service?.status.value);
  }

  @override
  Widget build(BuildContext context) {
    final state = ICloudSyncTileState.forStatus(_status);
    return SettingSwitchTile(
      focusNode: widget.focusNode,
      pref: SettingsService.icloudSyncEnabled,
      icon: Symbols.cloud_sync_rounded,
      title: t.settings.icloudSync,
      subtitle: state.subtitle,
      enabled: state.enabled,
      onAfterWrite: _handleToggle,
    );
  }

  Future<void> _handleToggle(bool enabled) async {
    final svc = _service;
    if (svc == null) return;
    try {
      if (enabled) {
        await svc.enable();
      } else {
        await svc.disable();
      }
    } catch (_) {
      await widget.onToggleFailed();
    }
  }
}
