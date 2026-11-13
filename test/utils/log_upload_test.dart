import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/utils/log_upload.dart';

/// The relay caps a log at 1 MB while the in-memory buffer holds up to 5 MB,
/// so an evening of playback used to produce an upload the server answered
/// with a 413, and the app showed one generic line for it.
void main() {
  String linesOfSize(int bytes, {String prefix = 'line'}) {
    final buffer = StringBuffer();
    var i = 0;
    while (buffer.length < bytes) {
      buffer.writeln('$prefix $i ${'x' * 80}');
      i++;
    }
    return buffer.toString();
  }

  test('leaves a log that already fits untouched', () {
    final body = buildLogUploadBody(header: 'Pleya v2.8.0', entries: 'one\ntwo\n');

    expect(body, 'Pleya v2.8.0\n---\none\ntwo\n');
  });

  test('clips an oversized log below the limit', () {
    final body = buildLogUploadBody(header: 'Pleya v2.8.0', entries: linesOfSize(2 * 1024 * 1024));

    expect(utf8.encode(body).length, lessThanOrEqualTo(logUploadMaxBytes));
  });

  test('keeps the newest lines and the header, and says what it dropped', () {
    final entries = '${linesOfSize(2 * 1024 * 1024, prefix: 'old')}newest line\n';

    final body = buildLogUploadBody(header: 'Pleya v2.8.0', entries: entries);

    expect(body, startsWith('Pleya v2.8.0\n---\n[truncated: '));
    expect(body, contains('KB of older log lines dropped'));
    expect(body, endsWith('newest line\n'));
    expect(body, isNot(contains('old 0 ')));
  });

  test('cuts on a line boundary so no partial entry is uploaded', () {
    final body = buildLogUploadBody(header: '', entries: linesOfSize(2 * 1024 * 1024));

    final firstEntry = body.split('\n')[1];
    expect(firstEntry, startsWith('line '));
  });

  test('survives a header that already fills the budget', () {
    final body = buildLogUploadBody(header: 'x' * logUploadMaxBytes, entries: 'entries\n');

    expect(body, isNot(contains('entries')));
  });

  test('an oversized log loses its old remote-input lines before it loses its start', () {
    final remote = StringBuffer();
    for (var i = 0; i < 12000; i++) {
      remote.writeln(
        '[18:53:27.723] [DEBUG] AppleTvRemoteTouchService: native press=right(3) phase=0 uipress=$i ${'x' * 60}',
      );
      remote.writeln('[18:53:27.724] [DEBUG] TextInputDiag FocusableWrapper: node=null received key=$i ${'x' * 60}');
    }
    final entries =
        '[18:00:00.000] [INFO] session start\n$remote'
        '[20:11:35.631] [WARNING] System memory pressure\n'
        '[20:12:10.797] [DEBUG] AppleTvRemoteTouchService: the press the report is about\n';
    expect(utf8.encode(entries).length, greaterThan(logUploadMaxBytes));

    final body = buildLogUploadBody(header: 'Pleya v2.8.1', entries: entries);

    expect(utf8.encode(body).length, lessThanOrEqualTo(logUploadMaxBytes));
    expect(body, contains('session start'), reason: 'the start of the session survives');
    expect(body, contains('older remote-input debug lines left out'));
    expect(body, contains('System memory pressure'));
    expect(body, endsWith('the press the report is about\n'), reason: 'the newest remote lines stay');
  });
}
