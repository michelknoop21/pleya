import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../connection/connection_registry.dart';
import '../../../i18n/strings.g.dart';
import '../../../mpv/mpv.dart';
import '../../../profiles/active_profile_provider.dart';
import '../../../profiles/profile_connection_registry.dart';
import '../../../models/companion_remote/remote_command.dart';
import '../../../providers/companion_remote_provider.dart';
import '../../../services/companion_remote/companion_remote_host_controller.dart';
import '../../../services/companion_remote/companion_remote_receiver.dart';
import '../../../services/companion_remote/playback_handoff.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/formatters.dart';
import '../../../utils/haptics.dart';
import '../../../utils/platform_detector.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/focusable_list_tile.dart';
import '../../../widgets/notice/notice.dart';
import '../../../widgets/notice/notice_controller.dart';
import '../../../widgets/overlay_sheet.dart';
import '../../../widgets/pleya_fly_icon.dart';
import 'base_video_control_sheet.dart';

/// Lists this device and the Apple TVs on the network, AirPlay-style, and hands
/// the current playback to the one the user picks (A-23, northstar 45-b to 45-g).
/// The phone keeps playing until the Apple TV reports that it plays; on any
/// failure it just keeps playing.
class PlaybackHandoffSheet extends StatefulWidget {
  final Player player;
  final String serverId;
  final String itemId;
  final String title;

  const PlaybackHandoffSheet({
    super.key,
    required this.player,
    required this.serverId,
    required this.itemId,
    required this.title,
  });

  @override
  State<PlaybackHandoffSheet> createState() => _PlaybackHandoffSheetState();
}

class _PlaybackHandoffSheetState extends State<PlaybackHandoffSheet> {
  static const _searchTimeout = Duration(seconds: 8);
  static const _amber = Color(0xFFFFB020);
  static const _ok = Color(0xFF3DD68C);

  // Read in initState, never lazily: a sheet closed before discovery started
  // would otherwise do its first lookup in dispose, on a deactivated context,
  // and that throw leaves the host's sheet subtree half unmounted.
  late final CompanionRemoteProvider _provider;
  // Taken when the sheet opens: the position the header promises.
  late final Duration _from = widget.player.state.position;
  StreamSubscription<List<DiscoveredHost>>? _subscription;
  Timer? _timeout;
  List<DiscoveredHost> _tvs = const [];
  bool _searching = true;
  DiscoveredHost? _handingTo;

  /// The Apple TV that refused and why: another profile is active on it (45-d),
  /// or the PIN of the sender's profile was not entered there (A-23b).
  ({String tv, String text})? _refusal;

  /// The profile the Apple TV switches to before it plays (A-23b); a text
  /// variant of the busy row of 45-c, not a state of its own.
  ({String profile, bool pin})? _switching;

  @override
  void initState() {
    super.initState();
    _provider = context.read<CompanionRemoteProvider>();
    unawaited(_search());
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _refusal = null;
    });
    await _subscription?.cancel();
    if (!mounted) return;
    // ignore: use_build_context_synchronously
    final ready = await ensureCompanionRemoteCrypto(context);
    if (!mounted) return;
    final stream = ready ? _provider.discoverHosts() : null;
    if (stream == null) {
      setState(() => _searching = false);
      return;
    }
    _subscription = stream.listen((hosts) {
      if (!mounted) return;
      setState(() {
        _tvs = hosts.where((h) => h.platform == 'tvOS').toList();
        if (_tvs.isNotEmpty) _searching = false;
      });
    });
    _timeout?.cancel();
    _timeout = Timer(_searchTimeout, () {
      if (mounted) setState(() => _searching = false);
    });
  }

  @override
  void dispose() {
    _timeout?.cancel();
    unawaited(_subscription?.cancel());
    _provider.stopDiscovery();
    super.dispose();
  }

  Future<void> _handOff(DiscoveredHost tv) async {
    if (_handingTo != null) return;
    // A phone that hosts its own remote session must not be overwritten by joining one.
    // Listening for Pleya Fly is no such session: joining stops it and leaving restarts it (A-23d).
    if (_provider.isHost && !_provider.isHandoffOnlyHost) return _showFailed(tv);
    Haptics.light();
    setState(() {
      _handingTo = tv;
      _refusal = null;
      _switching = null;
    });
    // Taken at the press: this is where the Apple TV starts. The phone plays
    // on until the Apple TV answers, so it can be a few seconds ahead by then.
    var request = PlaybackHandoffRequest(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      serverId: widget.serverId,
      itemId: widget.itemId,
      positionMs: widget.player.state.position.inMilliseconds,
      title: widget.title,
      from: _provider.deviceName,
    );
    // The Stop of the player this handoff started from. A later player has its own.
    final stopThisPlayer = CompanionRemoteReceiver.instance.onStop;
    // Read now: the sheet may be dismissed while it connects.
    final plexUserToken = _plexUserTokenLookup();
    var outcome = PlaybackHandoffOutcome.failed;
    try {
      await _provider.connectToDiscoveredHost(tv);
      // Known once connected: the account the handshake used.
      request = request.withPlexUserToken(await plexUserToken(_provider.peerConnectionId));
      outcome = await _provider.handOffPlayback(
        request,
        onSwitching: (profile, pin) {
          if (mounted) setState(() => _switching = (profile: profile, pin: pin));
        },
      );
    } catch (e) {
      appLogger.w('Playback handoff to ${tv.name} failed', error: e);
    }
    if (outcome == PlaybackHandoffOutcome.playing) {
      // The Apple TV plays: close this player the way the remote's Stop does,
      // also when the sheet was dismissed while waiting (45-g).
      await _provider.leaveSession();
      if (CompanionRemoteReceiver.instance.onStop == stopThisPlayer) stopThisPlayer?.call();
      noticeController.show(
        Notice(
          level: NoticeLevel.success,
          title: t.playbackHandoff.playingOn(name: tv.name),
          body: t.playbackHandoff.playingOnBody,
          groupKey: 'playback-handoff:${request.id}',
        ),
      );
      return;
    }
    // Giving up: tell the Apple TV, so a late start does not leave both playing.
    if (outcome == PlaybackHandoffOutcome.timedOut) {
      _provider.sendCommand(RemoteCommandType.syncState, data: {handoffCancelKey: request.id});
      // Sending encrypts asynchronously; closing the session now could drop it.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    await _provider.leaveSession();
    final refusal = switch (outcome) {
      PlaybackHandoffOutcome.wrongProfile => t.playbackHandoff.wrongProfile,
      PlaybackHandoffOutcome.pinCancelled => t.playbackHandoff.pinNotEntered,
      _ => null,
    };
    if (refusal != null && mounted) {
      // The user can fix this on the Apple TV and try again, so the sheet stays (45-d).
      setState(() {
        _handingTo = null;
        _refusal = (tv: tv.name, text: refusal);
        _switching = null;
      });
      return;
    }
    // Also when the sheet was dismissed while waiting: the user must hear it failed.
    _showFailed(tv, body: refusal);
  }

  /// Looks up the Plex token of this device's protected profile for the
  /// account of the connected Apple TV, so it can skip the PIN there (A-23c).
  /// Null on anything missing: the Apple TV then asks the PIN.
  Future<String?> Function(String? connectionId) _plexUserTokenLookup() {
    final profile = context.read<ActiveProfileProvider>().active;
    final connections = context.read<ConnectionRegistry>();
    final profileConnections = context.read<ProfileConnectionRegistry>();
    return (connectionId) async {
      if (profile == null || !profile.isPinProtected || connectionId == null) return null;
      try {
        final account = await connections.getPlexAccount(connectionId);
        return plexUserTokenForHandoff(
          profile: profile,
          plexConnectionId: account?.id,
          row: await profileConnections.get(profile.id, connectionId),
        );
      } catch (e) {
        appLogger.w('Playback handoff: no Plex token for the profile (${e.runtimeType})');
        return null;
      }
    };
  }

  /// Closes the sheet and says so in the player; this device keeps playing (45-e).
  void _showFailed(DiscoveredHost tv, {String? body}) {
    noticeController.show(
      Notice(
        level: NoticeLevel.warning,
        title: t.playbackHandoff.failedTitle(name: tv.name),
        body: body ?? t.playbackHandoff.failedBody,
        groupKey: 'playback-handoff-failed:${tv.clientId}',
      ),
    );
    if (mounted) OverlaySheetController.of(context).close();
  }

  Widget _row({
    required IconData icon,
    required String name,
    required Widget detail,
    Widget? trailing,
    VoidCallback? onTap,
    bool current = false,
    bool busy = false,
    bool dim = false,
  }) {
    final fill = Colors.white.withValues(alpha: current || busy ? 0.10 : 0.05);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Opacity(
        opacity: dim ? 0.45 : 1,
        child: Material(
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: busy ? BorderSide(color: Colors.white.withValues(alpha: 0.28)) : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: FocusableListTile(
            leading: AppIcon(icon, size: 24),
            title: Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            subtitle: detail,
            trailing: trailing,
            // Never the disabled style: the current device and the busy Apple TV stay bright (45-b, 45-c).
            enabled: true,
            onTap: onTap,
          ),
        ),
      ),
    );
  }

  String _busyText() => switch (_switching) {
    null => t.playbackHandoff.starting,
    (profile: final profile, pin: true) => t.playbackHandoff.switchingPin(profile: profile),
    (profile: final profile, pin: false) => t.playbackHandoff.switching(profile: profile),
  };

  Widget _readyDetail(TextStyle style) => Row(
    children: [
      Container(
        width: 7,
        height: 7,
        margin: const EdgeInsets.only(right: 6),
        decoration: const BoxDecoration(color: _ok, shape: BoxShape.circle),
      ),
      Flexible(child: Text(t.playbackHandoff.tvReady, style: style)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final dimText = TextStyle(color: tokens(context).textMuted, fontSize: 12);
    final busy = _handingTo != null;
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
        child: Text(
          t.playbackHandoff.resumeFrom(title: widget.title, time: formatDurationTimestamp(_from)),
          style: TextStyle(color: tokens(context).textMuted, fontSize: 13),
        ),
      ),
      _row(
        icon: Symbols.smartphone,
        name: PlatformDetector.isTablet(context) ? t.playbackHandoff.thisIpad : t.playbackHandoff.thisIphone,
        detail: Text(busy ? t.playbackHandoff.playingUntil : t.playbackHandoff.playingHere, style: dimText),
        trailing: const AppIcon(Symbols.check, size: 20),
        current: true,
      ),
      for (final tv in _tvs)
        _row(
          icon: Symbols.tv,
          name: tv.name,
          detail: _handingTo == tv
              ? Text(_busyText(), style: dimText)
              : _refusal?.tv == tv.name
              ? Text(_refusal!.text, style: dimText.copyWith(color: _amber))
              : _readyDetail(dimText),
          trailing: _handingTo == tv
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : null,
          busy: _handingTo == tv,
          dim: busy && _handingTo != tv,
          onTap: busy ? null : () => unawaited(_handOff(tv)),
        ),
      if (_tvs.isEmpty && _searching)
        const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      if (_tvs.isEmpty && !_searching) ...[
        Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(
                t.playbackHandoff.noneFoundTitle,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                t.playbackHandoff.noneFound,
                style: TextStyle(color: tokens(context).textMuted, fontSize: 13, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        _row(
          icon: Symbols.refresh_rounded,
          name: t.playbackHandoff.searchAgain,
          detail: const SizedBox.shrink(),
          onTap: () => unawaited(_search()),
        ),
      ] else
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Text(t.playbackHandoff.footer, style: dimText.copyWith(height: 1.4)),
        ),
    ];

    // Sized to its rows: two options do not need the full height (A-23, 20 October 2026).
    return BaseVideoControlSheet(
      title: t.playbackHandoff.title,
      leading: const PleyaFlyIcon(),
      shrinkWrap: true,
      child: ListView(shrinkWrap: true, children: children),
    );
  }
}
