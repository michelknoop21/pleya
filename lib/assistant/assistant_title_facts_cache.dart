import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../services/tmdb/tmdb_client.dart';
import '../utils/app_logger.dart';
import 'assistant_title_facts.dart';

/// External title facts by TMDB id: an in-memory LRU (500 titles, 6 h) in
/// front of the shared `ApiCache` table (24 h). Library state never goes in
/// here, only what Seerr and the online sources said about a title. An
/// incomplete lookup (TMDB failed or out of budget) stays 10 minutes, in
/// memory only. Callers put the TMDB key state in [lang], so saving or
/// clearing the key, or the online switch, starts a fresh cache.
class TitleFactsCache {
  TitleFactsCache({this.db, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final AppDatabase? db;
  final DateTime Function() _now;

  static const maxEntries = 500;
  static const memoryTtl = Duration(hours: 6);
  static const dbTtl = Duration(hours: 24);
  static const incompleteTtl = Duration(minutes: 10);

  // Insertion order is recency: a hit is moved to the end.
  final _memory = <String, ({DateTime at, Duration ttl, TitleFacts facts})>{};

  // v2: v1 rows did not record whether TMDB was part of the lookup.
  static String key(TmdbKind kind, int tmdbId, String lang) => 'titlefacts:v2:${kind.path}:$tmdbId:$lang';

  Future<TitleFacts?> get(TmdbKind kind, int tmdbId, String lang) async {
    final k = key(kind, tmdbId, lang);
    final hit = _memory.remove(k);
    if (hit != null && _now().difference(hit.at) < hit.ttl) {
      _memory[k] = hit;
      return hit.facts;
    }
    final db = this.db;
    if (db == null) return null;
    try {
      final row = await (db.select(db.apiCache)..where((t) => t.cacheKey.equals(k))).getSingleOrNull();
      if (row == null || _now().difference(row.cachedAt) >= dbTtl) return null;
      final facts = TitleFacts.fromJson(jsonDecode(row.data) as Map<String, dynamic>);
      _remember(k, facts, row.cachedAt, memoryTtl);
      return facts;
    } catch (e) {
      appLogger.d('Title facts: cache read failed', error: e.runtimeType);
      return null;
    }
  }

  Future<void> put(TmdbKind kind, int tmdbId, String lang, TitleFacts facts, {bool complete = true}) async {
    final k = key(kind, tmdbId, lang);
    final at = _now();
    _remember(k, facts, at, complete ? memoryTtl : incompleteTtl);
    final db = this.db;
    if (db == null || !complete) return;
    try {
      await db
          .into(db.apiCache)
          .insertOnConflictUpdate(
            ApiCacheCompanion(cacheKey: Value(k), data: Value(jsonEncode(facts.toJson())), cachedAt: Value(at)),
          );
    } catch (e) {
      appLogger.d('Title facts: cache write failed', error: e.runtimeType);
    }
  }

  void _remember(String k, TitleFacts facts, DateTime at, Duration ttl) {
    _memory.remove(k);
    _memory[k] = (at: at, ttl: ttl, facts: facts);
    while (_memory.length > maxEntries) {
      _memory.remove(_memory.keys.first);
    }
  }
}
