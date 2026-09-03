/// A queue entry is a promise: "de rest wordt opnieuw geprobeerd zodra deze
/// online is". [isRetryableServerWriteFailure] is the one place that decides
/// whether Pleya is allowed to make it (hoofdstuk 13.4 point 4, and fase 9's
/// G10/G11 lifecycle rule 7).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';

void main() {
  group('isRetryableServerWriteFailure', () {
    test('an auth rejection is not retryable — reconnecting does not sign anyone in', () {
      expect(isRetryableServerWriteFailure(const MediaServerAuthException('token expired')), isFalse);
      expect(isRetryableServerWriteFailure(const MediaServerAuthException('403', statusCode: 403)), isFalse);
      expect(isRetryableServerWriteFailure(const MediaServerPinExpiredException()), isFalse);
    });

    test('a 401 or 403 over the plain HTTP type is not retryable either', () {
      for (final status in [401, 403]) {
        expect(
          isRetryableServerWriteFailure(
            MediaServerHttpException(type: MediaServerHttpErrorType.unknown, statusCode: status),
          ),
          isFalse,
          reason: 'HTTP $status',
        );
      }
    });

    test('a backend that has no such endpoint is not retryable', () {
      // Jellyfin's removeFromContinueWatching throws exactly this. Queueing it
      // would leave a row retrying until it hit its attempt cap.
      expect(isRetryableServerWriteFailure(UnsupportedError('not supported')), isFalse);
    });

    test('the other 4xx are dead ends too', () {
      for (final status in [400, 404, 409, 422]) {
        expect(
          isRetryableServerWriteFailure(
            MediaServerHttpException(type: MediaServerHttpErrorType.unknown, statusCode: status),
          ),
          isFalse,
          reason: 'HTTP $status',
        );
      }
    });

    test('408 and 429 are the two client-range statuses that mean try again', () {
      for (final status in [408, 429]) {
        expect(
          isRetryableServerWriteFailure(
            MediaServerHttpException(type: MediaServerHttpErrorType.unknown, statusCode: status),
          ),
          isTrue,
          reason: 'HTTP $status',
        );
      }
    });

    test('server errors and transport failures are retryable', () {
      expect(
        isRetryableServerWriteFailure(
          MediaServerHttpException(type: MediaServerHttpErrorType.unknown, statusCode: 500),
        ),
        isTrue,
      );
      expect(
        isRetryableServerWriteFailure(
          MediaServerHttpException(type: MediaServerHttpErrorType.connectionTimeout, statusCode: null),
        ),
        isTrue,
      );
      expect(isRetryableServerWriteFailure(const SocketException('no route to host')), isTrue);
      expect(isRetryableServerWriteFailure(TimeoutException('slow')), isTrue);
    });

    test('an unrecognised throw errs towards retrying', () {
      // The safe direction: a hopeless queued entry is capped by
      // maxSyncAttempts, while a dropped one is a write the user was told had
      // been remembered and silently was not.
      expect(isRetryableServerWriteFailure(StateError('something else entirely')), isTrue);
    });
  });
}
