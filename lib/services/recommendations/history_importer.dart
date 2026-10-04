import 'tautulli_history_importer.dart' show TautulliImportOutcome;

/// One external history source feeding [MediaInteractions]. The outcome type
/// is shared with the Tautulli importer so the service treats both the same.
abstract interface class HistoryImporter {
  Future<TautulliImportOutcome?> sync();
}
