import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../providers/companion_remote_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../services/companion_remote/companion_remote_host_controller.dart';
import '../../services/companion_remote/fly_follow_puller.dart';
import '../../services/companion_remote/pleya_fly_receive.dart';
import '../../services/settings_service.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/formatters.dart';
import '../../utils/haptics.dart';
import '../../utils/provider_extensions.dart';
import '../../watch_together/providers/watch_together_provider.dart';
import '../media_markers.dart';
import '../notice/notice.dart';
import '../notice/notice_controller.dart';
import '../optimized_media_image.dart';
import '../pleya_fly_icon.dart';
import '../tv/tv_expandable_media_tile.dart' show discoveryWideArtPath;
import 'fly_follow_indicators.dart';

/// The Meenemen card on iPhone Home (A-23e, 45-h). It shows only while an
/// Apple TV in the Home plays something; one tap and this phone follows it.
class FlyFollowHomeCard extends StatefulWidget {
  const FlyFollowHomeCard({super.key});

  @override
  State<FlyFollowHomeCard> createState() => _FlyFollowHomeCardState();
}

class _FlyFollowHomeCardState extends State<FlyFollowHomeCard> {
  FlyFollowPuller? _puller;

  @override
  void initState() {
    super.initState();
    if (!pleyaFlyReceiveSupported()) return;
    // Pleya Fly off on this phone: no card either.
    final enabled = SettingsService.instanceOrNull?.read(SettingsService.enablePleyaFlyReceive) ?? false;
    if (!enabled) return;
    final companion = context.read<CompanionRemoteProvider>();
    final multiServer = context.read<MultiServerProvider>();
    final watchTogether = context.read<WatchTogetherProvider>();
    _puller = FlyFollowPuller(
      transport: CompanionRemoteFollowTransport(
        companion,
        ensureCrypto: () => mounted ? ensureCompanionRemoteCrypto(context) : Future.value(false),
      ),
      resolveItem: (serverId, itemId) async {
        final id = ServerId.tryParse(serverId);
        final client = id == null ? null : multiServer.getClientForServer(id);
        return client?.fetchItem(itemId);
      },
      join: (offer) {
        // Never leave the user's own Samen kijken session behind their back.
        if (watchTogether.isInSession && !watchTogether.isFlySession) {
          throw StateError('Watch Together runs on this phone');
        }
        return watchTogether.joinSession(
          offer.sessionId!,
          displayName: companion.deviceName,
          flySession: true,
          relayUrl: offer.relayUrl,
        );
      },
    );
    unawaited(_puller!.start());
  }

  @override
  void dispose() {
    _puller?.dispose();
    super.dispose();
  }

  Future<void> _take() async {
    final puller = _puller;
    final card = puller?.card;
    if (puller == null || card == null) return;
    final watchTogether = context.read<WatchTogetherProvider>();
    if (watchTogether.isInSession && !watchTogether.isFlySession) {
      // Busy with a code session here: say so instead of leaving it (M5).
      noticeController.show(
        Notice(
          level: NoticeLevel.info,
          title: t.flyFollow.failedTitle,
          body: t.flyFollow.busyPhone,
          groupKey: 'pleya-fly-follow-busy',
        ),
      );
      return;
    }
    Haptics.light();
    if (await puller.take()) return;
    noticeController.show(
      Notice(
        level: NoticeLevel.warning,
        title: t.flyFollow.failedTitle,
        body: t.flyFollow.failedBody(name: card.tv.name),
        groupKey: 'pleya-fly-follow-failed:${card.tv.clientId}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final puller = _puller;
    if (puller == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: puller,
      builder: (context, _) {
        final card = puller.card;
        if (card == null) return const SizedBox.shrink();
        return FlyFollowCardView(card: card, taking: puller.taking, onTake: _take);
      },
    );
  }
}

/// The card itself, without discovery, so tests and goldens can draw each state.
class FlyFollowCardView extends StatelessWidget {
  const FlyFollowCardView({super.key, required this.card, required this.onTake, this.taking = false});

  final FlyFollowCard card;
  final bool taking;
  final VoidCallback onTake;

  String _detail() => switch (card.block) {
    FlyFollowCardBlock.unsupported => t.flyFollow.unsupported,
    FlyFollowCardBlock.busy => t.flyFollow.busy(name: card.tv.name),
    FlyFollowCardBlock.unreachable => t.flyFollow.unreachable,
    null => t.flyFollow.at(time: formatDurationTimestamp(Duration(milliseconds: card.offer?.positionMs ?? 0))),
  };

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final offer = card.offer;
    return AutomationNode(
      id: AutomationIds.homeFlyFollowCard,
      role: 'region',
      state: () => {'tv': card.tv.name, 'title': card.title, 'canFollow': card.canFollow, 'block': card.block?.name},
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: tk.surface, borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              // On the narrowest phones (320) the still gives its room to the text.
              if (MediaQuery.sizeOf(context).width >= 360) ...[
                _Thumb(item: card.item, positionMs: offer?.positionMs),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  mainAxisSize: .min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(color: flySyncGreen, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            t.flyFollow.playingOn(name: card.tv.name),
                            maxLines: 1,
                            overflow: .ellipsis,
                            style: TextStyle(color: tk.textMuted, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      card.title,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: TextStyle(color: tk.text, fontSize: 15, fontWeight: .w700),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _detail(),
                      maxLines: card.block == null ? 1 : 2,
                      overflow: .ellipsis,
                      style: TextStyle(color: tk.textMuted.withValues(alpha: 0.75), fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (card.canFollow) ...[const SizedBox(width: 10), _TakeButton(taking: taking, onTake: onTake)],
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.item, required this.positionMs});

  final MediaItem? item;
  final int? positionMs;

  @override
  Widget build(BuildContext context) {
    const width = 64.0;
    const height = width * 9 / 16;
    final item = this.item;
    final duration = item?.durationMs;
    final fraction = duration != null && duration > 0 && positionMs != null
        ? (positionMs! / duration).clamp(0.0, 1.0)
        : null;
    final client = item == null ? null : context.tryGetMediaClientWithFallback(serverIdOrNull(item.serverId));
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            if (item != null)
              OptimizedMediaImage.thumb(
                client: client,
                imagePath: discoveryWideArtPath(item) ?? item.thumbPath,
                width: width,
                height: height,
                fallbackIcon: Symbols.movie_rounded,
                blurHash: item.posterBlurHash,
              ),
            if (fraction != null) Positioned(left: 0, right: 0, bottom: 0, child: ResumeLine(fraction: fraction)),
          ],
        ),
      ),
    );
  }
}

class _TakeButton extends StatelessWidget {
  const _TakeButton({required this.taking, required this.onTake});

  final bool taking;
  final VoidCallback onTake;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return AutomationNode(
      id: AutomationIds.homeFlyFollowTake,
      role: 'button',
      state: () => {'taking': taking},
      child: Material(
        color: tk.text,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: taking ? null : onTake,
          child: SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 13, 0),
              child: Row(
                mainAxisSize: .min,
                children: [
                  if (taking)
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: tk.bg))
                  else
                    PleyaFlyIcon(size: 20, color: tk.bg),
                  const SizedBox(width: 6),
                  Text(
                    t.flyFollow.take,
                    style: TextStyle(color: tk.bg, fontSize: 14, fontWeight: .w700),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
