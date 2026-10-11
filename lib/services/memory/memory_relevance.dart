import '../../database/app_database.dart';
import 'memory_models.dart';
import 'memory_validation.dart';

/// The facts in [rows] that share a word with [question], best match first,
/// within [kMemoryRelevantMaxFacts] and [kMemoryRelevantMaxChars]. Chosen on
/// this device, with no model call.
List<MemoryFact> pickRelevantFacts(List<AssistantMemoryRow> rows, String question) {
  final asked = memoryMatchWords(question);
  if (asked.isEmpty) return const [];

  final scored = <({MemoryFact fact, int score})>[];
  for (final row in rows) {
    final score = memoryMatchWords(row.value).intersection(asked).length;
    if (score > 0) scored.add((fact: MemoryFact.fromRow(row), score: score));
  }
  // List.sort is not stable, so the tie on score is spelled out: newest first,
  // and on an equal change time the order of `MemoryStore.all`.
  scored.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final byChange = b.fact.updatedAt.compareTo(a.fact.updatedAt);
    if (byChange != 0) return byChange;
    final byMade = b.fact.createdAt.compareTo(a.fact.createdAt);
    return byMade != 0 ? byMade : a.fact.id.compareTo(b.fact.id);
  });

  final chosen = <MemoryFact>[];
  var used = 0;
  for (final entry in scored) {
    if (chosen.length == kMemoryRelevantMaxFacts) break;
    // Code points, see kMemoryRelevantMaxChars.
    final cost = entry.fact.ref.length + 1 + entry.fact.value.runes.length + 1;
    if (used + cost > kMemoryRelevantMaxChars) continue;
    chosen.add(entry.fact);
    used += cost;
  }
  return chosen;
}
