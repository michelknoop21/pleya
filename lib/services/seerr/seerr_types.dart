/// Shared value types for the seerr client, split out of `seerr_client.dart`
/// to keep that file focused on transport. Re-exported from there.
library;

import '../../models/seerr/seerr_media.dart';

/// Typed seerr error so callers can distinguish auth (401), permission (403)
/// and network/other failures for user-facing messaging.
class SeerrException implements Exception {
  final String message;
  final bool isAuth;
  final bool isForbidden;
  final bool isNetwork;

  const SeerrException(this.message, {this.isAuth = false, this.isForbidden = false, this.isNetwork = false});

  factory SeerrException.auth() => const SeerrException('Not authenticated', isAuth: true);
  factory SeerrException.forbidden() => const SeerrException('Not permitted', isForbidden: true);
  factory SeerrException.network(String m) => SeerrException(m, isNetwork: true);
  factory SeerrException.http(int code, Object? body) {
    // Overseerr/Jellyseerr return {"message": ...} on failure — surface it.
    final msg = body is Map ? body['message']?.toString() : null;
    return SeerrException(msg != null && msg.isNotEmpty ? msg : 'HTTP $code');
  }

  @override
  String toString() => message;
}

/// A page of discover/search results.
typedef SeerrMediaPage = ({List<SeerrMedia> items, int page, int totalPages});

/// A user's remaining request quota.
typedef SeerrQuota = ({int? movieRemaining, int? movieLimit, int? tvRemaining, int? tvLimit});

/// A TMDB genre (id + display name) from `/genres/movie` or `/genres/tv`.
typedef SeerrGenre = ({int id, String name});

/// A streaming service from `/watchproviders/*`. [logoPath] is a TMDB path, so
/// it still needs the image base URL prefixed before use.
class SeerrWatchProvider {
  final int id;
  final String name;
  final String? logoPath;

  const SeerrWatchProvider({required this.id, required this.name, this.logoPath});

  static SeerrWatchProvider? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! int || name is! String || name.isEmpty) return null;
    final logo = json['logoPath'];
    return SeerrWatchProvider(id: id, name: name, logoPath: logo is String && logo.isNotEmpty ? logo : null);
  }
}
