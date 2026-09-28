import 'package:json_annotation/json_annotation.dart';

part 'media_review.g.dart';

/// A critic review excerpt attached to a media item (Plex `Review[]`).
@JsonSerializable(includeIfNull: false)
class MediaReview {
  final String author;
  final String text;
  final String? imageUri;
  final String? link;
  final String? source;

  const MediaReview({required this.author, required this.text, this.imageUri, this.link, this.source});

  factory MediaReview.fromJson(Map<String, dynamic> json) => _$MediaReviewFromJson(json);

  Map<String, dynamic> toJson() => _$MediaReviewToJson(this);
}
