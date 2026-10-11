import '../database/app_database.dart' show WatchedIdentity;
import '../models/trakt/trakt_title.dart';
import '../services/trakt/trakt_library_reader.dart';
import '../services/trakt/trakt_watched_identities.dart';

/// Why the asker's Trakt account may not be read, as the tool error code;
/// null when it may: linked, not a children's profile, still the profile the
/// context was built for, and personalization on. The one rule behind both the
/// "seen" filter and the watchlist tool. A linked account with personalization
/// off is not "not connected".
String? assistantTraktBlock({
  required bool connected,
  required bool kidsProfile,
  required bool sameProfile,
  required bool personalization,
}) {
  if (!connected) return 'trakt_not_connected';
  if (kidsProfile || !sameProfile) return 'trakt_not_available';
  if (!personalization) return 'trakt_personalization_off';
  return null;
}

/// What Big P may read from the asker's own Trakt account, for the active
/// profile only. Absent when Trakt is not linked, on a children's profile or
/// with personalization off: [blocked] is evaluated live on every call.
class AssistantTraktServices {
  const AssistantTraktServices({required this.blocked, required this.watchlist});

  /// Null when Trakt may be read, else the tool error code that says why.
  final String? Function() blocked;

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
  bool _failed = false;

  /// Trakt is linked and allowed but could not be read this ask: "unseen"
  /// then did not count it, and the model should say so.
  bool get unavailable => _failed;

  /// Whether the last read added Trakt titles to a "seen" answer, so the
  /// model can say that "unseen" counted Trakt.
  bool get included => _included;

  Future<List<WatchedIdentity>> identities({bool completedOnly = false}) async {
    if (!available()) return const [];
    final seen = await read();
    if (seen == null) {
      _failed = true;
      return const [];
    }
    final identities = traktWatchedIdentities(seen, completedOnly: completedOnly);
    if (identities.isNotEmpty) _included = true;
    return identities;
  }
}
