import '../database/app_database.dart' show WatchedIdentity;
import '../models/trakt/trakt_title.dart';
import '../services/trakt/trakt_library_reader.dart';
import '../services/trakt/trakt_watched_identities.dart';

/// Whether the asker's Trakt account may be read at all: linked, not a
/// children's profile, still the profile the context was built for, and
/// personalization on. The one rule behind both the "seen" filter and the
/// watchlist tool.
bool assistantTraktAvailable({
  required bool connected,
  required bool kidsProfile,
  required bool sameProfile,
  required bool personalization,
}) => connected && !kidsProfile && sameProfile && personalization;

/// What Big P may read from the asker's own Trakt account, for the active
/// profile only. Absent when Trakt is not linked, on a children's profile or
/// with personalization off: [available] is evaluated live on every call.
class AssistantTraktServices {
  const AssistantTraktServices({required this.available, required this.watchlist});

  final bool Function() available;

  /// Newest watchlist entries, or null when Trakt cannot be read right now.
  final Future<List<TraktTitle>?> Function() watchlist;
}

/// The Trakt side of "seen": titles the asker watched elsewhere, read through
/// the reader's cache. Used only locally to filter; nothing of it is sent on.
class AssistantTraktSeen {
  AssistantTraktSeen({required this.available, required this.read});

  final bool Function() available;
  final Future<TraktSeen?> Function() read;
  bool _included = false;

  /// Whether the last read added Trakt titles to a "seen" answer, so the
  /// model can say that "unseen" counted Trakt.
  bool get included => _included;

  Future<List<WatchedIdentity>> identities({bool completedOnly = false}) async {
    if (!available()) return const [];
    final seen = await read();
    if (seen == null) return const [];
    final identities = traktWatchedIdentities(seen, completedOnly: completedOnly);
    if (identities.isNotEmpty) _included = true;
    return identities;
  }
}
