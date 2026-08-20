import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/utils/error_message_utils.dart';
import 'package:pleya/widgets/notice/notice.dart';

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

  group('friendlyError over the full MediaServerException hierarchy', () {
    test('MediaServerAuthException never leaks its hand-written .message', () {
      final error = MediaServerAuthException('Invalid username or password', statusCode: 401);
      expect(friendlyError(error), isNot(contains('Invalid username or password')));
    });

    test('MediaServerPinExpiredException (a MediaServerAuthException subtype) is handled, not rethrown', () {
      expect(() => friendlyError(const MediaServerPinExpiredException()), returnsNormally);
    });

    test('MediaServerUrlException never leaks its hand-written .message', () {
      final error = MediaServerUrlException('Server did not respond in time');
      expect(friendlyError(error), isNot(contains('Server did not respond in time')));
    });
  });

  group('noticeForError technical-leak sweep', () {
    // Patterns that must never reach a Notice shown on screen: exception
    // class names, transport-layer class names, stack-trace fragments, raw
    // URLs/hosts/ports, and the classic `Instance of 'Foo'` default toString.
    const forbidden = [
      'Exception',
      'SocketException',
      'ClientException',
      'HandshakeException',
      'MediaServerHttpException',
      'stack trace',
      'http://',
      'https://',
      ':8443',
      "Instance of '",
    ];

    void expectNoLeak(Notice notice) {
      final text = '${notice.title} ${notice.body ?? ''}';
      for (final pattern in forbidden) {
        expect(text, isNot(contains(pattern)), reason: 'leaked "$pattern" in "$text"');
      }
    }

    final fixtureUri = Uri.parse('https://my-plex-server.local:8443/library/sections');

    test('MediaServerHttpException (unknown type, from a real caught exception)', () {
      final error = MediaServerHttpException.from(
        ClientException('Connection closed while receiving data', fixtureUri),
        uri: fixtureUri,
      );
      expectNoLeak(noticeForError(error, context: 'Libraries'));
    });

    test('MediaServerHttpException connectionError (from a real SocketException)', () {
      final error = MediaServerHttpException.from(
        SocketException('Connection refused', address: InternetAddress.loopbackIPv4, port: 8443),
        uri: fixtureUri,
      );
      expectNoLeak(noticeForError(error, context: 'Discover', serverName: 'my-plex-server.local'));
    });

    test('MediaServerAuthException', () {
      final error = MediaServerAuthException('Invalid username or password', statusCode: 401);
      expectNoLeak(noticeForError(error, context: 'Sign in'));
    });

    test('MediaServerPinExpiredException', () {
      expectNoLeak(noticeForError(const MediaServerPinExpiredException()));
    });

    test('MediaServerUrlException', () {
      final error = MediaServerUrlException('Server did not respond in time');
      expectNoLeak(noticeForError(error, serverName: 'my-plex-server.local'));
    });

    test('a raw SocketException never routed through MediaServerHttpException.from', () {
      expectNoLeak(noticeForError(const SocketException('Connection refused')));
    });

    test('a bare Exception (the toString()-leak default case)', () {
      expectNoLeak(noticeForError(Exception('internal-detail')));
    });

    test('every Notice carries a well-formed report code', () {
      final notice = noticeForError(Exception('boom'), context: 'Home');
      expect(notice.reportCode, matches(RegExp(r'^[0-9A-F]{4}$')));
    });
  });
}
