import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../database/app_database.dart';
import '../../utils/app_logger.dart';
import 'memory_enabled_store.dart';
import 'memory_models.dart';
import 'memory_relevance.dart';
import 'memory_store.dart';
import 'memory_validation.dart';

export 'memory_models.dart';

/// What one profile asked the assistant to remember, and the written overview
/// derived from it. Made once per profile session with the profile in the
/// constructor: no method takes a profile id, and a fact of another profile
/// does not exist for this instance. Chat and settings share the instance,
/// and an overview is saved on the instance that gave the facts for it:
/// [saveOverview] refuses the hash of another instance or an earlier run.
///
/// Nothing here logs a fact, a key, a question, an overview or an id, and no
/// database error leaves this class: its message quotes the statement
/// parameters. A failed call gives [MemoryCode.storageFailed], or the empty
/// answer for a read that has no code to give.
///
/// A service whose profile was deleted writes nothing any more
/// ([MemoryCode.profileGone]). After [clearAll] it keeps working, but an
/// overview written from the wiped facts is refused.
class MemoryService {
  MemoryService({
    required AppDatabase database,
    required String profileId,
    MemoryEnabledStore? enabledStore,
    String Function()? newId,
    DateTime Function()? now,
  }) : _profileId = profileId,
       _removals = AssistantMemoryEpochs.removals(profileId),
       _store = MemoryStore(database, profileId),
       _enabledStore = enabledStore ?? MemoryEnabledStore(profileId),
       _newId = newId ?? const Uuid().v4,
       _now = now ?? DateTime.now;

  final String _profileId;
  final int _removals;
  final MemoryStore _store;
  final MemoryEnabledStore _enabledStore;
  final String Function() _newId;
  final DateTime Function() _now;

  /// The hashes [overviewInput] handed out since the facts were last wiped,
  /// and the wipe count they belong to. Bounded; a hash that fell out is
  /// refused, which only costs a rewrite.
  final Set<String> _issuedHashes = {};
  int _issuedAtWipe = 0;
  static const int _issuedHashLimit = 32;

  static final RegExp _refShape = RegExp(r'^[0-9a-f-]{8,36}$');
  static const MemoryResult _failed = MemoryResult(MemoryCode.storageFailed);

  bool get _hasProfile => _profileId.isNotEmpty;
  bool get _profileGone =>
      AssistantMemoryEpochs.removing(_profileId) || AssistantMemoryEpochs.removals(_profileId) != _removals;

  /// Whether this profile's memory is on. Off means no tools, no context and
  /// no proposals; the stored facts and overview stay.
  Future<bool> get enabled => _enabledStore.read();

  Future<void> setEnabled(bool value) => _enabledStore.save(value);

  /// This profile's facts, newest change first. [query] keeps the facts that
  /// hold every word of it. Empty when the lookup fails.
  Future<List<MemoryFact>> list({MemoryCategory? category, String? query}) async {
    if (!_hasProfile) return const [];
    final words = query == null ? const <String>[] : memoryValueKey(query).split(' ').where((w) => w.isNotEmpty);
    return _guarded(const [], () async {
      return [
        for (final row in await _store.all())
          if ((category == null || row.category == category.id) && words.every(row.valueKey.contains))
            MemoryFact.fromRow(row),
      ];
    });
  }

  /// Stores a new fact. The same sentence twice is one row: the second call
  /// returns the existing fact with [MemoryCode.exists]. "The same" ignores
  /// case, punctuation and accents ([memoryValueKey]), so `Kijkt één film`
  /// after `Kijkt een film` gives [MemoryCode.exists] too.
  Future<MemoryResult> add({
    required String value,
    required MemoryCategory category,
    required MemorySource source,
  }) async {
    if (!_hasProfile) return const MemoryResult(MemoryCode.noProfile);
    final checked = checkMemoryValue(value);
    final accepted = checked.value;
    if (accepted == null) return MemoryResult(checked.code);

    return _guarded(_failed, () {
      return _store.transaction(() async {
        final existing = await _store.byValueKey(accepted.key);
        if (existing != null) return MemoryResult(MemoryCode.exists, MemoryFact.fromRow(existing));
        if (await _store.count() >= kMemoryFactLimit) return const MemoryResult(MemoryCode.limitReached);
        if (_profileGone) return const MemoryResult(MemoryCode.profileGone);

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

    return _guarded(_failed, () {
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
        if (_profileGone) return const MemoryResult(MemoryCode.profileGone);

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
    });
  }

  /// Hard delete. The removed fact comes back so the caller can name it.
  Future<MemoryResult> delete(String id) async {
    if (!_hasProfile) return const MemoryResult(MemoryCode.noProfile);
    return _guarded(_failed, () {
      return _store.transaction(() async {
        final current = await _store.byId(id);
        if (current == null) return const MemoryResult(MemoryCode.notFound);
        await _store.deleteById(id);
        return MemoryResult(MemoryCode.ok, MemoryFact.fromRow(current));
      });
    });
  }

  /// Drops every fact of this profile and its written overview. An overview
  /// that was being written from those facts is refused when it arrives.
  Future<MemoryResult> clearAll() async {
    if (!_hasProfile) return const MemoryResult(MemoryCode.noProfile);
    AssistantMemoryEpochs.noteWipe(_profileId);
    return _guarded(_failed, () async {
      await _store.transaction(_store.deleteAll);
      return const MemoryResult(MemoryCode.ok);
    });
  }

  /// Resolves a short reference ([MemoryFact.ref]) or a full id to one fact of
  /// this profile. Unknown gives [MemoryCode.notFound], more than one match
  /// [MemoryCode.ambiguous]; neither changes anything.
  Future<MemoryResult> resolve(String ref) async {
    if (!_hasProfile) return const MemoryResult(MemoryCode.noProfile);
    final wanted = ref.trim().toLowerCase();
    if (!_refShape.hasMatch(wanted)) return const MemoryResult(MemoryCode.notFound);
    return _guarded(_failed, () async {
      final matches = await _store.byIdPrefix(wanted);
      if (matches.isEmpty) return const MemoryResult(MemoryCode.notFound);
      if (matches.length > 1) return const MemoryResult(MemoryCode.ambiguous);
      return MemoryResult(MemoryCode.ok, MemoryFact.fromRow(matches.single));
    });
  }

  /// The facts that share a word with [question], see [pickRelevantFacts].
  /// Empty when the memory is off, and empty rather than an error when the
  /// lookup fails: a question must not break on its memory.
  Future<List<MemoryFact>> relevantFor(String question) async {
    if (!_hasProfile) return const [];
    return _guarded(const [], () async {
      if (!await enabled) return const [];
      return pickRelevantFacts(await _store.all(), question);
    });
  }

  /// The stored overview of this profile, or null when none was written or the
  /// lookup fails.
  Future<MemoryOverview?> overview() async {
    if (!_hasProfile) return null;
    return _guarded(null, () async {
      final row = await _store.overview();
      return row == null ? null : MemoryOverview.fromRow(row);
    });
  }

  /// What an overview in [locale] is written from, read in one go: every
  /// fact of this profile and the hash that covers exactly those facts. The
  /// only way to a hash [saveOverview] takes, so an overview cannot be stored
  /// under a hash of other facts than the ones it was written from. Null when
  /// there is no profile, when the lookup fails or when the facts were wiped
  /// during it: then there is nothing to write from. Take it and save on the
  /// same instance.
  Future<MemoryOverviewInput?> overviewInput({required String locale}) async {
    if (!_hasProfile) return null;
    final wipe = AssistantMemoryEpochs.wipes(_profileId);
    return _guarded(null, () async {
      final rows = await _store.all();
      if (AssistantMemoryEpochs.wipes(_profileId) != wipe) return null;
      final hash = _hashOf(rows, locale);
      _issue(hash, wipe);
      return MemoryOverviewInput(
        facts: List.unmodifiable([for (final row in rows) MemoryFact.fromRow(row)]),
        factsHash: hash,
        locale: locale,
      );
    });
  }

  /// Whether the stored overview no longer matches the facts, [locale] or the
  /// format version. True when there is none. A failed attempt with the same
  /// hash is not stale, so it is not retried until something changes. False
  /// when the lookup fails: a broken database is no reason to write. Asking
  /// this does not let [saveOverview] through; only [overviewInput] does.
  Future<bool> overviewIsStale({required String locale}) async {
    if (!_hasProfile) return false;
    return _guarded(false, () async {
      final row = await _store.overview();
      return row == null || row.factsHash != _hashOf(await _store.all(), locale);
    });
  }

  /// Keeps one overview for this profile, replacing the previous one. A failed
  /// attempt is stored with an empty body. Stores nothing and says why when
  /// [body] is not a JSON object within [kMemoryOverviewMaxBytes]
  /// ([MemoryCode.invalidOverview]), or when [factsHash] is not the hash of an
  /// [overviewInput] of this instance for the same [locale] whose facts are
  /// still the facts of this profile ([MemoryCode.staleHash]): a fact was
  /// added, changed, removed or wiped since.
  Future<MemoryResult> saveOverview({
    required String factsHash,
    required String locale,
    required MemoryOverviewStatus status,
    String body = '',
  }) async {
    if (!_hasProfile) return const MemoryResult(MemoryCode.noProfile);
    final kept = status == MemoryOverviewStatus.ok ? body : '';
    if (status == MemoryOverviewStatus.ok && !isMemoryOverviewBody(kept)) {
      return const MemoryResult(MemoryCode.invalidOverview);
    }
    return _guarded(_failed, () {
      return _store.transaction(() async {
        final current = _hashOf(await _store.all(), locale);
        if (_profileGone) return const MemoryResult(MemoryCode.profileGone);
        final issued = _issuedAtWipe == AssistantMemoryEpochs.wipes(_profileId) && _issuedHashes.contains(factsHash);
        if (!issued || factsHash != current) return const MemoryResult(MemoryCode.staleHash);
        await _store.putOverview(
          factsHash: factsHash,
          locale: locale,
          status: status.id,
          body: kept,
          at: _now().toUtc().millisecondsSinceEpoch,
        );
        return const MemoryResult(MemoryCode.ok);
      });
    });
  }

  /// Covers the id, updatedAt and text of every fact, the locale and
  /// [kMemoryOverviewFormatVersion].
  static String _hashOf(List<AssistantMemoryRow> rows, String locale) {
    final facts = [
      for (final row in rows) [row.id, row.updatedAt, row.value],
    ]..sort((a, b) => (a.first as String).compareTo(b.first as String));
    final payload = jsonEncode({'v': kMemoryOverviewFormatVersion, 'locale': locale, 'facts': facts});
    return sha256.convert(utf8.encode(payload)).toString();
  }

  void _issue(String hash, int wipe) {
    if (_issuedAtWipe != wipe) {
      _issuedHashes.clear();
      _issuedAtWipe = wipe;
    }
    _issuedHashes
      ..remove(hash)
      ..add(hash);
    if (_issuedHashes.length > _issuedHashLimit) _issuedHashes.remove(_issuedHashes.first);
  }

  Future<MemoryResult> _stored(String id) async {
    final row = await _store.byId(id);
    return row == null ? const MemoryResult(MemoryCode.notFound) : MemoryResult(MemoryCode.ok, MemoryFact.fromRow(row));
  }

  /// Runs [action] and turns whatever it throws into [onFailure]. Only the
  /// type of the error is logged; its message can quote a fact.
  Future<T> _guarded<T>(T onFailure, Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      appLogger.w('Memory storage failed: ${e.runtimeType}');
      return onFailure;
    }
  }
}
