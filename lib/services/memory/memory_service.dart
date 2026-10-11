import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../database/app_database.dart';
import '../../utils/app_logger.dart';
import 'memory_enabled_store.dart';
import 'memory_models.dart';
import 'memory_store.dart';
import 'memory_validation.dart';

export 'memory_models.dart';

/// What one profile asked the assistant to remember, and the written overview
/// derived from it. Made once per profile session with the profile in the
/// constructor: no method takes a profile id, and a fact of another profile
/// does not exist for this instance. Chat and settings share the instance.
///
/// Nothing here logs a fact, a key, a question, an overview or an id.
class MemoryService {
  MemoryService({
    required AppDatabase database,
    required String profileId,
    MemoryEnabledStore? enabledStore,
    String Function()? newId,
    DateTime Function()? now,
  }) : _hasProfile = profileId.isNotEmpty,
       _store = MemoryStore(database, profileId),
       _enabledStore = enabledStore ?? MemoryEnabledStore(profileId),
       _newId = newId ?? const Uuid().v4,
       _now = now ?? DateTime.now;

  final bool _hasProfile;
  final MemoryStore _store;
  final MemoryEnabledStore _enabledStore;
  final String Function() _newId;
  final DateTime Function() _now;

  static final RegExp _refShape = RegExp(r'^[0-9a-f-]{8,36}$');

  /// Whether this profile's memory is on. Off means no tools, no context and
  /// no proposals; the stored facts and overview stay.
  Future<bool> get enabled => _enabledStore.read();

  Future<void> setEnabled(bool value) => _enabledStore.save(value);

  /// This profile's facts, newest change first. [query] keeps the facts that
  /// hold every word of it.
  Future<List<MemoryFact>> list({MemoryCategory? category, String? query}) async {
    if (!_hasProfile) return const [];
    final words = query == null ? const <String>[] : memoryValueKey(query).split(' ').where((w) => w.isNotEmpty);
    return [
      for (final row in await _store.all())
        if ((category == null || row.category == category.id) && words.every(row.valueKey.contains))
          MemoryFact.fromRow(row),
    ];
  }

  /// Stores a new fact. The same sentence twice is one row: the second call
  /// returns the existing fact with [MemoryCode.exists].
  Future<MemoryResult> add({
    required String value,
    required MemoryCategory category,
    required MemorySource source,
  }) async {
    if (!_hasProfile) return const MemoryResult(MemoryCode.noProfile);
    final checked = checkMemoryValue(value);
    final accepted = checked.value;
    if (accepted == null) return MemoryResult(checked.code);

    return _store.transaction(() async {
      final existing = await _store.byValueKey(accepted.key);
      if (existing != null) return MemoryResult(MemoryCode.exists, MemoryFact.fromRow(existing));
      if (await _store.count() >= kMemoryFactLimit) return const MemoryResult(MemoryCode.limitReached);

      final id = _newId();
      await _store.insert(
        id: id,
        category: category.id,
        value: accepted.value,
        valueKey: accepted.key,
        source: source.id,
        at: _now().toUtc().millisecondsSinceEpoch,
      );
      return _stored(id);
    });
  }

  /// Changes the text, the category or both of the fact with [id]. Defaults to
  /// a manual edit, which is what a change in settings is.
  Future<MemoryResult> update(
    String id, {
    String? value,
    MemoryCategory? category,
    MemorySource source = MemorySource.settingsManual,
  }) async {
    if (!_hasProfile) return const MemoryResult(MemoryCode.noProfile);
    MemoryValue? accepted;
    if (value != null) {
      final checked = checkMemoryValue(value);
      accepted = checked.value;
      if (accepted == null) return MemoryResult(checked.code);
    }

    return _store.transaction(() async {
      final current = await _store.byId(id);
      if (current == null) return const MemoryResult(MemoryCode.notFound);
      final nextValue = accepted?.value ?? current.value;
      final nextKey = accepted?.key ?? current.valueKey;
      final nextCategory = category?.id ?? current.category;
      if (nextValue == current.value && nextCategory == current.category) {
        return MemoryResult(MemoryCode.ok, MemoryFact.fromRow(current));
      }
      if (nextKey != current.valueKey && await _store.byValueKey(nextKey) != null) {
        return const MemoryResult(MemoryCode.duplicate);
      }

      // Strictly later than the previous change: the overview hash reads
      // updatedAt, and a category change alters nothing else it covers.
      final now = _now().toUtc().millisecondsSinceEpoch;
      await _store.update(
        id,
        category: nextCategory,
        value: nextValue,
        valueKey: nextKey,
        source: source.id,
        at: now > current.updatedAt ? now : current.updatedAt + 1,
      );
      return _stored(id);
    });
  }

  /// Hard delete. The removed fact comes back so the caller can name it.
  Future<MemoryResult> delete(String id) async {
    if (!_hasProfile) return const MemoryResult(MemoryCode.noProfile);
    return _store.transaction(() async {
      final current = await _store.byId(id);
      if (current == null) return const MemoryResult(MemoryCode.notFound);
      await _store.deleteById(id);
      return MemoryResult(MemoryCode.ok, MemoryFact.fromRow(current));
    });
  }

  /// Drops every fact of this profile and its written overview.
  Future<void> clearAll() async {
    if (!_hasProfile) return;
    await _store.transaction(_store.deleteAll);
  }

  /// Resolves a short reference ([MemoryFact.ref]) or a full id to one fact of
  /// this profile. Unknown gives [MemoryCode.notFound], more than one match
  /// [MemoryCode.ambiguous]; neither changes anything.
  Future<MemoryResult> resolve(String ref) async {
    if (!_hasProfile) return const MemoryResult(MemoryCode.noProfile);
    final wanted = ref.trim().toLowerCase();
    if (!_refShape.hasMatch(wanted)) return const MemoryResult(MemoryCode.notFound);
    final matches = await _store.byIdPrefix(wanted);
    if (matches.isEmpty) return const MemoryResult(MemoryCode.notFound);
    if (matches.length > 1) return const MemoryResult(MemoryCode.ambiguous);
    return MemoryResult(MemoryCode.ok, MemoryFact.fromRow(matches.single));
  }

  /// The facts that share a word with [question], best match first, within
  /// [kMemoryRelevantMaxFacts] and [kMemoryRelevantMaxChars]. A fact costs its
  /// reference, a space, its text and a line break. Chosen on this device, with
  /// no model call. Empty when the memory is off, and empty rather than an
  /// error when the lookup fails: a question must not break on its memory.
  Future<List<MemoryFact>> relevantFor(String question) async {
    if (!_hasProfile) return const [];
    try {
      if (!await enabled) return const [];
      final asked = memoryMatchWords(question);
      if (asked.isEmpty) return const [];

      final scored = <({MemoryFact fact, int score})>[];
      for (final row in await _store.all()) {
        final score = memoryMatchWords(row.value).intersection(asked).length;
        if (score > 0) scored.add((fact: MemoryFact.fromRow(row), score: score));
      }
      // List.sort is not stable, so the tie on score is spelled out: newest first.
      scored.sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        return byScore != 0 ? byScore : b.fact.updatedAt.compareTo(a.fact.updatedAt);
      });

      final chosen = <MemoryFact>[];
      var used = 0;
      for (final entry in scored) {
        if (chosen.length == kMemoryRelevantMaxFacts) break;
        final cost = entry.fact.ref.length + 1 + entry.fact.value.runes.length + 1;
        if (used + cost > kMemoryRelevantMaxChars) continue;
        chosen.add(entry.fact);
        used += cost;
      }
      return chosen;
    } catch (e) {
      appLogger.w('Memory lookup failed: ${e.runtimeType}');
      return const [];
    }
  }

  /// The stored overview of this profile, or null when none was written.
  Future<MemoryOverview?> overview() async {
    if (!_hasProfile) return null;
    final row = await _store.overview();
    return row == null ? null : MemoryOverview.fromRow(row);
  }

  /// Hash of what an overview in [locale] is written from: the id, updatedAt
  /// and text of every fact of this profile, the locale and
  /// [kMemoryOverviewFormatVersion]. Take it when the facts are read for a
  /// write and hand the same value to [saveOverview], so a fact that changes
  /// while the overview is being written leaves it stale.
  Future<String> factsHash({required String locale}) async {
    final rows = _hasProfile ? await _store.all() : const <AssistantMemoryRow>[];
    final facts = [
      for (final row in rows) [row.id, row.updatedAt, row.value],
    ]..sort((a, b) => (a.first as String).compareTo(b.first as String));
    final payload = jsonEncode({'v': kMemoryOverviewFormatVersion, 'locale': locale, 'facts': facts});
    return sha256.convert(utf8.encode(payload)).toString();
  }

  /// Whether the stored overview no longer matches the facts, [locale] or the
  /// format version. True when there is none. A failed attempt with the same
  /// hash is not stale, so it is not retried until something changes.
  Future<bool> overviewIsStale({required String locale}) async {
    if (!_hasProfile) return false;
    final row = await _store.overview();
    return row == null || row.factsHash != await factsHash(locale: locale);
  }

  /// Keeps one overview for this profile, replacing the previous one. A failed
  /// attempt is stored with an empty body.
  Future<void> saveOverview({
    required String factsHash,
    required String locale,
    required MemoryOverviewStatus status,
    String body = '',
  }) async {
    if (!_hasProfile) return;
    await _store.putOverview(
      factsHash: factsHash,
      locale: locale,
      status: status.id,
      body: status == MemoryOverviewStatus.ok ? body : '',
      at: _now().toUtc().millisecondsSinceEpoch,
    );
  }

  Future<MemoryResult> _stored(String id) async {
    final row = await _store.byId(id);
    return row == null ? const MemoryResult(MemoryCode.notFound) : MemoryResult(MemoryCode.ok, MemoryFact.fromRow(row));
  }
}
