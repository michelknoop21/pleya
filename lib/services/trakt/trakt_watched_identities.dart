import '../../database/app_database.dart' show WatchedIdentity;
import '../../media/unified/identity_evidence.dart';
import '../../models/trakt/trakt_title.dart';
import '../../utils/external_ids.dart';
import 'trakt_library_reader.dart';

/// Trakt's watched titles in the shape the viewing log's identities have, so
/// "seen" can read them with the same token and title+year rules.
///
/// A watched film is a finished one. A series is only "seen" (an episode was
/// watched), never "completed", exactly as a log row for one episode is, so
/// [completedOnly] leaves series out.
List<WatchedIdentity> traktWatchedIdentities(TraktSeen seen, {bool completedOnly = false}) => [
  for (final t in seen.movies) _identity(t),
  if (!completedOnly)
    for (final t in seen.shows) _identity(t),
];

WatchedIdentity _identity(TraktTitle t) {
  final scope = t.isShow ? 'show' : 'movie';
  return (
    key: 'trakt:$scope:${t.ids.trakt ?? t.ids.imdb ?? t.title}',
    title: t.title,
    year: t.year,
    show: t.isShow,
    tokens: {
      for (final token in externalIdTokens(
        scope: scope,
        ids: ExternalIds(imdb: t.ids.imdb, tmdb: t.ids.tmdb, tvdb: t.ids.tvdb),
      ))
        token.key,
    },
  );
}
