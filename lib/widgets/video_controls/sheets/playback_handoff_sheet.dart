import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../i18n/strings.g.dart';
import '../../../mpv/mpv.dart';
import '../../../models/companion_remote/remote_command.dart';
import '../../../providers/companion_remote_provider.dart';
import '../../../services/companion_remote/companion_remote_host_controller.dart';
import '../../../services/companion_remote/companion_remote_receiver.dart';
import '../../../services/companion_remote/playback_handoff.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/haptics.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/focusable_list_tile.dart';
import 'base_video_control_sheet.dart';

/// Lists the Apple TVs on the network and hands the current playback to the one
/// the user picks (A-23). The phone keeps playing until the Apple TV reports
/// that it plays; on any failure it just keeps playing.
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

  late final CompanionRemoteProvider _provider = context.read<CompanionRemoteProvider>();
  StreamSubscription<List<DiscoveredHost>>? _subscription;
  Timer? _timeout;
  List<DiscoveredHost> _tvs = const [];
  bool _searching = true;
  DiscoveredHost? _handingTo;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _failed = false;
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
    if (_provider.isHost) {
      setState(() => _failed = true);
      return;
    }
    Haptics.light();
    setState(() {
      _handingTo = tv;
      _failed = false;
    });
    // Taken at the press: this is where the Apple TV starts. The phone plays
    // on until the Apple TV answers, so it can be a few seconds ahead by then.
    final request = PlaybackHandoffRequest(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      serverId: widget.serverId,
      itemId: widget.itemId,
      positionMs: widget.player.state.position.inMilliseconds,
      title: widget.title,
      from: _provider.deviceName,
    );
    var outcome = PlaybackHandoffOutcome.failed;
    try {
      await _provider.connectToDiscoveredHost(tv);
      outcome = await _provider.handOffPlayback(request);
    } catch (e) {
      appLogger.w('Playback handoff to ${tv.name} failed', error: e);
    }
    if (outcome == PlaybackHandoffOutcome.playing) {
      // The Apple TV plays: close this player the way the remote's Stop does,
      // also when the sheet was dismissed while waiting.
      await _provider.leaveSession();
      CompanionRemoteReceiver.instance.onStop?.call();
      return;
    }
    // Giving up: tell the Apple TV, so a late start does not leave both playing.
    if (outcome == PlaybackHandoffOutcome.timedOut) {
      _provider.sendCommand(RemoteCommandType.syncState, data: {handoffCancelKey: request.id});
    }
    await _provider.leaveSession();
    if (!mounted) return;
    setState(() {
      _handingTo = null;
      _failed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final muted = tokens(context).textMuted;
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Text(t.playbackHandoff.subtitle, style: TextStyle(color: muted, fontSize: 13)),
      ),
      for (final tv in _tvs)
        FocusableListTile(
          leading: const AppIcon(Symbols.tv_rounded, fill: 1),
          title: Text(tv.name),
          subtitle: Text(
            _handingTo == tv ? t.playbackHandoff.starting : t.playbackHandoff.ready,
            style: TextStyle(color: muted, fontSize: 12),
          ),
          trailing: _handingTo == tv
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : null,
          enabled: _handingTo == null,
          onTap: () => unawaited(_handOff(tv)),
        ),
      if (_failed)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(t.playbackHandoff.failed, style: const TextStyle(color: Color(0xFFFFB020), fontSize: 13)),
        ),
      if (_tvs.isEmpty && _searching)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      if (_tvs.isEmpty && !_searching) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(t.playbackHandoff.noneFound, style: TextStyle(color: muted, fontSize: 13, height: 1.4)),
        ),
        FocusableListTile(
          leading: const AppIcon(Symbols.refresh_rounded),
          title: Text(t.playbackHandoff.searchAgain),
          onTap: () => unawaited(_search()),
        ),
      ],
    ];

    return BaseVideoControlSheet(
      title: t.playbackHandoff.title,
      icon: Symbols.cast_connected_rounded,
      child: ListView(children: children),
    );
  }
}
