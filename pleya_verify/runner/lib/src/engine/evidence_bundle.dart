import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const JsonEncoder _prettyJson = JsonEncoder.withIndent('  ');

/// Writes one scenario run's evidence to `.build/pleya-verify/<run-id>/` —
/// the fixed shape Fase 8 requires: `manifest.json`, `report.md`,
/// `scenario.resolved.yaml`, `screenshots/`, `ui-tree/`, `focus-trace.json`,
/// `fixture/requests.jsonl`, `app.log`, `driver.log`.
class EvidenceBundle {
  final Directory dir;

  EvidenceBundle(this.dir) {
    dir.createSync(recursive: true);
    Directory('${dir.path}/screenshots').createSync(recursive: true);
    Directory('${dir.path}/ui-tree').createSync(recursive: true);
    Directory('${dir.path}/fixture').createSync(recursive: true);
  }

  void writeManifest(Map<String, Object?> manifest) =>
      File('${dir.path}/manifest.json').writeAsStringSync(_prettyJson.convert(manifest));

  void writeReport(String markdown) => File('${dir.path}/report.md').writeAsStringSync(markdown);

  void writeResolvedScenario(String yamlSource) =>
      File('${dir.path}/scenario.resolved.yaml').writeAsStringSync(yamlSource);

  void writeFocusTrace(List<Map<String, Object?>> entries) =>
      File('${dir.path}/focus-trace.json').writeAsStringSync(_prettyJson.convert(entries));

  /// One JSON object per line, oldest first — same shape `/v1/logs` returns.
  void writeAppLog(List<Map<String, Object?>> entries) =>
      File('${dir.path}/app.log').writeAsStringSync(entries.map(jsonEncode).join('\n'));

  void writeDriverLog(List<String> lines) => File('${dir.path}/driver.log').writeAsStringSync(lines.join('\n'));

  /// Empty when the scenario never talked to a fixture server — still
  /// created, per the plan's "volledige bundel" requirement, rather than
  /// silently absent.
  void writeFixtureRequests(List<Map<String, Object?>> requests) =>
      File('${dir.path}/fixture/requests.jsonl').writeAsStringSync(requests.map(jsonEncode).join('\n'));

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
