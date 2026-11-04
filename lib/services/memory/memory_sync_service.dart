part of 'memory_service.dart';

/// One explicit account binding. Facts stay in MemoryStore; this row only holds
/// the confirmed base and mutation bookkeeping needed to survive offline/crash.
class MemorySyncService extends ChangeNotifier {
  MemorySyncService({
    required this.memory,
    required this.transportFor,
    required this.isEligible,
    required this.isCurrent,
  }) {
    memory.addListener(_onMemoryChanged);
  }

  final MemoryService memory;
  final Future<MemorySyncTransport?> Function(String accountKey) transportFor;
  final bool Function() isEligible;
  final bool Function() isCurrent;
  _MemorySyncState? _state;
  MemorySyncStatus _status = MemorySyncStatus.local;
  Future<void>? _flight;
  bool _disposed = false;
  bool _applying = false;
  bool _again = false;
  int _bindingGeneration = 0;
  DateTime? _lastSuccess;
  DateTime? _retryAfter;
  int _failures = 0;
  Timer? _localTimer;

  String? get accountKey => _state?.accountKey;
  MemorySyncStatus get status => _status;
  DateTime? get lastSuccess => _lastSuccess;
  bool get hasPendingClear => _state?.clearGeneration != null;
  List<MemorySyncConflict> get conflicts => List.unmodifiable(_state?.conflicts ?? const []);
  MemorySyncSnapshot? get quarantine => _state?.quarantine;
  bool get _allowed => !_disposed && isCurrent() && isEligible() && !memory._profileGone;

  Future<void> load() async {
    try {
      final json = await memory._store.syncState();
      if (_disposed || !isCurrent()) return;
      _state = json == null ? null : _MemorySyncState.fromJson(json);
      _refreshStatus();
    } catch (_) {
      _setStatus(MemorySyncStatus.error);
    }
  }

  Future<MemorySyncPreview> preview(String key) async {
    if (!_allowed) throw const MemorySyncFailure('unavailable');
    final transport = await transportFor(key);
    if (!_allowed || transport == null) throw const MemorySyncFailure('unavailable');
    final remote = await transport.fetch();
    _checkSnapshot(remote);
    final local = await memory.tryList();
    if (!_allowed || local == null) throw const MemorySyncFailure('unavailable');
    return MemorySyncPreview(
      accountKey: key,
      remote: remote,
      deviceFacts: List.unmodifiable(local),
      localFacts: List.unmodifiable(local.where((f) => f.category != MemoryCategory.household)),
    );
  }

  Future<void> connect(MemorySyncPreview preview, {Set<String>? selectedIds}) async {
    if (!_allowed) throw const MemorySyncFailure('unavailable');
    final selected = selectedIds ?? preview.localFacts.map((f) => f.id).toSet();
    if (!selected.every((id) => preview.localFacts.any((f) => f.id == id))) {
      throw const MemorySyncFailure('stale_preview');
    }
    _bindingGeneration++;
    _retryAfter = null;
    _failures = 0;
    await memory._store.transaction(() async {
      if (!_allowed) throw const MemorySyncFailure('unavailable');
      final local = [for (final row in await memory._store.all()) MemoryFact.fromRow(row)];
      for (final old in preview.localFacts.where((f) => selected.contains(f.id))) {
        if (!local.any((f) => sameSyncFact(f, old))) throw const MemorySyncFailure('stale_preview');
      }
      // Never carry another account's queue into the newly confirmed binding.
      final state = _MemorySyncState(
        accountKey: preview.accountKey,
        base: preview.remote,
        generation: 1,
        excluded: local.where((f) => !selected.contains(f.id)).map((f) => f.id).toSet(),
      );
      final desired = <String, MemoryFact>{for (final f in preview.remote.facts) f.id: f};
      for (final fact in local.where((f) => selected.contains(f.id))) {
        final existing = desired[fact.id];
        if (existing != null && !sameSyncFact(existing, fact)) {
          state.conflicts.add(MemorySyncConflict(id: fact.id, local: fact, server: existing));
        } else if (!desired.values.any((f) => memoryValueKey(f.value) == memoryValueKey(fact.value))) {
          desired[fact.id] = fact;
        }
      }
      // Equal imported text with a different id must not leave a hidden local duplicate.
      final selectedLocal = local.where((f) => selected.contains(f.id)).map((f) => f.id).toSet();
      await _writeFacts(state, local, desired.values.toList(), removeIds: selectedLocal);
      await memory._store.putSyncState(state.toJson());
      _state = state;
    });
    _notifyMemory();
    _refreshStatus();
    await sync();
  }

  Future<void> disconnect() async {
    _bindingGeneration++;
    await memory._store.transaction(memory._store.removeSyncState);
    _state = null;
    _lastSuccess = null;
    _retryAfter = null;
    _failures = 0;
    _setStatus(MemorySyncStatus.local);
  }

  Future<void> sync({bool force = false}) {
    if (force) _retryAfter = null;
    if (_retryAfter != null && DateTime.now().isBefore(_retryAfter!)) return Future.value();
    final running = _flight;
    if (running != null) return running;
    final operation = _run();
    _flight = operation;
    return operation.whenComplete(() {
      _flight = null;
      if (_again && !_disposed) {
        _again = false;
        scheduleMicrotask(sync);
      }
    });
  }

  Future<void> _run() async {
    if (!_allowed) {
      if (_state != null) _setStatus(MemorySyncStatus.unavailable);
      return;
    }
    final binding = _bindingGeneration;
    String? key;
    MemorySyncTransport? transport;
    bool sentClear = false;
    try {
      await load();
      final state = _state;
      if (state == null || state.quarantine != null || state.conflicts.isNotEmpty) return;
      key = state.accountKey;
      transport = await transportFor(key);
      if (!_active(binding, key)) return;
      if (transport == null) {
        _setStatus(MemorySyncStatus.unavailable);
        return;
      }
      _setStatus(MemorySyncStatus.syncing);
      if (state.clearGeneration == null) {
        final remote = await transport.fetch();
        _checkSnapshot(remote);
        if (!_active(binding, key)) return;
        await _receive(remote, binding, key);
      }
      if (!_active(binding, key)) return;
      final context = await _context();
      final fresh = context.$1;
      final facts = _shared(fresh, context.$2);
      if (fresh.quarantine != null || fresh.conflicts.isNotEmpty) {
        _refreshStatus();
        return;
      }
      if (fresh.clearGeneration == null && _sameFacts(facts, fresh.base.facts)) {
        _lastSuccess = DateTime.now().toUtc();
        _retryAfter = null;
        _failures = 0;
        _setStatus(MemorySyncStatus.synced);
        return;
      }
      if (!_active(binding, key)) return;
      final sentGeneration = fresh.generation;
      final clear = fresh.clearGeneration != null;
      sentClear = clear;
      final sentFacts = clear ? <MemoryFact>[] : facts;
      await memory._store.transaction(() async {
        final current = await _readState();
        if (!_active(binding, key!) || current.accountKey != key) return;
        current.inFlight = MemorySyncSnapshot(epoch: fresh.base.epoch, revision: fresh.base.revision, facts: sentFacts);
        current.sentGeneration = sentGeneration;
        await memory._store.putSyncState(current.toJson());
      });
      if (!_active(binding, key)) return;
      final accepted = clear
          ? await transport.clear(epoch: fresh.base.epoch, baseRevision: fresh.base.revision)
          : await transport.replace(epoch: fresh.base.epoch, baseRevision: fresh.base.revision, facts: sentFacts);
      _checkSnapshot(accepted);
      if (!_active(binding, key)) return;
      await _acknowledge(accepted, sentFacts, sentGeneration, clear, binding, key);
      if (!_active(binding, key)) return;
      _lastSuccess = DateTime.now().toUtc();
      _retryAfter = null;
      _failures = 0;
      _refreshStatus();
    } catch (error) {
      if (sentClear &&
          error is MemorySyncFailure &&
          const {'memory.conflict', 'memory.epoch_changed'}.contains(error.code) &&
          key != null &&
          transport != null &&
          _active(binding, key)) {
        try {
          final remote = await transport.fetch();
          _checkSnapshot(remote);
          await memory._store.transaction(() async {
            final current = await _readState();
            if (!_active(binding, key!) || current.accountKey != key || current.clearGeneration == null) return;
            current.quarantine = remote;
            current.inFlight = null;
            await memory._store.putSyncState(current.toJson());
            _state = current;
          });
          if (_active(binding, key)) _refreshStatus();
          return;
        } catch (_) {
          // Keep the pending clear without importing facts or silently retrying new data.
        }
      }
      if (error is MemorySyncFailure && error.code == 'memory.deleted' && key != null && _active(binding, key)) {
        try {
          await _stageDeletedCandidates(binding, key);
          return;
        } catch (_) {
          // A failed local transaction leaves its original facts and queue intact.
        }
      }
      if (!_disposed && binding == _bindingGeneration && isCurrent()) {
        const delays = [5, 15, 30, 60, 120, 300];
        final index = _failures < delays.length ? _failures++ : delays.length - 1;
        _retryAfter = DateTime.now().add(Duration(seconds: delays[index]));
        _setStatus(MemorySyncStatus.error);
      }
    }
  }

  Future<void> _stageDeletedCandidates(int binding, String key) async {
    await memory._store.transaction(() async {
      final state = await _readState();
      if (!_active(binding, key) || state.accountKey != key) return;
      final local = [for (final row in await memory._store.all()) MemoryFact.fromRow(row)];
      final known = state.base.facts.map((f) => f.id).toSet();
      final shared = _shared(state, local);
      state.conflicts = [
        for (final fact in shared)
          if (!known.contains(fact.id)) MemorySyncConflict(id: fact.id, local: fact),
      ];
      if (state.conflicts.isEmpty) throw const MemorySyncFailure('memory.deleted');
      await _writeFacts(state, local, shared.where((f) => known.contains(f.id)).toList());
      state.inFlight = null;
      await memory._store.putSyncState(state.toJson());
      _state = state;
    });
    _notifyMemory();
    _refreshStatus();
  }

  Future<(_MemorySyncState, List<MemoryFact>)> _context() => memory._store.transaction(
    () async => (await _readState(), [for (final row in await memory._store.all()) MemoryFact.fromRow(row)]),
  );

  Future<_MemorySyncState> _readState() async {
    final json = await memory._store.syncState();
    if (json == null) throw const MemorySyncFailure('unavailable');
    return _MemorySyncState.fromJson(json);
  }

  bool _active(int generation, String key) => _allowed && generation == _bindingGeneration && _state?.accountKey == key;

  Future<void> _receive(MemorySyncSnapshot remote, int binding, String key) async {
    bool changed = false;
    await memory._store.transaction(() async {
      final state = await _readState();
      if (!_active(binding, key) || state.accountKey != key) return;
      if (state.clearGeneration != null) return;
      final local = [for (final row in await memory._store.all()) MemoryFact.fromRow(row)];
      final shared = _shared(state, local);
      if (remote.epoch != state.base.epoch) {
        // Old pending creates belong to the old epoch too. Preserve only inactive drafts.
        final previous = {for (final f in state.base.facts) f.id: f};
        state.conflicts = [
          for (final fact in shared)
            if (!sameSyncFact(fact, previous[fact.id])) MemorySyncConflict(id: fact.id, local: fact),
        ];
        state.quarantine = remote;
        state.clearGeneration = null;
        state.inFlight = null;
        await _writeFacts(state, local, const []);
        if (remote.facts.isEmpty && state.conflicts.isEmpty) {
          state.base = remote;
          state.quarantine = null;
        }
      } else {
        if (remote.revision < state.base.revision) throw const MemorySyncFailure('revision_rollback');
        final receipt = state.inFlight;
        final confirmedReceipt = receipt != null && _sameFacts(receipt.facts, remote.facts);
        final base = confirmedReceipt ? receipt.facts : state.base.facts;
        final merged = _merge(base, shared, remote.facts);
        state.conflicts = merged.$2;
        await _writeFacts(state, local, merged.$1);
        state.base = remote;
        if (confirmedReceipt) state.inFlight = null;
        if (state.conflicts.isEmpty && state.clearGeneration == null && _sameFacts(merged.$1, remote.facts)) {
          state.ackGeneration = state.generation;
        }
      }
      await memory._store.putSyncState(state.toJson());
      changed = !_sameFacts(local, [for (final row in await memory._store.all()) MemoryFact.fromRow(row)]);
      _state = state;
    });
    if (changed) _notifyMemory();
  }

  Future<void> _acknowledge(
    MemorySyncSnapshot accepted,
    List<MemoryFact> sent,
    int generation,
    bool clear,
    int binding,
    String key,
  ) async {
    await memory._store.transaction(() async {
      final state = await _readState();
      if (!_active(binding, key) || state.accountKey != key) return;
      if (state.clearGeneration != null && state.clearGeneration! > generation) {
        // A newer wipe supersedes this PUT; retain only its stamp for the queued clear.
        state.base = MemorySyncSnapshot(epoch: accepted.epoch, revision: accepted.revision, facts: []);
        state.inFlight = null;
        await memory._store.putSyncState(state.toJson());
        _state = state;
        _again = true;
        return;
      }
      final local = [for (final row in await memory._store.all()) MemoryFact.fromRow(row)];
      final shared = _shared(state, local);
      final merged = _merge(sent, shared, accepted.facts);
      await _writeFacts(state, local, merged.$1);
      state.base = accepted;
      state.conflicts = merged.$2;
      state.inFlight = null;
      if (_sameFacts(merged.$1, accepted.facts)) state.ackGeneration = state.generation;
      if (clear && state.clearGeneration != null && state.clearGeneration! <= generation) state.clearGeneration = null;
      await memory._store.putSyncState(state.toJson());
      _state = state;
      if (state.generation > generation) _again = true;
    });
    _notifyMemory();
  }

  Future<void> acceptRemoteReset() async {
    if (!_allowed) throw const MemorySyncFailure('unavailable');
    await memory._store.transaction(() async {
      final state = await _readState();
      final reset = state.quarantine;
      if (!_allowed || reset == null) return;
      final local = [for (final row in await memory._store.all()) MemoryFact.fromRow(row)];
      final clearing = state.clearGeneration != null;
      if (!clearing) await _writeFacts(state, local, reset.facts);
      state.base = clearing ? MemorySyncSnapshot(epoch: reset.epoch, revision: reset.revision, facts: []) : reset;
      state.quarantine = null;
      // Discarding old queued edits is explicit; no old-epoch fact is uploaded.
      state.conflicts = [];
      if (!clearing) state.ackGeneration = state.generation;
      await memory._store.putSyncState(state.toJson());
      _state = state;
    });
    _notifyMemory();
    _refreshStatus();
    if (hasPendingClear) await sync(force: true);
  }

  Future<void> resolveConflict(String id, MemorySyncChoice choice) async {
    if (!_allowed) throw const MemorySyncFailure('unavailable');
    await memory._store.transaction(() async {
      final state = await _readState();
      if (!_allowed || state.quarantine != null) throw const MemorySyncFailure('unavailable');
      final matches = state.conflicts.where((c) => c.id == id);
      if (matches.isEmpty) return;
      final conflict = matches.first;
      final local = [for (final row in await memory._store.all()) MemoryFact.fromRow(row)];
      final desired = {for (final fact in _shared(state, local)) fact.id: fact};
      if (choice != MemorySyncChoice.server) {
        desired.remove(id);
        final own = conflict.local;
        if (own != null) {
          final keepId = choice == MemorySyncChoice.local && conflict.server != null;
          final copy = MemoryFact(
            id: keepId ? own.id : memory._newId(),
            value: own.value,
            category: own.category,
            source: MemorySource.settingsManual,
            createdAt: own.createdAt,
            updatedAt: memory._now().toUtc(),
          );
          desired[copy.id] = copy;
        }
        if (choice == MemorySyncChoice.both && conflict.server != null) desired[id] = conflict.server!;
      }
      state.conflicts.removeWhere((c) => c.id == id);
      state.generation++;
      await _writeFacts(state, local, desired.values.toList());
      await memory._store.putSyncState(state.toJson());
      _state = state;
    });
    _notifyMemory();
    _refreshStatus();
    await sync();
  }

  List<MemoryFact> _shared(_MemorySyncState state, List<MemoryFact> facts) => [
    for (final fact in facts)
      if (fact.category != MemoryCategory.household && !state.excluded.contains(fact.id)) fact,
  ];

  Future<void> _writeFacts(
    _MemorySyncState state,
    List<MemoryFact> local,
    List<MemoryFact> desired, {
    Set<String> removeIds = const {},
  }) async {
    validateSyncFacts(desired);
    final kept = local.where(
      (f) => (f.category == MemoryCategory.household || state.excluded.contains(f.id)) && !removeIds.contains(f.id),
    );
    final combined = [...kept, ...desired];
    if (combined.length > kMemoryFactLimit) throw const MemorySyncFailure('memory.limit_reached');
    final keys = <String>{};
    final ids = <String>{};
    for (final fact in combined) {
      if (!keys.add(memoryValueKey(fact.value)) || !ids.add(fact.id)) throw const MemorySyncFailure('memory.duplicate');
    }
    final previous = {for (final fact in local) fact.id: fact};
    if (combined.length == local.length &&
        combined.every((fact) {
          final old = previous[fact.id];
          return sameSyncFact(fact, old) && old!.createdAt == fact.createdAt && old.updatedAt == fact.updatedAt;
        })) {
      return;
    }
    await memory._store.replaceFacts([
      for (final fact in combined)
        AssistantMemoriesCompanion.insert(
          id: fact.id,
          profileId: memory.profileId,
          category: fact.category.id,
          value: fact.value,
          valueKey: memoryValueKey(fact.value),
          source: fact.source.id,
          createdAt: fact.createdAt.millisecondsSinceEpoch,
          updatedAt: fact.updatedAt.millisecondsSinceEpoch,
        ),
    ]);
    await memory._excludeSeenStore.save(combined.any((f) => ExcludeSeenStore.isSentence(f.value)));
  }

  (List<MemoryFact>, List<MemorySyncConflict>) _merge(
    List<MemoryFact> base,
    List<MemoryFact> local,
    List<MemoryFact> remote,
  ) {
    final before = {for (final f in base) f.id: f};
    final own = {for (final f in local) f.id: f};
    final theirs = {for (final f in remote) f.id: f};
    final result = <MemoryFact>[];
    final conflicts = <MemorySyncConflict>[];
    for (final id in {...before.keys, ...own.keys, ...theirs.keys}) {
      final old = before[id];
      final a = own[id];
      final b = theirs[id];
      if (sameSyncFact(a, b) || sameSyncFact(a, old)) {
        if (b != null) result.add(b);
      } else if (sameSyncFact(b, old)) {
        if (a != null) result.add(a);
      } else {
        if (b != null) result.add(b);
        conflicts.add(MemorySyncConflict(id: id, local: a, server: b));
      }
    }
    return (result, conflicts);
  }

  bool _sameFacts(List<MemoryFact> a, List<MemoryFact> b) {
    if (a.length != b.length) return false;
    final byId = {for (final f in b) f.id: f};
    return a.every((f) => sameSyncFact(f, byId[f.id]));
  }

  void _checkSnapshot(MemorySyncSnapshot snapshot) {
    // The injected transport is a trust boundary even when it did not use fromJson.
    MemorySyncSnapshot.fromJson(snapshot.toJson());
  }

  void _notifyMemory() {
    if (memory._disposed) return;
    _applying = true;
    try {
      memory.notifyListeners();
    } finally {
      _applying = false;
    }
  }

  void _onMemoryChanged() {
    if (_applying || _disposed || _state == null) return;
    _setStatus(MemorySyncStatus.pending);
    _again = true;
    if (_flight == null) {
      _again = false;
      _localTimer?.cancel();
      _localTimer = Timer(const Duration(milliseconds: 200), sync);
    }
  }

  void _refreshStatus() {
    final state = _state;
    _setStatus(
      state == null
          ? MemorySyncStatus.local
          : !_allowed
          ? MemorySyncStatus.unavailable
          : state.quarantine != null
          ? MemorySyncStatus.quarantine
          : state.conflicts.isNotEmpty
          ? MemorySyncStatus.conflict
          : state.clearGeneration != null || state.generation > state.ackGeneration
          ? MemorySyncStatus.pending
          : MemorySyncStatus.synced,
    );
  }

  void _setStatus(MemorySyncStatus value) {
    if (_disposed) return;
    _status = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _localTimer?.cancel();
    _bindingGeneration++;
    memory.removeListener(_onMemoryChanged);
    super.dispose();
  }
}

class _MemorySyncState {
  _MemorySyncState({required this.accountKey, required this.base, this.generation = 0, Set<String>? excluded})
    : excluded = excluded ?? {};
  final String accountKey;
  MemorySyncSnapshot base;
  int generation;
  int ackGeneration = 0;
  int? clearGeneration;
  final Set<String> excluded;
  List<MemorySyncConflict> conflicts = [];
  MemorySyncSnapshot? quarantine;
  MemorySyncSnapshot? inFlight;
  int? sentGeneration;

  factory _MemorySyncState.fromJson(Map<String, dynamic> json) {
    final state = _MemorySyncState(
      accountKey: json['accountKey'] as String,
      base: MemorySyncSnapshot.fromJson(json['base'] as Map<String, dynamic>),
      generation: json['generation'] as int,
      excluded: (json['excluded'] as List).cast<String>().toSet(),
    );
    state.ackGeneration = json['ackGeneration'] as int? ?? 0;
    state.clearGeneration = json['clearGeneration'] as int?;
    state.quarantine = json['quarantine'] == null
        ? null
        : MemorySyncSnapshot.fromJson(json['quarantine'] as Map<String, dynamic>);
    state.inFlight = json['inFlight'] == null
        ? null
        : MemorySyncSnapshot.fromJson(json['inFlight'] as Map<String, dynamic>);
    state.sentGeneration = json['sentGeneration'] as int?;
    state.conflicts = [
      for (final c in json['conflicts'] as List)
        MemorySyncConflict(
          id: c['id'] as String,
          local: c['local'] == null ? null : _readLocalFact(c['local'] as Map<String, dynamic>),
          server: c['server'] == null ? null : _readLocalFact(c['server'] as Map<String, dynamic>),
        ),
    ];
    return state;
  }

  static MemoryFact _readLocalFact(Map<String, dynamic> json) => MemoryFact(
    id: json['id'] as String,
    value: json['value'] as String,
    category: MemoryCategory.fromId(json['category'] as String),
    source: MemorySource.fromId(json['source'] as String),
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'accountKey': accountKey,
    'base': base.toJson(),
    'generation': generation,
    'ackGeneration': ackGeneration,
    'clearGeneration': clearGeneration,
    'excluded': excluded.toList(),
    'quarantine': quarantine?.toJson(),
    'inFlight': inFlight?.toJson(),
    'sentGeneration': sentGeneration,
    'conflicts': [
      for (final c in conflicts)
        {
          'id': c.id,
          'local': c.local == null ? null : memorySyncFactJson(c.local!),
          'server': c.server == null ? null : memorySyncFactJson(c.server!),
        },
    ],
  };
}
