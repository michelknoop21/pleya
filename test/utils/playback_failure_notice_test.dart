import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/utils/error_message_utils.dart';
import 'package:pleya/utils/playback_failure_classifier.dart';
import 'package:pleya/widgets/notice/notice.dart';

void main() {
  group('noticeForPlaybackFailure wording', () {
    test('a missing file gets its own title and says what to check', () {
      final notice = noticeForPlaybackFailure('file.mkv: HTTP error 404 Not Found');
      expect(notice.title, isNot('Playback stopped'));
      expect(notice.body, isNotNull);
      expect(notice.body!.toLowerCase(), contains('file'));
      expect(notice.groupKey, 'playback:fileUnavailable');
    });

    test('an unrecognised failure keeps the neutral stopped title', () {
      final notice = noticeForPlaybackFailure('something nobody parsed');
      expect(notice.title, 'Playback stopped');
      expect(notice.groupKey, 'playback:unknown');
    });

    test('every playback notice carries a bounded stay, unlike other errors', () {
      for (final kind in PlaybackFailureKind.values) {
        final notice = noticeForPlaybackFailureKind(kind);
        expect(notice.level, NoticeLevel.error);
        expect(notice.duration, isNotNull, reason: '${kind.name} would stay until dismissed');
      }
    });

    test('every playback notice shares the group prefix the player clears on', () {
      for (final kind in PlaybackFailureKind.values) {
        expect(noticeForPlaybackFailureKind(kind).groupKey, startsWith(playbackNoticeGroupPrefix));
      }
    });

    test('a raw log line never reaches the card', () {
      const raw = 'https://my-server.local:32400/library/parts/9815/file.mkv: HTTP error 404 Not Found';
      final notice = noticeForPlaybackFailure(raw);
      final text = '${notice.title} ${notice.body ?? ''}';
      expect(text, isNot(contains('http')));
      expect(text, isNot(contains('404')));
      expect(text, isNot(contains('.mkv')));
    });
  });
}
