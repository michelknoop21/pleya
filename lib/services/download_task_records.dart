import 'package:background_downloader/background_downloader.dart';

import '../utils/app_logger.dart';

/// Keeps the downloader's task records free of finished tasks.
///
/// background_downloader writes a JSON record per tracked task to the app
/// support directory, URL included, and never removes it by itself. Our stream
/// URLs carry the account token (Jellyfin `api_key`, Plex `X-Plex-Token`), so a
/// task that finished, failed or was cancelled would leave that token readable
/// there for as long as the install lives. A task that is still queued, running
/// or paused needs its record (`rescheduleKilledTasks`, resume); a final one
/// does not, because the download library keeps its own state.
class DownloadTaskRecords {
  DownloadTaskRecords({
    Future<List<TaskRecord>> Function(String group)? allRecords,
    Future<void> Function(Iterable<String> taskIds)? deleteRecords,
  }) : _allRecords = allRecords ?? ((group) => FileDownloader().database.allRecords(group: group)),
       _deleteRecords = deleteRecords ?? ((ids) => FileDownloader().database.deleteRecordsWithIds(ids));

  final Future<List<TaskRecord>> Function(String group) _allRecords;
  final Future<void> Function(Iterable<String> taskIds) _deleteRecords;

  /// Removes the record of a task whose status is final. Never throws: a
  /// failure leaves the record for the next [purgeFinished].
  Future<void> forgetIfFinal(Task task, TaskStatus status) async {
    if (!status.isFinalState) return;
    try {
      await _deleteRecords([task.taskId]);
    } catch (e) {
      appLogger.w('Downloads: could not remove the record of a finished task', error: e);
    }
  }

  /// Removes every record in [group] whose status is final. Returns how many.
  Future<int> purgeFinished(String group) async {
    try {
      final finished = (await _allRecords(group)).where((r) => r.status.isFinalState).map((r) => r.taskId).toList();
      if (finished.isEmpty) return 0;
      await _deleteRecords(finished);
      return finished.length;
    } catch (e) {
      appLogger.w('Downloads: could not purge finished task records', error: e);
      return 0;
    }
  }
}
