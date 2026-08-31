import 'dart:convert';
import 'dart:io';

import 'package:pleya_verify_runner/src/engine/evidence_bundle.dart';
import 'package:test/test.dart';

/// Evidence bundles get attached to issues and uploaded as CI artifacts, so
/// every text stream that can quote a real URL or header has to be redacted
/// on its way to disk. `redact_test.dart` proves the redaction rules
/// themselves; this proves they are actually *wired into* the writer —
/// which they were not, for the whole of Fases 6-10.
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pleya-verify-bundle-test');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  String read(String relative) => File('${dir.path}/$relative').readAsStringSync();

  test('app.log redacts credentials, including ones nested inside an entry', () {
    EvidenceBundle(dir).writeAppLog([
      {'level': 'info', 'message': 'GET https://media.example.com/library?X-Plex-Token=sk-real-secret-value'},
      {
        'level': 'debug',
        'request': {
          'headers': {'Authorization': 'Bearer eyJreal.token.value'},
        },
      },
    ]);

    final log = read('app.log');
    expect(log, isNot(contains('sk-real-secret-value')));
    expect(log, isNot(contains('eyJreal.token.value')));
    expect(log, contains('[REDACTED]'));

    // Still valid JSON per line — an evidence file that redaction turned
    // into garbage is not evidence. Running the plain-text rules over
    // encoded JSON used to eat the closing `"}`.
    for (final line in log.split('\n')) {
      expect(() => jsonDecode(line), returnsNormally, reason: 'not valid JSON after redaction: $line');
    }
  });

  test('driver.log redacts credentials', () {
    EvidenceBundle(dir).writeDriverLog([
      'launching /path/Pleya.app',
      'sign_in POST base_url=https://fixture.local password=hunter2-real',
    ]);

    final log = read('driver.log');
    expect(log, isNot(contains('hunter2-real')));
    expect(log, contains('launching /path/Pleya.app'));
  });

  test('fixture/requests.jsonl redacts credentials', () {
    EvidenceBundle(dir).writeFixtureRequests([
      {'method': 'GET', 'path': '/Items?api_key=real-jellyfin-key'},
    ]);

    final log = read('fixture/requests.jsonl');
    expect(log, isNot(contains('real-jellyfin-key')));
    expect(log, contains('api_key=[REDACTED]'));
  });

  test('report.md redacts credentials', () {
    EvidenceBundle(dir).writeReport('# run\n\nfailed on: Authorization: Bearer real-token-here\n');

    expect(read('report.md'), isNot(contains('real-token-here')));
  });

  test('manifest.json is written verbatim — it is machine-read, and its free-text fields '
      'are redacted where they are produced', () {
    EvidenceBundle(dir).writeManifest({
      'result': 'PASS',
      'instance': {'port': 47318},
    });

    final manifest = read('manifest.json');
    expect(manifest, contains('"port": 47318'));
    expect(manifest, contains('"result": "PASS"'));
  });

  test('an empty log still produces the file, so a bundle is never silently incomplete', () {
    EvidenceBundle(dir)
      ..writeAppLog(const [])
      ..writeFixtureRequests(const []);

    expect(File('${dir.path}/app.log').existsSync(), isTrue);
    expect(File('${dir.path}/fixture/requests.jsonl').existsSync(), isTrue);
  });
}
