/// Pure identity-evidence primitives shared by every unified-catalog
/// identity computation (hoofdstuk 11.1/11.3 of
/// docs/tvos-unified-experience.md). No I/O, no backend imports beyond the
/// neutral [MediaKind]/[ExternalIds] types.
library;

import '../media_kind.dart';
import '../../utils/external_ids.dart';
import 'canonical_media_identity.dart';

/// A single piece of strong identity evidence: a namespaced token like
/// `movie:tmdb:438631` or `show:tvdb:371980` (hoofdstuk 11.3).
///
/// [scope] is the identity granularity the token was collected at — `movie`,
/// `show`, `season` or `episode` — so a TMDB id collected for a show never
/// silently collides with the same numeric id collected for a movie.
class IdentityToken {
  final String scope;
  final String namespace;
  final String value;

  const IdentityToken({required this.scope, required this.namespace, required this.value});

  /// Canonical string form, also usable as a map/set key.
  String get key => '$scope:$namespace:$value';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IdentityToken && other.scope == scope && other.namespace == namespace && other.value == value;

  @override
  int get hashCode => Object.hash(scope, namespace, value);

  @override
  String toString() => key;
}

/// The identity-relevant facts extracted from one concrete source (hoofdstuk
/// 11.1): its [CanonicalMediaIdentity] bucket plus whatever strong tokens
/// (external ids, stable guid) were collected for it. Distinct from
/// `MediaItem` itself, which carries playback and display fields the
/// identity pipeline never needs.
class IdentityEvidence {
  final CanonicalMediaIdentity identity;
  final Set<IdentityToken> strongTokens;

  const IdentityEvidence({required this.identity, this.strongTokens = const {}});

  bool get hasStrongEvidence => strongTokens.isNotEmpty;

  /// Whether there is anything at all to bucket or match on.
  bool get isUsable => hasStrongEvidence || identity.bucketKey != null;
}

/// Namespace for identity tokens built from a stable catalogue GUID
/// (`plex://movie/...`), as opposed to `tmdb`/`imdb`/`tvdb`.
const identityTokenNamespaceGuid = 'guid';
const identityTokenNamespaceImdb = 'imdb';
const identityTokenNamespaceTmdb = 'tmdb';
const identityTokenNamespaceTvdb = 'tvdb';

/// Normalizes a raw server GUID into a value usable as strong identity
/// evidence, or `null` when it cannot serve that role.
///
/// Centralizes the rule previously duplicated ad hoc wherever Continue
/// Watching dedup needed it: a GUID is only trustworthy when it names a real
/// agent (`scheme://...`) and is not Plex's "no agent matched this item"
/// marker (`agents.none://`, in both the legacy `com.plexapp.` and current
/// `tv.plex.` forms). A server-local or unmatched GUID says nothing about
/// what the item actually is, so it must never contribute to grouping.
String? normalizeStableGuid(String? guid) {
  final value = guid?.trim();
  if (value == null || value.isEmpty) return null;
  if (!value.contains('://')) return null;
  if (value.contains('agents.none://')) return null;
  return value.toLowerCase();
}

/// Builds the strong tokens a stable GUID contributes at [scope], or an empty
/// set when the GUID is not usable as evidence.
///
/// Episodes are always scoped to `episode` regardless of the caller's
/// requested [scope]: a GUID identifies the concrete item it was read from,
/// and an episode GUID must never be treated as evidence for its show.
Set<IdentityToken> guidTokens({required String scope, required String? guid, required MediaKind kind}) {
  final stable = normalizeStableGuid(guid);
  if (stable == null) return const {};
  final effectiveScope = kind == MediaKind.episode ? 'episode' : scope;
  return {IdentityToken(scope: effectiveScope, namespace: identityTokenNamespaceGuid, value: stable)};
}

/// Builds the strong tokens an [ExternalIds] triple contributes at [scope].
Set<IdentityToken> externalIdTokens({required String scope, required ExternalIds ids}) {
  final tokens = <IdentityToken>{};
  final imdb = ids.imdb?.trim().toLowerCase();
  if (imdb != null && imdb.isNotEmpty) {
    tokens.add(IdentityToken(scope: scope, namespace: identityTokenNamespaceImdb, value: imdb));
  }
  final tmdb = ids.tmdb;
  if (tmdb != null) {
    tokens.add(IdentityToken(scope: scope, namespace: identityTokenNamespaceTmdb, value: '$tmdb'));
  }
  final tvdb = ids.tvdb;
  if (tvdb != null) {
    tokens.add(IdentityToken(scope: scope, namespace: identityTokenNamespaceTvdb, value: '$tvdb'));
  }
  return tokens;
}
