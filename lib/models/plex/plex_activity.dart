import 'package:json_annotation/json_annotation.dart';

part 'plex_activity.g.dart';

/// Represents a running background task on a Plex Media Server (from /activities endpoint).
@JsonSerializable(createToJson: false)
class PlexActivity {
  @JsonKey(defaultValue: '')
  final String uuid;
  @JsonKey(defaultValue: '')
  final String type;
  @JsonKey(defaultValue: '')
  final String title;
  final String? subtitle;
  @JsonKey(defaultValue: 0)
  final int progress; // 0–100
  @JsonKey(defaultValue: false)
  final bool cancellable;

  /// The library section a scan or refresh works on (`Context.librarySectionID`).
  @JsonKey(readValue: _readLibrarySectionId)
  final String? librarySectionId;

  const PlexActivity({
    required this.uuid,
    required this.type,
    required this.title,
    this.subtitle,
    required this.progress,
    required this.cancellable,
    this.librarySectionId,
  });

  factory PlexActivity.fromJson(Map<String, dynamic> json) => _$PlexActivityFromJson(json);
}

Object? _readLibrarySectionId(Map<dynamic, dynamic> json, String _) => switch (json['Context']) {
  {'librarySectionID': final Object id} when id is String || id is num => '$id',
  _ => null,
};
