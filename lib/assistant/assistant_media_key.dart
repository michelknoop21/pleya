import '../utils/external_ids.dart';

/// How firmly two history rows on different servers are the same title.
/// Ordered from strong to weak: only [external] is proof.
enum AssistantMediaProof { external, titleYear, titleOnly }

/// What a source says about a title. [bucket] is the unified catalog's kind
/// plus normalized title (`movie:dune`, `show:severance`); the kind is part
/// of it, so a film never matches a series. [year] and [ids] are null/empty
/// where the source gives none (Plex and Tautulli history carry neither).
class AssistantMediaKey {
  const AssistantMediaKey({required this.bucket, this.year, this.ids = const ExternalIds()});

  final String bucket;
  final int? year;
  final ExternalIds ids;

  bool get show => bucket.startsWith('show:');
}

/// How [a] and [b] relate, or null when they are not the same title.
///
/// A shared external id is proof; a differing id of the same scheme, another
/// kind, or two known years that differ say they are different titles (Dune
/// 1984 and Dune 2021). Equal titles with equal years are a likely match, equal
/// titles with a year missing on a side are a guess. Never merge on less.
AssistantMediaProof? assistantMediaMatch(AssistantMediaKey a, AssistantMediaKey b) {
  if (a.show != b.show) return null;
  final x = a.ids;
  final y = b.ids;
  var shared = false;
  for (final (l, r) in [(x.imdb, y.imdb), (x.tmdb, y.tmdb), (x.tvdb, y.tvdb)]) {
    if (l == null || r == null) continue;
    if (l != r) return null;
    shared = true;
  }
  if (shared) return AssistantMediaProof.external;
  if (a.bucket != b.bucket) return null;
  if (a.year != null && b.year != null) return a.year == b.year ? AssistantMediaProof.titleYear : null;
  return AssistantMediaProof.titleOnly;
}

/// One title as seen on one or more servers. [weakest] is the weakest proof
/// that joined a server to it; null while only one server is in.
class AssistantMediaCluster<T> {
  AssistantMediaCluster(T first, AssistantMediaKey key, String server) : members = [first], servers = {server} {
    _add(key, server);
  }

  final List<T> members;
  final Set<String> servers;
  AssistantMediaProof? weakest;
  final _seen = <String>{};
  final _keys = <(AssistantMediaKey, String)>[];

  bool get crossServer => servers.length > 1;

  // Distinct keys only: thousands of plays of one title stay one entry.
  void _add(AssistantMediaKey key, String server) {
    if (_seen.add('$server|${key.bucket}|${key.year}|${key.ids}')) _keys.add((key, server));
  }
}

/// Groups [items] into titles. A row joins the first cluster that holds the
/// same title on its own server or, failing that, a match on another server.
/// Joining a new server lowers [AssistantMediaCluster.weakest] to that proof;
/// rows of a server already in never do (one server's own title is no merge).
List<AssistantMediaCluster<T>> clusterByMediaKey<T>(
  Iterable<T> items, {
  required AssistantMediaKey Function(T) keyOf,
  required String Function(T) serverOf,
}) {
  final clusters = <AssistantMediaCluster<T>>[];
  for (final item in items) {
    final key = keyOf(item);
    final server = serverOf(item);
    AssistantMediaCluster<T>? home;
    AssistantMediaProof? proof;
    for (final c in clusters) {
      var own = false;
      AssistantMediaProof? other;
      for (final (k, s) in c._keys) {
        final m = assistantMediaMatch(k, key);
        if (m == null) continue;
        if (s == server) {
          own = true;
        } else if (other == null || m.index < other.index) {
          other = m;
        }
      }
      if (own || other != null) {
        home = c;
        proof = other;
        break;
      }
    }
    if (home == null) {
      clusters.add(AssistantMediaCluster(item, key, server));
      continue;
    }
    home.members.add(item);
    if (home.servers.add(server) && proof != null) {
      if (home.weakest == null || proof.index > home.weakest!.index) home.weakest = proof;
    }
    home._add(key, server);
  }
  return clusters;
}
