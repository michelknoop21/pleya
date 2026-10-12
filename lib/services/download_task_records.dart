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
///
/// Resume data embeds the task, URL included, and is stored on its own. The
/// library drops resume data that arrives for a task whose record is already
/// final, but once the record is gone that guard no longer fires, so resume
/// data without a live task is removed here as well.
class DownloadTaskRecords {
  DownloadTaskRecords({
    Future<List<TaskRecord>> Function(String group)? allRecords,
    Future<List<ResumeData>> Function()? allResumeData,
    Future<void> Function(Iterable<String> taskIds)? deleteRecords,
  }) : _allRecords = allRecords ?? ((group) => FileDownloader().database.allRecords(group: group)),
       // The package offers no public way to list resume data. `storage` is
       // marked for testing only, but it is the one handle on the store that
       // `deleteRecordsWithIds` itself works through.
       _allResumeData =
           allResumeData ??
           (() {
             // ignore: invalid_use_of_visible_for_testing_member
             return FileDownloader().database.storage.retrieveAllResumeData();
           }),
       // Also discards the resume data and the paused state of those ids.
       _deleteRecords = deleteRecords ?? ((ids) => FileDownloader().database.deleteRecordsWithIds(ids));

  final Future<List<TaskRecord>> Function(String group) _allRecords;
  final Future<List<ResumeData>> Function() _allResumeData;
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

  /// Removes every record in [group] whose status is final, and the resume
  /// data of tasks in [group] that no live record claims. Returns how many
  /// tasks were cleaned up.
  Future<int> purgeFinished(String group) async {
    try {
      final records = await _allRecords(group);
      final live = {
        for (final r in records)
          if (!r.status.isFinalState) r.taskId,
      };
      final stale = <String>{
        for (final r in records)
          if (r.status.isFinalState) r.taskId,
        for (final d in await _allResumeData())
          if (d.task.group == group && !live.contains(d.taskId)) d.taskId,
      };
      if (stale.isEmpty) return 0;
      await _deleteRecords(stale);
      return stale.length;
    } catch (e) {
      appLogger.w('Downloads: could not purge finished task records', error: e);
      return 0;
    }
  }
}
