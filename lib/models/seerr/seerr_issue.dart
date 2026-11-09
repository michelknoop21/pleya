enum SeerrIssueStatus { open, resolved }

typedef SeerrIssueComment = ({int id, int? userId, String? author, String message, DateTime? createdAt});

class SeerrIssue {
  SeerrIssue.fromJson(Map<String, dynamic> json)
    : id = _positiveId(json['id']),
      status = switch (json['status']) {
        1 => SeerrIssueStatus.open,
        2 => SeerrIssueStatus.resolved,
        _ => throw const FormatException('Invalid Seerr issue status'),
      },
      type = json['issueType'] is int ? json['issueType'] as int : 0,
      creatorId = _optionalId(_map(json['createdBy'])['id']),
      creator = _author(_map(json['createdBy'])),
      mediaType = _text(_map(json['media'])['mediaType']),
      tmdbId = _optionalId(_map(json['media'])['tmdbId']),
      season = _optionalId(json['problemSeason']),
      episode = _optionalId(json['problemEpisode']),
      createdAt = _date(json['createdAt']),
      updatedAt = _date(json['updatedAt']),
      comments = _comments(json['comments']);

  final int id;
  final SeerrIssueStatus status;
  final int type;
  final int? creatorId;
  final String? creator;
  final String? mediaType;
  final int? tmdbId;
  final int? season;
  final int? episode;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<SeerrIssueComment> comments;

  static Map<dynamic, dynamic> _map(Object? value) => value is Map ? value : const {};
  static String? _text(Object? value) => value is String && value.isNotEmpty ? value : null;
  static int? _optionalId(Object? value) => value is int && value > 0 ? value : null;
  static int _positiveId(Object? value) =>
      _optionalId(value) ?? (throw const FormatException('Invalid Seerr issue ID'));
  static DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value) : null;
  static String? _author(Map<dynamic, dynamic> user) =>
      _text(user['displayName']) ?? _text(user['username']) ?? _text(user['plexUsername']);

  static List<SeerrIssueComment> _comments(Object? value) {
    if (value is! List) return const [];
    return [
      for (final comment in value)
        if (comment is Map && comment['id'] is int && comment['message'] is String)
          (
            id: _positiveId(comment['id']),
            userId: _optionalId(_map(comment['user'])['id']),
            author: _author(_map(comment['user'])),
            message: comment['message'] as String,
            createdAt: _date(comment['createdAt']),
          ),
    ]..sort((a, b) => a.id.compareTo(b.id));
  }
}
