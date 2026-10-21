import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../automation/automation_ids.dart';
import '../../../focus/card_focus_scope.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/companion_remote_provider.dart';
import '../../../services/companion_remote/companion_remote_host_controller.dart';
import '../../../services/companion_remote/companion_remote_receiver.dart';
import '../../../services/companion_remote/playback_handoff_sender.dart';
import '../../../utils/formatters.dart';
import '../../notice/notice.dart';
import '../../notice/notice_controller.dart';
import '../../pleya_fly_icon.dart';
import 'tv_panel_widgets.dart';

/// The sender of the TV player panel over the Companion Remote. On success the
/// player this fly started from closes and a notice says where it plays; on a
/// failure this device keeps playing, says so, and [onFailed] closes the view.
PlaybackHandoffSender createTvPleyaFlySender(BuildContext context, {required VoidCallback onFailed}) {
  return PlaybackHandoffSender(
    transport: CompanionRemoteHandoffTransport(
      context.read<CompanionRemoteProvider>(),
      ensureCrypto: () => context.mounted ? ensureCompanionRemoteCrypto(context) : Future.value(false),
    ),
    currentStop: () => CompanionRemoteReceiver.instance.onStop,
    onPlaying: (host) => noticeController.show(
      Notice(
        level: NoticeLevel.success,
        title: t.playbackHandoff.playingOn(name: host.name),
        body: t.playbackHandoff.playingOnPhoneBody,
        groupKey: 'pleya-fly:${host.clientId}',
      ),
    ),
    onFailed: (host, refusal) {
      noticeController.show(
        Notice(
          level: NoticeLevel.warning,
          title: t.playbackHandoff.failedTitle(name: host.name),
          body: pleyaFlyFailureBody(host.name, refusal),
          groupKey: 'playback-handoff-failed:${host.clientId}',
        ),
      );
      onFailed();
    },
  );
}

/// The second line of the notice for a fly that did not start: why, when the
/// phone said so, else that this device keeps playing.
String pleyaFlyFailureBody(String name, PlaybackHandoffRefusal? refusal) => switch (refusal) {
  PlaybackHandoffRefusal.wrongProfile => t.playbackHandoff.wrongProfileOn(name: name),
  PlaybackHandoffRefusal.pinNotEntered => t.playbackHandoff.pinNotEnteredOn(name: name),
  null => t.playbackHandoff.failedBody,
};

/// Pleya Fly from the Apple TV (A-23d): the iPhones and iPads with Pleya open,
/// as a sub-view of the player panel (DEC-101: the panel is the only player
/// menu on TV). Left the phones, right what goes over. The state lives in the
/// [PlaybackHandoffSender], so Menu can close this view while a fly goes on.
class TvPleyaFlySubView extends StatefulWidget {
  const TvPleyaFlySubView({
    super.key,
    required this.sender,
    required this.title,
    required this.from,
    required this.firstFocusNode,
    required this.onSelectHost,
  });

  final PlaybackHandoffSender sender;

  /// The title that goes over, and the position it was at when the view opened.
  final String title;
  final Duration from;
  final FocusNode firstFocusNode;
  final ValueChanged<DiscoveredHost> onSelectHost;

  @override
  State<TvPleyaFlySubView> createState() => _TvPleyaFlySubViewState();
}

class _TvPleyaFlySubViewState extends State<TvPleyaFlySubView> {
  @override
  void initState() {
    super.initState();
    widget.sender.attachView();
    // A fly under way keeps its list; a fresh view searches.
    if (!widget.sender.busy) unawaited(widget.sender.search());
  }

  @override
  void dispose() {
    widget.sender.stopSearch();
    super.dispose();
  }

  String _detail(DiscoveredHost host) {
    final sender = widget.sender;
    if (sender.isHandingTo(host)) {
      return switch (sender.switching) {
        null => t.playbackHandoff.startingOn(name: host.name),
        (profile: _, pin: true) => t.playbackHandoff.switchingPinOn(name: host.name),
        (profile: final profile, pin: false) => t.playbackHandoff.switchingOn(name: host.name, profile: profile),
      };
    }
    return switch (sender.refusalFor(host)) {
      PlaybackHandoffRefusal.wrongProfile => t.playbackHandoff.wrongProfileOn(name: host.name),
      PlaybackHandoffRefusal.pinNotEntered => t.playbackHandoff.pinNotEnteredOn(name: host.name),
      null => t.playbackHandoff.phoneReady,
    };
  }

  List<Widget> _left(BuildContext context) {
    final sender = widget.sender;
    final hosts = sender.visibleHosts;
    final m = TvPanelMetrics.of(context);
    final left = <Widget>[TvPanelSectionHeader(label: t.playbackHandoff.continueOn)];
    if (hosts.isEmpty && sender.searching) {
      left.add(
        TvPanelGroup(
          key: const ValueKey('pleya-fly-hosts'),
          children: [
            TvPanelRow(
              focusNode: widget.firstFocusNode,
              icon: Symbols.wifi_find_rounded,
              title: t.playbackHandoff.searchingPhones,
              automationId: AutomationIds.playerPanelRow,
              automationInstance: 'pleya_fly.searching',
            ),
          ],
        ),
      );
      return left;
    }
    if (hosts.isEmpty) {
      left.add(TvPanelStaticRow(title: t.playbackHandoff.noPhoneTitle, subtitle: t.playbackHandoff.noPhone));
      left.add(SizedBox(height: m.gap(10)));
      left.add(
        TvPanelGroup(
          key: const ValueKey('pleya-fly-hosts'),
          children: [
            TvPanelRow(
              focusNode: widget.firstFocusNode,
              icon: Symbols.refresh_rounded,
              title: t.playbackHandoff.searchAgain,
              onSelect: () => unawaited(sender.search()),
              automationId: AutomationIds.playerPanelRow,
              automationInstance: 'pleya_fly.search_again',
            ),
          ],
        ),
      );
      return left;
    }
    final busy = sender.busy;
    left.add(
      TvPanelGroup(
        key: const ValueKey('pleya-fly-hosts'),
        children: [
          for (final (i, host) in hosts.indexed)
            TvPanelRow(
              focusNode: i == 0 ? widget.firstFocusNode : null,
              icon: Symbols.smartphone,
              title: host.name,
              subtitle: _detail(host),
              highlighted: sender.isHandingTo(host),
              // While one phone starts, the others are dimmed and take no Select.
              dimmed: busy && !sender.isHandingTo(host),
              trailing: sender.isHandingTo(host)
                  ? SizedBox(
                      width: m.gap(20),
                      height: m.gap(20),
                      child: const CircularProgressIndicator(strokeWidth: 2, color: TvPanelTheme.textMuted),
                    )
                  : null,
              onSelect: busy ? null : () => widget.onSelectHost(host),
              automationId: AutomationIds.playerPanelRow,
              automationInstance: 'pleya_fly.device.$i',
              automationState: () => {'busy': sender.isHandingTo(host), 'refused': sender.refusalFor(host)?.name},
            ),
        ],
      ),
    );
    return left;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.sender,
      builder: (context, _) => TvPanelColumns(
        left: _left(context),
        right: [
          TvPanelSectionHeader(label: t.playbackHandoff.title),
          TvPanelStaticRow(
            title: widget.title,
            subtitle: t.playbackHandoff.resumeAt(time: formatDurationTimestamp(widget.from)),
          ),
        ],
      ),
    );
  }
}

/// The Pleya Fly glyph inside a panel row: it follows the row's focus ink the
/// way the Material icons of the other rows do.
class TvPleyaFlyGlyph extends StatelessWidget {
  const TvPleyaFlyGlyph({super.key});

  @override
  Widget build(BuildContext context) {
    final focused = CardFocusScope.maybeOf(context) ?? false;
    return PleyaFlyIcon(
      size: TvPanelMetrics.of(context).rowIconSize,
      color: focused ? TvPanelTheme.focusInk : Colors.white,
    );
  }
}
