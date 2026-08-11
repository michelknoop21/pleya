import 'live_tv_support.dart';
import '../models/media_grab_operation.dart';
import '../models/media_subscription.dart';

/// DVR operations: guide reloads, recording rules and their scheduled grabs.
///
/// Split off from [LiveTvSupport] because only Plex implements any of it.
/// Obtained via [MediaServerClient.liveTvDvr], which returns `null` for
/// backends without a DVR — the same signal as
/// [ServerCapabilities.liveTvDvr], but in a form the compiler enforces.
abstract class LiveTvDvrSupport {
  Future<LiveTvActivityResult<void>> reloadGuide(String dvrId);

  Future<List<SubscriptionTemplate>> getSubscriptionTemplate(String guid);
  Future<List<MediaSubscription>> fetchRecordingRules({bool includeGrabs = true, bool includeStorage = true});
  Future<MediaSubscription?> createRecordingRule(MediaSubscriptionCreateRequest request);
  Future<MediaSubscription?> updateRecordingRule(String subscriptionId, Map<String, Object?> prefs);
  Future<void> deleteRecordingRule(String subscriptionId);
  Future<void> processRecordingRules();
  Future<List<MediaGrabOperation>> fetchScheduledRecordings();
  Future<void> cancelGrab(String operationId);
  Future<List<MediaSubscription>> fetchSubscriptionMapping({
    required String providerId,
    required List<String> ratingKeys,
    bool includeStorage = true,
  });
}
