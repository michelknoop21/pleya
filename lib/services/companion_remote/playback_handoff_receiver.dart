import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../models/companion_remote/remote_command.dart';
import '../../providers/companion_remote_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../utils/app_logger.dart';
import '../../utils/video_player_navigation.dart';
import '../../widgets/notice/notice.dart';
import '../../widgets/notice/notice_controller.dart';
import 'companion_remote_receiver.dart';
import 'playback_handoff.dart';

/// Apple TV side of a Playback Handoff (A-23): open the item the phone named,
/// at the position it named, and report back once it plays.
///
/// A handoff is a deliberate press on the phone, so it replaces whatever this
/// device is doing without asking. Any failure is reported to the phone, which
/// then keeps playing.
Future<void> receivePlaybackHandoff(BuildContext context, PlaybackHandoffRequest request) async {
  final provider = context.read<CompanionRemoteProvider>();
  void fail(String reason) {
    appLogger.w('Playback handoff ${request.id} failed: $reason');
    provider.sendCommand(RemoteCommandType.syncState, data: {handoffFailedKey: request.id});
  }

  final serverId = ServerId.tryParse(request.serverId);
  final client = serverId == null ? null : context.read<MultiServerProvider>().getClientForServer(serverId);
  if (client == null) return fail('server ${request.serverId} not available');

  MediaItem? item;
  try {
    item = await client.fetchItem(request.itemId);
  } catch (e) {
    appLogger.d('Playback handoff item fetch failed', error: e);
  }
  if (!context.mounted) return;
  if (item == null || (item.kind != MediaKind.movie && item.kind != MediaKind.episode)) {
    return fail('item ${request.itemId} not playable');
  }

  // A player that is already open is closed first; two players must never stack.
  final closePlayer = CompanionRemoteReceiver.instance.onStop;
  if (closePlayer != null) {
    closePlayer();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!context.mounted) return;
  }

  noticeController.show(
    Notice(
      level: NoticeLevel.info,
      title: t.playbackHandoff.received(from: request.from),
      body: item.displayTitle,
      groupKey: 'playback-handoff:${request.id}',
    ),
  );

  await navigateToVideoPlayer(
    context,
    metadata: item,
    // The sender's position is the intent; a refetch or a cached offset must not compete with it.
    resolveWatchState: false,
    startPosition: Duration(milliseconds: request.positionMs),
    handoffId: request.id,
    onPlaybackInitFailed: () => fail('player did not start'),
  );
}
