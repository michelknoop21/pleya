// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_review.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MediaReview _$MediaReviewFromJson(Map<String, dynamic> json) => MediaReview(
  author: json['author'] as String,
  text: json['text'] as String,
  imageUri: json['imageUri'] as String?,
  link: json['link'] as String?,
  source: json['source'] as String?,
);

Map<String, dynamic> _$MediaReviewToJson(MediaReview instance) =>
    <String, dynamic>{
      'author': instance.author,
      'text': instance.text,
      'imageUri': ?instance.imageUri,
      'link': ?instance.link,
      'source': ?instance.source,
    };
