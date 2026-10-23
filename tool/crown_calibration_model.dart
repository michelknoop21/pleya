import 'dart:math' as math;

/// Fixed protocol: all indices are zero-based; the UI displays one-based titles.
const crownLibrarySizes = [100, 1000, 10000];
const crownRepeats = 5;
const crownRowExtent = 72.0;

String crownTitle(int index, int count) {
  final letter = String.fromCharCode(65 + index * 26 ~/ count);
  return '$letter · ${(index + 1).toString().padLeft(5, '0')}';
}

class CrownTask {
  const CrownTask(this.id, this.start, this.target, this.instruction);
  final String id;
  final int start;
  final int target;
  final String instruction;
}

List<CrownTask> crownTasks(int count) {
  final middle = count ~/ 2;
  return [
    CrownTask('one-forward', middle, middle + 1, 'Ga één titel verder en stop.'),
    CrownTask('one-back', middle, middle - 1, 'Ga één titel terug en stop.'),
    CrownTask('end', 0, count - 1, 'Ga van het begin naar het einde.'),
    CrownTask('start', count - 1, 0, 'Ga van het einde naar het begin.'),
    CrownTask('far-forward', count ~/ 5, count * 4 ~/ 5, 'Zoek de doeltitel en rem af om precies te stoppen.'),
    CrownTask('far-back', count * 4 ~/ 5, count ~/ 5, 'Zoek de doeltitel en rem af om precies te stoppen.'),
    CrownTask(
      'reverse-release',
      middle,
      middle,
      'Beweeg verder, houd 1 s stil, keer terug naar het doel en laat los. Wacht 1 s.',
    ),
  ];
}

/// A session contains 105 attempts: 7 tasks × 5 repetitions × 3 libraries.
/// Human arrival is judged from the first visible row, not an invisible pixel.
class CrownAttempt {
  CrownAttempt({required this.count, required this.task, required this.repeat});
  final int count;
  final CrownTask task;
  final int repeat;
  final samples = <Map<String, Object>>[];
  int? _startUs;
  int? _lastUs;
  late double _lastRow = task.start.toDouble();
  double _lastMovingRow = 0;
  int _direction = 0;
  bool _passed = false;
  int corrections = 0;
  double overshoot = 0;
  double postReleaseDrift = 0;
  double? _releasedRow;
  bool _hasDrag = false;
  late bool _visitedStart = task.start == 0;
  late bool _visitedEnd = task.start == count - 1;
  bool get started => _hasDrag;

  void add(Map<String, Object> sample) {
    samples.add(Map.of(sample));
    final time = sample['t_us'] as int;
    // Haptic markers, post-release samples and pointer down do not start a task.
    if (_startUs == null && sample['event'] != 'start' && sample['event'] != 'pointer_down') return;
    _startUs ??= time;
    if (sample['event'] == 'start') {
      _hasDrag = true;
      _releasedRow = null;
    }
    if (sample['event'] == 'end') _lastUs = time;
    final row = (sample['pixels'] as num).toDouble() / crownRowExtent;
    _lastRow = row;
    _visitedStart = _visitedStart || row <= .000001;
    _visitedEnd = _visitedEnd || row >= count - 1 - .000001;
    if (sample['event'] == 'end') _releasedRow = row;
    if (_releasedRow != null) postReleaseDrift = math.max(postReleaseDrift, (row - _releasedRow!).abs());
    if (sample['event'] == 'start' && samples.where((s) => s['event'] == 'start').length == 1) {
      _lastMovingRow = row;
    }
    final delta = row - _lastMovingRow;
    final nextDirection = delta.abs() < 0.000001 ? 0 : delta.sign.toInt();
    if (nextDirection != 0) {
      if (_passed && _direction != 0 && nextDirection != _direction) corrections++;
      _direction = nextDirection;
      _lastMovingRow = row;
    }
    // The whole visible target-row band counts as the target. Endpoint tasks
    // have no space beyond the target, so report their final error as well.
    final forward = task.target >= task.start;
    final beyond = (forward ? row.floor() - task.target : task.target - row.floor()).toDouble();
    if (task.start != task.target && beyond > 0) {
      _passed = true;
      overshoot = math.max(overshoot, beyond);
    }
  }

  Map<String, Object?> finish({required bool aborted, required bool? readable, required bool? hapticsHelpful}) => {
    'library_size': count,
    'task': task.id,
    'repeat': repeat,
    'start_index': task.start,
    'target_index': task.target,
    'duration_us': _startUs == null || _lastUs == null ? null : _lastUs! - _startUs!,
    'overshoot_titles': overshoot,
    'corrections': corrections,
    'post_release_drift_titles': postReleaseDrift,
    'final_error_titles': _lastRow - task.target,
    'success':
        !aborted &&
        started &&
        _lastRow.floor() == task.target &&
        (task.id != 'ends-release' || (_visitedStart && _visitedEnd)),
    'visited_start': _visitedStart,
    'visited_end': _visitedEnd,
    'aborted': aborted,
    'position_readable': readable,
    'haptics_helpful': hapticsHelpful,
    'samples': samples,
  };
}

/// Brief physical acceptance after the automatic comparison, without repeated tasks.
List<CrownTask> crownQuickTasks(int count) => [
  CrownTask('ends-release', 0, 0, 'Sleep de kroon in één haal helemaal naar onder en weer naar boven.'),
  CrownTask('one-back', count * 4 ~/ 5, count * 4 ~/ 5 - 1, 'Schuif in de lijst zelf één titel terug en laat los.'),
];
