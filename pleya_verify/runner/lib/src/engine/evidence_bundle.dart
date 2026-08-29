import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../redact.dart';

const JsonEncoder _prettyJson = JsonEncoder.withIndent('  ');

/// Writes one scenario run's evidence to `.build/pleya-verify/<run-id>/` —
/// the fixed shape Fase 8 requires: `manifest.json`, `report.md`,
/// `scenario.resolved.yaml`, `screenshots/`, `ui-tree/`, `focus-trace.json`,
/// `fixture/requests.jsonl`, `app.log`, `driver.log`.
///
/// **Every text stream that can carry a credential passes through
/// [redact] on its way to disk.** These files get attached to issues and
/// uploaded as CI artifacts, and the app log, the driver log and the
/// fixture request log all quote real URLs and headers. Redaction happens
/// on the serialized line rather than per field, so a token nested three
/// levels down in a request body is covered too. `ui-tree/*.json` is the
/// one exception that needs nothing here: node labels already go through
/// `LogRedactionManager.redact` app-side, in `AutomationRegistry.snapshot()`.
class EvidenceBundle {
  final Directory dir;

  EvidenceBundle(this.dir) {
    dir.createSync(recursive: true);
    Directory('${dir.path}/screenshots').createSync(recursive: true);
    Directory('${dir.path}/ui-tree').createSync(recursive: true);
    Directory('${dir.path}/fixture').createSync(recursive: true);
  }

  /// Not redacted here, deliberately: `manifest.json` is machine-read (the
  /// MCP layer, CI), and running a regex over structured output risks
  /// rewriting a value some tool parses. Its two free-text fields —
  /// `failure_message` and each step's `error` — are redacted where they
  /// are produced, in `run_scenario.dart`.
  void writeManifest(Map<String, Object?> manifest) =>
      File('${dir.path}/manifest.json').writeAsStringSync(_prettyJson.convert(manifest));

  void writeReport(String markdown) => File('${dir.path}/report.md').writeAsStringSync(redact(markdown));

  void writeResolvedScenario(String yamlSource) =>
      File('${dir.path}/scenario.resolved.yaml').writeAsStringSync(yamlSource);

  void writeFocusTrace(List<Map<String, Object?>> entries) =>
      File('${dir.path}/focus-trace.json').writeAsStringSync(_prettyJson.convert(entries));

  /// One JSON object per line, oldest first — same shape `/v1/logs` returns.
  void writeAppLog(List<Map<String, Object?>> entries) =>
      File('${dir.path}/app.log').writeAsStringSync(_redactedJsonLines(entries));

  void writeDriverLog(List<String> lines) =>
      File('${dir.path}/driver.log').writeAsStringSync(redact(lines.join('\n')));

  /// Empty when the scenario never talked to a fixture server — still
  /// created, per the plan's "volledige bundel" requirement, rather than
  /// silently absent.
  void writeFixtureRequests(List<Map<String, Object?>> requests) =>
      File('${dir.path}/fixture/requests.jsonl').writeAsStringSync(_redactedJsonLines(requests));

  /// Redacts the decoded entry and *then* encodes it — never the encoded
  /// text. See [redactJson]: running the plain-text rules over JSON both
  /// corrupts it (a token pattern eats the closing `"}`) and misses the
  /// `"Authorization":"Bearer …"` shape entirely.
  String _redactedJsonLines(List<Map<String, Object?>> entries) =>
      entries.map((e) => jsonEncode(redactJson(e))).join('\n');

  File saveScreenshot(String name, Uint8List bytes) {
    final file = File('${dir.path}/screenshots/$name.png');
    file.writeAsBytesSync(bytes);
    return file;
  }

  File saveUiTree(String name, Map<String, Object?> tree) {
    final file = File('${dir.path}/ui-tree/$name.json');
    file.writeAsStringSync(_prettyJson.convert(tree));
    return file;
  }
}
