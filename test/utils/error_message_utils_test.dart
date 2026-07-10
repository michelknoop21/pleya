import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/utils/error_message_utils.dart';

void main() {
  group('friendlyError', () {
    test('transient MediaServerHttpException maps to connection message', () {
      final error = MediaServerHttpException(type: MediaServerHttpErrorType.connectionError);
      expect(friendlyError(error), 'Unable to connect to media server');
    });

    test('MediaServerHttpException timeout with context names the context', () {
      final error = MediaServerHttpException(type: MediaServerHttpErrorType.connectionTimeout);
      expect(friendlyError(error, context: 'library'), contains('library'));
    });

    test('unknown-type MediaServerHttpException never surfaces its raw .message', () {
      // MediaServerHttpException.from() puts error.toString() into .message for
      // the unknown catch-all — friendlyError must not leak it, even with context.
      final error = MediaServerHttpException(
        type: MediaServerHttpErrorType.unknown,
        message: 'token=super-secret-internal-detail',
      );
      final withContext = friendlyError(error, context: 'playlists');
      expect(withContext, isNot(contains('super-secret-internal-detail')));
      expect(withContext, contains('playlists'));
      expect(friendlyError(error), isNot(contains('super-secret-internal-detail')));
    });

    test('SocketException maps to connection message', () {
      expect(friendlyError(const SocketException('boom')), 'Unable to connect to media server');
    });

    test('TimeoutException without context maps to connection message', () {
      expect(friendlyError(TimeoutException('slow')), 'Unable to connect to media server');
    });

    test('unknown error never leaks toString to the UI', () {
      final message = friendlyError(Exception('super-secret-internal-detail'));
      expect(message, isNot(contains('super-secret-internal-detail')));
      expect(message, 'Something went wrong. Try again.');
    });

    test('unknown error with context names the context, not the error', () {
      final message = friendlyError(Exception('secret'), context: 'playlists');
      expect(message, contains('playlists'));
      expect(message, isNot(contains('secret')));
    });
  });

  group('mapUnexpectedErrorToMessage', () {
    test('no longer leaks raw error toString', () {
      final message = mapUnexpectedErrorToMessage(Exception('internal-detail'), context: 'folders');
      expect(message, isNot(contains('internal-detail')));
      expect(message, contains('folders'));
    });
  });
}
