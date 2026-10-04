import 'media_item.dart';

/// Evidence belongs to one server account and one exact item. Missing data
/// never proves access or an unwatched state.
enum ParticipantAccess { allowed, denied, unknown }

enum ParticipantWatchState { watched, unwatched, unknown }

class ParticipantItemEvidence {
  const ParticipantItemEvidence({
    this.access = ParticipantAccess.unknown,
    this.watch = ParticipantWatchState.unknown,
    this.item,
  });
  final ParticipantAccess access;
  final ParticipantWatchState watch;
  final MediaItem? item;
}
