import 'dart:io';

import 'package:yaml/yaml.dart';

/// One entry from `pleya_verify/automation_ids.yaml` — the generated mirror
/// of `AutomationIds.catalog()` (`lib/automation/automation_ids.dart`,
/// `tool/generate_automation_ids_yaml.dart`).
typedef AutomationIdEntry = ({String id, String role, bool instanceable});

/// The set of automation ids a scenario is allowed to reference, loaded
/// from the generated yaml rather than duplicating the Dart catalog (the
/// runner package has no dependency on the Flutter app).
class AutomationIdCatalog {
  final Map<String, AutomationIdEntry> _byId;

  AutomationIdCatalog._(this._byId);

  factory AutomationIdCatalog.fromYaml(String contents) {
    final doc = loadYaml(contents) as YamlMap;
    final ids = doc['ids'] as YamlList;
    final byId = <String, AutomationIdEntry>{};
    for (final raw in ids) {
      final entry = raw as YamlMap;
      final id = entry['id'] as String;
      byId[id] = (id: id, role: entry['role'] as String, instanceable: entry['instanceable'] as bool);
    }
    return AutomationIdCatalog._(byId);
  }

  factory AutomationIdCatalog.fromFile(File file) => AutomationIdCatalog.fromYaml(file.readAsStringSync());

  bool contains(String baseId) => _byId.containsKey(baseId);

  bool isInstanceable(String baseId) => _byId[baseId]?.instanceable ?? false;

  Iterable<AutomationIdEntry> get entries => _byId.values;
}
