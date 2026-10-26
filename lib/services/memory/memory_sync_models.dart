import 'memory_models.dart';
import 'memory_validation.dart';

/// Safe fixed code only: never put transport bodies or fact text in this exception.
class MemorySyncFailure implements Exception {
  const MemorySyncFailure(this.code);
  final String code;
  @override
  String toString() => 'MemorySyncFailure';
}

enum MemorySyncStatus { local, syncing, pending, synced, unavailable, error, conflict, quarantine }

enum MemorySyncChoice { local, server, both }

class MemorySyncSnapshot {
  MemorySyncSnapshot({required this.epoch, required this.revision, required List<MemoryFact> facts})
    : facts = List.unmodifiable(facts);
  final String epoch;
  final int revision;
  final List<MemoryFact> facts;

  factory MemorySyncSnapshot.fromJson(Map<String, dynamic> json) {
    try {
      final epoch = json['epoch'] as String;
      final revision = json['revision'] as int;
      if (!_uuid.hasMatch(epoch) || revision < 0 || revision > 9007199254740991) {
        throw const MemorySyncFailure('invalid_snapshot');
      }
      final rawFacts = json['facts'] as List;
      if (rawFacts.length > kMemoryFactLimit) throw const MemorySyncFailure('invalid_snapshot');
      final facts = [for (final raw in rawFacts) _readFact(raw as Map<String, dynamic>)];
      validateSyncFacts(facts);
      return MemorySyncSnapshot(epoch: epoch, revision: revision, facts: facts);
    } catch (_) {
      throw const MemorySyncFailure('invalid_snapshot');
    }
  }

  Map<String, dynamic> toJson() => {
    'epoch': epoch,
    'revision': revision,
    'facts': [for (final fact in facts) memorySyncFactJson(fact)],
  };
}

final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

MemoryFact _readFact(Map<String, dynamic> json) {
  final category = json['category'] as String;
  final source = json['source'] as String;
  if (!MemoryCategory.values.any((c) => c.id == category && c != MemoryCategory.household) ||
      !MemorySource.values.any((s) => s.id == source)) {
    throw const MemorySyncFailure('invalid_snapshot');
  }
  final created = DateTime.parse(json['created_at'] as String);
  final updated = DateTime.parse(json['updated_at'] as String);
  if (!created.isUtc || !updated.isUtc || updated.isBefore(created)) {
    throw const MemorySyncFailure('invalid_snapshot');
  }
  return MemoryFact(
    id: json['id'] as String,
    value: json['value'] as String,
    category: MemoryCategory.fromId(category),
    source: MemorySource.fromId(source),
    createdAt: created,
    updatedAt: updated,
  );
}

Map<String, dynamic> memorySyncFactJson(MemoryFact fact, {bool dates = true}) => {
  'id': fact.id,
  'category': fact.category.id,
  'value': fact.value,
  'source': fact.source.id,
  if (dates) 'created_at': fact.createdAt.toUtc().toIso8601String(),
  if (dates) 'updated_at': fact.updatedAt.toUtc().toIso8601String(),
};

void validateSyncFacts(List<MemoryFact> facts) {
  if (facts.length > kMemoryFactLimit) throw const MemorySyncFailure('memory.limit_reached');
  final ids = <String>{};
  final keys = <String>{};
  for (final fact in facts) {
    final checked = checkMemoryValue(fact.value);
    if (!_uuid.hasMatch(fact.id) ||
        fact.category == MemoryCategory.household ||
        checked.value == null ||
        checked.value!.value != fact.value) {
      throw const MemorySyncFailure('invalid_snapshot');
    }
    if (!ids.add(fact.id) || !keys.add(checked.value!.key)) throw const MemorySyncFailure('memory.duplicate');
  }
}

bool sameSyncFact(MemoryFact? a, MemoryFact? b) =>
    identical(a, b) ||
    a != null && b != null && a.id == b.id && a.value == b.value && a.category == b.category && a.source == b.source;

abstract class MemorySyncTransport {
  Future<MemorySyncSnapshot> fetch();
  Future<MemorySyncSnapshot> replace({
    required String epoch,
    required int baseRevision,
    required List<MemoryFact> facts,
  });
  Future<MemorySyncSnapshot> clear({required String epoch, required int baseRevision});
}

class MemorySyncPreview {
  const MemorySyncPreview({
    required this.accountKey,
    required this.remote,
    required this.localFacts,
    this.deviceFacts = const [],
  });
  final String accountKey;
  final MemorySyncSnapshot remote;
  final List<MemoryFact> localFacts;
  final List<MemoryFact> deviceFacts;

  int combinedCount(Set<String> selected) {
    final desired = {for (final fact in remote.facts) fact.id: fact};
    for (final fact in localFacts.where((fact) => selected.contains(fact.id))) {
      if (!desired.containsKey(fact.id) &&
          !desired.values.any((other) => memoryValueKey(other.value) == memoryValueKey(fact.value))) {
        desired[fact.id] = fact;
      }
    }
    final all = deviceFacts.isEmpty ? localFacts : deviceFacts;
    return desired.length + all.where((fact) => !selected.contains(fact.id)).length;
  }
}

class MemorySyncConflict {
  const MemorySyncConflict({required this.id, this.local, this.server});
  final String id;
  final MemoryFact? local;
  final MemoryFact? server;
}
