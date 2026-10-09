import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/models/seerr/seerr_media.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';

/// Seerr keeps a 4K status beside the HD one. The request form judges a 4K
/// request on it, so "not sent" has to stay apart from "unknown".
void main() {
  Map<String, dynamic> row(Map<String, dynamic>? mediaInfo) => {
    'id': 603,
    'mediaType': 'movie',
    'title': 'Charge',
    'mediaInfo': ?mediaInfo,
  };

  test('a search row carries the 4K status next to the HD one', () {
    final media = SeerrMedia.tryFromJson(row({'status': 5, 'status4k': 2}))!;
    expect(media.status, SeerrMediaStatus.available);
    expect(media.status4k, SeerrMediaStatus.pending);
  });

  test('a detail answer carries it too', () {
    final media = SeerrMedia.fromDetail(row({'status': 5, 'status4k': 5}), mediaType: 'movie');
    expect(media.status4k, SeerrMediaStatus.available);
  });

  test('a payload without a 4K status says nothing about 4K', () {
    expect(SeerrMedia.tryFromJson(row({'status': 5}))!.status4k, isNull);
    expect(SeerrMedia.tryFromJson(row(null))!.status4k, isNull);
  });

  test('a card that follows a new HD status keeps what it knew about 4K', () {
    final media = SeerrMedia.tryFromJson(row({'status': 1, 'status4k': 2}))!;
    expect(media.withStatus(SeerrMediaStatus.available).status4k, SeerrMediaStatus.pending);
  });
}
