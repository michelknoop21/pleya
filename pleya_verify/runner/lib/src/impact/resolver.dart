import 'dart:io';

import 'package:yaml/yaml.dart';

/// One `rules:` entry from `pleya_verify/impact-map.yaml`: a glob [pattern]
/// (`**` matches across `/`, `*` matches within one segment) mapped to the
/// scenario [tags] a change under it should select.
class ImpactRule {
  final String pattern;
  final List<String> tags;

  const ImpactRule({required this.pattern, required this.tags});
}

/// One `ignored:` entry — a path that never selects a suite, with a
/// mandatory [reason] (enforced at parse time, not left to convention).
class IgnoreRule {
  final String pattern;
  final String reason;

  const IgnoreRule({required this.pattern, required this.reason});
}

/// Thrown when `impact-map.yaml` itself is malformed — most notably, an
/// `ignored:` entry without a `reason:`.
class ImpactMapParseException implements Exception {
  final String message;

  const ImpactMapParseException(this.message);

  @override
  String toString() => 'ImpactMapParseException: $message';
}

class ImpactMap {
  final String defaultSuite;
  final List<ImpactRule> rules;
  final List<IgnoreRule> ignored;

  const ImpactMap({required this.defaultSuite, required this.rules, required this.ignored});

  factory ImpactMap.fromFile(File file) => ImpactMap.fromYaml(file.readAsStringSync());

  factory ImpactMap.fromYaml(String contents) {
    final doc = loadYaml(contents) as YamlMap;

    final defaultSuite = doc['default_suite'];
    if (defaultSuite is! String) {
      throw const ImpactMapParseException('missing required field: default_suite');
    }

    final rules = <ImpactRule>[];
    for (final raw in (doc['rules'] as YamlList?) ?? const []) {
      final entry = raw as YamlMap;
      final pattern = entry['pattern'];
      final tags = entry['tags'];
      if (pattern is! String || tags is! YamlList) {
        throw ImpactMapParseException('a rules entry needs a string pattern and a tags list: $entry');
      }
      rules.add(ImpactRule(pattern: pattern, tags: tags.cast<String>()));
    }

    final ignored = <IgnoreRule>[];
    for (final raw in (doc['ignored'] as YamlList?) ?? const []) {
      final entry = raw as YamlMap;
      final pattern = entry['pattern'];
      final reason = entry['reason'];
      if (pattern is! String) {
        throw ImpactMapParseException('an ignored entry needs a string pattern: $entry');
      }
      if (reason is! String || reason.trim().isEmpty) {
        throw ImpactMapParseException("ignored pattern '$pattern' is missing a reason");
      }
      ignored.add(IgnoreRule(pattern: pattern, reason: reason));
    }

    return ImpactMap(defaultSuite: defaultSuite, rules: rules, ignored: ignored);
  }
}

/// The result of resolving a set of changed paths against an [ImpactMap].
class ImpactResult {
  /// Every scenario tag a changed path selected — always non-empty when at
  /// least one changed path was given, per the plan's hard rule: an unknown
  /// path is `inconclusive`, not a silently empty selection, so it falls
  /// back to [ImpactMap.defaultSuite] rather than selecting nothing.
  final Set<String> tags;

  /// Paths matched by an `ignored:` rule, with why.
  final Map<String, String> ignoredPaths;

  /// Paths that matched no `rules:` entry and no `ignored:` entry — these
  /// are what pulled [ImpactMap.defaultSuite] into [tags].
  final List<String> unmatchedPaths;

  /// Which tags each non-ignored, matched path contributed — for a report,
  /// not consulted by [tags] itself.
  final Map<String, List<String>> matchedBy;

  const ImpactResult({
    required this.tags,
    required this.ignoredPaths,
    required this.unmatchedPaths,
    required this.matchedBy,
  });
}

ImpactResult resolveImpact(List<String> changedPaths, ImpactMap map) {
  final tags = <String>{};
  final ignoredPaths = <String, String>{};
  final unmatchedPaths = <String>[];
  final matchedBy = <String, List<String>>{};

  for (final path in changedPaths) {
    final ignoreRule = map.ignored.where((r) => _globMatches(r.pattern, path)).firstOrNull;
    if (ignoreRule != null) {
      ignoredPaths[path] = ignoreRule.reason;
      continue;
    }

    final matchingRules = map.rules.where((r) => _globMatches(r.pattern, path)).toList();
    if (matchingRules.isEmpty) {
      unmatchedPaths.add(path);
      tags.add(map.defaultSuite);
      continue;
    }

    final pathTags = <String>{for (final r in matchingRules) ...r.tags};
    tags.addAll(pathTags);
    matchedBy[path] = pathTags.toList();
  }

  return ImpactResult(tags: tags, ignoredPaths: ignoredPaths, unmatchedPaths: unmatchedPaths, matchedBy: matchedBy);
}

/// Minimal glob match: `**` matches any run of characters including `/`,
/// `*` matches any run within one path segment (not `/`), everything else
/// is literal. Deliberately not `package:glob` — the vocabulary this needs
/// is this small, and it keeps the runner's dependency footprint minimal.
bool _globMatches(String pattern, String path) {
  final buffer = StringBuffer('^');
  var i = 0;
  while (i < pattern.length) {
    if (pattern.startsWith('**', i)) {
      buffer.write('.*');
      i += 2;
    } else if (pattern[i] == '*') {
      buffer.write('[^/]*');
      i += 1;
    } else {
      buffer.write(RegExp.escape(pattern[i]));
      i += 1;
    }
  }
  buffer.write(r'$');
  return RegExp(buffer.toString()).hasMatch(path);
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
