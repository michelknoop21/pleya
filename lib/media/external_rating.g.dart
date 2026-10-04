// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'external_rating.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ExternalRating _$ExternalRatingFromJson(Map<String, dynamic> json) =>
    ExternalRating(
      source: $enumDecode(_$ExternalRatingSourceEnumMap, json['source']),
      value: (json['value'] as num).toDouble(),
      imageUri: json['imageUri'] as String?,
    );

Map<String, dynamic> _$ExternalRatingToJson(ExternalRating instance) =>
    <String, dynamic>{
      'source': _$ExternalRatingSourceEnumMap[instance.source]!,
      'value': instance.value,
      'imageUri': ?instance.imageUri,
    };

const _$ExternalRatingSourceEnumMap = {
  ExternalRatingSource.imdb: 'imdb',
  ExternalRatingSource.rottenTomatoesCritic: 'rottenTomatoesCritic',
  ExternalRatingSource.rottenTomatoesAudience: 'rottenTomatoesAudience',
  ExternalRatingSource.tmdb: 'tmdb',
  ExternalRatingSource.community: 'community',
};
