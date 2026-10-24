// Usage: dart run tool/crown_calibration_report.dart exported-session.json [...]
import 'dart:convert';
import 'dart:io';

num median(List<num> values) {
  final sorted = [...values]..sort();
  final n = sorted.length;
  return n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

void main(List<String> paths) {
  if (paths.isEmpty) {
    stderr.writeln('Usage: dart run tool/crown_calibration_report.dart session.json [...]');
    exitCode = 64;
    return;
  }
  stdout.writeln(
    'Condition | Library | Task | Trials/success/abort | Median seconds (worst) | Median overshoot (worst) | Median corrections (worst) | Median absolute final error (worst) | Median release drift (worst) | Readable/helpful',
  );
  stdout.writeln('--- | ---: | --- | --- | --- | --- | --- | --- | --- | ---');
  for (final path in paths) {
    final data = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    if (data['schema'] != 1) throw FormatException('Unsupported calibration schema: $path');
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final raw in data['attempts'] as List) {
      final attempt = raw as Map<String, dynamic>;
      final key = '${attempt['library_size']} | ${attempt['task']}';
      (groups[key] ??= []).add(attempt);
    }
    for (final entry in groups.entries) {
      final trials = entry.value;
      // Aborts must remain visible; never silently pool them with successes.
      final measured = trials.where((t) => t['aborted'] == false && t['duration_us'] != null).toList();
      String metric(String key, {num divisor = 1}) {
        if (measured.isEmpty) return 'unmeasured';
        final values = measured
            .map((t) => (key == 'final_error_titles' ? (t[key] as num).abs() : t[key] as num) / divisor)
            .toList();
        return '${median(values).toStringAsFixed(2)} (${values.reduce((a, b) => a > b ? a : b).toStringAsFixed(2)})';
      }

      stdout.writeln(
        '${data['condition']} | ${entry.key} | ${trials.length}/${trials.where((t) => t['success'] == true).length}/${trials.where((t) => t['aborted'] == true).length} | ${metric('duration_us', divisor: 1000000)} | ${metric('overshoot_titles')} | ${metric('corrections')} | ${metric('final_error_titles')} | ${metric('post_release_drift_titles')} | ${measured.where((t) => t['position_readable'] == true).length}/${measured.where((t) => t['haptics_helpful'] == true).length} of ${measured.length}',
      );
    }
    stdout.writeln(
      '\n$path: complete=${data['complete']}; source=${data['source_commit']}; physical identity=${data['physical_device']}.',
    );
  }
  stdout.writeln(
    '\nNo automatic winner: compare every task and size, including failure counts and worst attempts. Replay is technical evidence, not physical usability evidence.',
  );
}
