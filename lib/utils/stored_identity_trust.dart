/// Whether existing identity claims can cross the Pleya applied boundary.
library;

import '../media/media_item.dart';
import '../media/media_kind.dart';
import 'external_ids.dart';
import '../services/unified_catalog/identity_resolver.dart' show continueWatchingExternalIdTarget;
import '../media/media_server_client.dart';
import '../media/unified/carried_external_ids.dart';
import '../services/pleya_server_client.dart';

bool canTrustStoredIdentity(MediaItem item, MediaServerClient? client) =>
    storedIdentityIsSafe(item) || (client is PleyaServerClient && client.canUseStoredExternalIds(item));

/// A library claim has its own applied numbers, never the caller's guessed id.
/// Existing, explicitly applied snapshots remain usable when transport is down.
Future<ExternalIds> pleyaAppliedTitleIds(MediaItem item, PleyaServerClient? client, {MediaItem? identityItem}) async {
  final target = continueWatchingExternalIdTarget(item);
  if (target == null) return const ExternalIds();
  final proof = target.targetId == item.id ? item : identityItem;
  final stored =
      proof != null &&
          proof.serverId == item.serverId &&
          proof.id == target.targetId &&
          (target.targetId == item.id || proof.kind == MediaKind.show)
      ? externalIdsCarriedBy(proof) ?? const ExternalIds()
      : const ExternalIds();
  if (client == null || !client.identityCapabilitiesKnown) return stored;
  final source = client.externalIdentitySource;
  try {
    final answer = await client.fetchExternalIdsDetailed(target.targetId);
    if (source != client.externalIdentitySource || answer.source != source) return const ExternalIds();
    return source == 'applied' ? answer.ids : stored;
  } catch (_) {
    return source == client.externalIdentitySource ? stored : const ExternalIds();
  }
}
