import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/models/seerr/seerr_issue.dart';
import 'package:pleya/services/seerr/seerr_client.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/seerr/seerr_session.dart';

void main() {
  Map<String, dynamic> issue(int id, int author, {int status = 1}) => {
    'id': id,
    'status': status,
    'createdBy': {'id': author},
    'comments': [
      {'id': 2, 'message': 'Second'},
      {'id': 1, 'message': 'First'},
    ],
  };

  SeerrClient client(int permissions, Future<http.Response> Function(http.Request) handler) {
    final result = SeerrClient(
      SeerrSession(
        baseUrl: 'https://seerr.example',
        authMode: SeerrAuthMode.local,
        cookie: 'connect.sid=fixture',
        userId: 7,
        permissions: permissions,
      ),
      httpClient: MockClient(handler),
    );
    addTearDown(result.dispose);
    return result;
  }

  http.Response json(Object value) =>
      http.Response(jsonEncode(value), 200, headers: {'content-type': 'application/json'});

  test('an own-scope list does not expose other users even if Seerr ignores the filter', () async {
    final seerr = client(SeerrPermission.createIssues, (request) async {
      expect(request.url.path, '/api/v1/issue');
      expect(request.url.queryParameters, {
        'take': '20',
        'skip': '20',
        'sort': 'modified',
        'filter': 'open',
        'createdBy': '7',
      });
      return json({
        'results': [issue(1, 7), issue(2, 8), issue(3, 7, status: 2)],
        'pageInfo': {'pages': 3},
      });
    });
    final result = await seerr.getIssues(status: SeerrIssueStatus.open, ownOnly: false, page: 2);
    expect(result.items.map((row) => row.id), [1]);
    expect(result.hasMore, isTrue);
    expect(result.items.single.comments.map((comment) => comment.message), ['First', 'Second']);
  });

  test('request management does not grant issue access or mutations', () async {
    final seerr = client(SeerrPermission.manageRequests, (_) async => throw StateError('unexpected network request'));
    final report = SeerrIssue.fromJson(issue(1, 7));
    final forbidden = throwsA(isA<SeerrException>().having((e) => e.isForbidden, 'isForbidden', true));
    await expectLater(seerr.getIssues(), forbidden);
    await expectLater(seerr.getIssue(1), forbidden);
    await expectLater(seerr.replyToIssue(report, 'comment'), forbidden);
    await expectLater(seerr.setIssueStatus(report, SeerrIssueStatus.resolved), forbidden);
  });

  test('manager replies, resolves and reopens through the issue API', () async {
    final calls = <String>[];
    final seerr = client(SeerrPermission.manageIssues, (request) async {
      calls.add('${request.method} ${request.url.path}');
      if (request.url.path.endsWith('/comment')) {
        expect(jsonDecode(request.body), {'message': 'Fixed sound'});
      }
      return json(issue(1, 8));
    });
    final report = await seerr.getIssue(1);
    await seerr.replyToIssue(report, '  Fixed sound  ');
    await seerr.setIssueStatus(report, SeerrIssueStatus.resolved);
    await seerr.setIssueStatus(report, SeerrIssueStatus.open);
    expect(calls, [
      'GET /api/v1/issue/1',
      'POST /api/v1/issue/1/comment',
      'POST /api/v1/issue/1/resolved',
      'POST /api/v1/issue/1/open',
    ]);
  });

  test('a row with an unknown status or a bad id is skipped, the rest of the page stays', () async {
    final seerr = client(SeerrPermission.manageIssues, (_) async {
      return json({
        'results': [issue(1, 7), issue(2, 7, status: 9), issue(0, 7), issue(3, 7)],
        'pageInfo': {'pages': 1},
      });
    });
    final result = await seerr.getIssues();
    expect(result.items.map((row) => row.id), [1, 3]);
  });

  test('the creator may resolve their own report, but not someone else\'s', () async {
    final calls = <String>[];
    final seerr = client(SeerrPermission.createIssues, (request) async {
      calls.add('${request.method} ${request.url.path}');
      return json(issue(1, 7));
    });
    await seerr.setIssueStatus(SeerrIssue.fromJson(issue(1, 7)), SeerrIssueStatus.resolved);
    expect(calls, ['POST /api/v1/issue/1/resolved']);
    await expectLater(
      seerr.setIssueStatus(SeerrIssue.fromJson(issue(2, 8)), SeerrIssueStatus.resolved),
      throwsA(isA<SeerrException>().having((e) => e.isForbidden, 'isForbidden', true)),
    );
    expect(calls, hasLength(1));
  });

  test('issue support: a 404 on the list route means unsupported, other failures keep the entry', () async {
    Future<bool> probe(int code) =>
        client(SeerrPermission.manageIssues, (_) async => http.Response('{}', code)).supportsIssues();
    expect(await probe(404), isFalse);
    expect(await probe(200), isTrue);
    expect(await probe(500), isTrue);
  });

  test('a 500 is not cached, a 404 is remembered only until the probe TTL ends', () async {
    var calls = 0;
    var code = 500;
    final seerr = client(SeerrPermission.manageIssues, (_) async {
      calls++;
      return http.Response('{}', code);
    });
    expect(await seerr.supportsIssues(), isTrue);
    expect(await seerr.supportsIssues(), isTrue);
    expect(calls, 2);

    code = 404;
    expect(await seerr.supportsIssues(), isFalse);
    expect(await seerr.supportsIssues(), isFalse);
    expect(calls, 3);

    final ttl = SeerrConstants.issueProbeTtl;
    addTearDown(() => SeerrConstants.issueProbeTtl = ttl);
    SeerrConstants.issueProbeTtl = Duration.zero;
    code = 200;
    expect(await seerr.supportsIssues(), isTrue);
    expect(calls, 4);
  });
}
