import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../assistant/assistant_memory.dart';
import '../../../assistant/assistant_memory_host.dart';
import '../../../assistant/assistant_memory_overview.dart';
import '../../../services/memory/memory_service.dart';
import '../../../services/memory/memory_validation.dart';
import '../../../utils/app_logger.dart';

/// What the body of the memory screen shows.
enum MemoryScreenView {
  loading,

  /// The facts could not be read. Never drawn as an empty memory.
  error,

  /// A children's profile: the facts as a list, to look at and to wipe.
  kids,
  off,
  empty,

  /// Big P is writing the overview (43 B).
  writing,
  overview,

  /// The facts per category, where no overview could be written.
  list,
}

/// What the line under the title says.
enum MemoryScreenStatus { none, error, kids, off, empty, waiting, asking, writing, updated, updatedOn, list }

/// The state of Instellingen > Big P > Geheugen for one profile session: the
/// facts, the switch, the written overview and the field under it. The main
/// screen and the list "Herinneringen" share one instance, so a change in the
/// list is the change the overview is written again for.
///
/// Every write goes through [MemoryService]; nothing of a fact is logged.
class MemoryScreenModel extends ChangeNotifier {
  MemoryScreenModel({
    required this.memory,
    required this.writer,
    required this.host,
    required this._kidsAges,
    required this._locale,
    DateTime Function()? now,
    this.kidsChanges,
    this.ownsHost = true,
  }) : _now = now ?? DateTime.now {
    host.addListener(_onHost);
    kidsChanges?.addListener(_onKidsChanged);
  }

  final AssistantMemoryServices memory;
  final AssistantMemoryOverviewWriter writer;

  /// The run behind "Vraag of werk bij" and the follow-up questions.
  final AssistantMemoryHost host;

  /// Fires when the children's switch of the profile changes.
  final Listenable? kidsChanges;

  /// Whether [dispose] also ends [host].
  final bool ownsHost;
  final Future<List<int>> Function() _kidsAges;
  final String Function() _locale;
  final DateTime Function() _now;

  bool _disposed = false;
  bool _loaded = false;
  bool _enabled = false;
  bool _kids = false;
  bool _writing = false;
  bool _answerShown = false;
  int _ensures = 0;
  List<MemoryFact>? _facts;
  List<int> _ages = const [];
  MemoryOverviewText? _overview;
  DateTime? _writtenAt;

  MemoryService get _service => memory.service;

  /// The facts, newest change first; null when they could not be read.
  List<MemoryFact>? get facts => _facts;
  int get count => _facts?.length ?? 0;
  bool get enabled => _enabled;
  bool get kids => _kids;

  /// The children's ages from Kinderprofiel, sorted. Never part of the memory.
  List<int> get kidsAges => _ages;
  MemoryOverviewText? get overview => _overview;

  /// When the overview on screen was written.
  DateTime? get writtenAt => _writtenAt;

  /// The field takes a question: the memory is on, this is no children's
  /// profile and the facts could be read.
  bool get canAsk => _loaded && _enabled && !_kids && _facts != null;

  /// The answer of the last question stands above the field.
  bool get answerShown => _answerShown && host.question != null;

  MemoryScreenView get view {
    if (!_loaded) return MemoryScreenView.loading;
    if (_facts == null) return MemoryScreenView.error;
    if (_kids) return MemoryScreenView.kids;
    if (!_enabled) return MemoryScreenView.off;
    if (_facts!.isEmpty) return MemoryScreenView.empty;
    if (_writing) return MemoryScreenView.writing;
    return _overview == null ? MemoryScreenView.list : MemoryScreenView.overview;
  }

  MemoryScreenStatus get status => switch (view) {
    MemoryScreenView.loading => MemoryScreenStatus.none,
    MemoryScreenView.error => MemoryScreenStatus.error,
    MemoryScreenView.kids => MemoryScreenStatus.kids,
    MemoryScreenView.off => MemoryScreenStatus.off,
    _ when host.proposal != null => MemoryScreenStatus.waiting,
    _ when host.busy => MemoryScreenStatus.asking,
    MemoryScreenView.empty => MemoryScreenStatus.empty,
    MemoryScreenView.writing => MemoryScreenStatus.writing,
    MemoryScreenView.list => MemoryScreenStatus.list,
    MemoryScreenView.overview => _justWritten ? MemoryScreenStatus.updated : MemoryScreenStatus.updatedOn,
  };

  bool get _justWritten {
    final at = _writtenAt;
    return at == null || _now().difference(at).abs() < const Duration(minutes: 10);
  }

  /// The facts of [category] that hold every word of [query], as
  /// [MemoryService.list] matches them.
  List<MemoryFact> filtered({MemoryCategory? category, String query = ''}) {
    final words = memoryValueKey(query).split(' ').where((word) => word.isNotEmpty).toList();
    return [
      for (final fact in _facts ?? const <MemoryFact>[])
        if ((category == null || fact.category == category) && words.every(memoryValueKey(fact.value).contains)) fact,
    ];
  }

  /// Reads the profile's state and shows the overview, writing it when the
  /// stored one is out of date.
  Future<void> load() async {
    await _read();
    await _ensure();
  }

  /// The user's "Overzicht opnieuw schrijven", and "Opnieuw proberen".
  Future<void> rewrite() async {
    await _read();
    await _ensure(rewrite: true);
  }

  Future<void> setEnabled(bool value) async {
    if (!memory.profileCurrent) return;
    await _service.setEnabled(value);
    if (!value) host.cancel();
    await load();
  }

  Future<MemoryResult> add(String value, MemoryCategory category) =>
      _write(() => _service.add(value: value, category: category, source: MemorySource.settingsManual));

  /// A manual change: the service marks the fact as edited by hand.
  Future<MemoryResult> update(MemoryFact fact, {required String value, required MemoryCategory category}) =>
      _write(() => _service.update(fact.id, value: value == fact.value ? null : value, category: category));

  Future<MemoryResult> delete(MemoryFact fact) => _write(() => _service.delete(fact.id));

  /// Wipes every fact of the profile. Allowed with the memory off and on a
  /// children's profile; the children's ages are not part of it.
  Future<MemoryResult> clearAll() {
    host.cancel();
    _answerShown = false;
    return _write(_service.clearAll);
  }

  void dismissAnswer() {
    if (host.proposal != null || !_answerShown) return;
    _answerShown = false;
    _notify();
  }

  Future<MemoryResult> _write(Future<MemoryResult> Function() action) async {
    // The service of a profile that is no longer the active one writes nothing.
    if (!memory.profileCurrent) return const MemoryResult(MemoryCode.profileGone);
    final result = await action();
    if (result.ok) await load();
    return result;
  }

  Future<void> _read() async {
    final current = memory.profileCurrent;
    final enabled = current && await _service.enabled;
    final kids = await memory.kidsNow;
    final facts = current ? await _service.tryList() : null;
    var ages = const <int>[];
    try {
      ages = [...await _kidsAges()]..sort();
    } catch (e) {
      appLogger.w('Memory screen: children ages unreadable: ${e.runtimeType}');
    }
    if (_disposed) return;
    _enabled = enabled;
    _kids = kids;
    _facts = facts;
    _ages = ages;
    _loaded = true;
    if (kids || !enabled || facts == null || facts.isEmpty) {
      _overview = null;
      _writing = false;
    }
    _notify();
  }

  Future<void> _ensure({bool rewrite = false}) async {
    if (view == MemoryScreenView.loading || !canAsk || count == 0) return;
    final run = ++_ensures;
    _writing = true;
    _notify();
    var result = await writer.ensure(locale: _locale(), rewrite: rewrite);
    // The facts changed while Big P wrote: once more, from the new facts.
    if (result.state == MemoryOverviewState.stale && run == _ensures && !_disposed) {
      result = await writer.ensure(locale: _locale());
    }
    final shown = result.state == MemoryOverviewState.current || result.state == MemoryOverviewState.written;
    final at = !shown
        ? null
        : result.state == MemoryOverviewState.written
        ? _now()
        : (await _service.overview())?.generatedAt.toLocal();
    if (_disposed || run != _ensures) return;
    _overview = shown ? result.text : null;
    _writtenAt = at;
    _writing = false;
    _notify();
  }

  void _onHost() {
    if (_disposed) return;
    if (host.busy || host.proposal != null) _answerShown = true;
    if (host.overviewStale && !host.busy) {
      host.overviewWritten();
      unawaited(load());
      return;
    }
    _notify();
  }

  void _onKidsChanged() => unawaited(load());

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    host.removeListener(_onHost);
    kidsChanges?.removeListener(_onKidsChanged);
    if (ownsHost) host.dispose();
    super.dispose();
  }
}
