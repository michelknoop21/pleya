import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/remembered_source_choice.dart';
import 'package:pleya/services/unified_catalog/source_preference_store.dart';

void main() {
  group('preference key (hoofdstuk 14.8)', () {
    test('a movie keys on its canonical bucket, so the entry survives the session', () {
      final key = SourcePreferenceStore.preferenceKeyFor(CanonicalMediaIdentity.movie(title: 'Dune', year: 2021));

      expect(key, isNotNull);
      // Content-derived, not the session-scoped groupId of hoofdstuk 11.9.
      expect(key, SourcePreferenceStore.preferenceKeyFor(CanonicalMediaIdentity.movie(title: 'dune', year: 2021)));
    });

    test('a remake with another year is a different entry', () {
      expect(
        SourcePreferenceStore.preferenceKeyFor(CanonicalMediaIdentity.movie(title: 'Dune', year: 1984)),
        isNot(SourcePreferenceStore.preferenceKeyFor(CanonicalMediaIdentity.movie(title: 'Dune', year: 2021))),
      );
    });

    test('a movie and a show with one title never share an entry', () {
      expect(
        SourcePreferenceStore.preferenceKeyFor(CanonicalMediaIdentity.movie(title: 'Fargo', year: 1996)),
        isNot(SourcePreferenceStore.preferenceKeyFor(CanonicalMediaIdentity.show(title: 'Fargo', year: 1996))),
      );
    });

    test('an identity with no canonical key remembers nothing rather than colliding', () {
      expect(SourcePreferenceStore.preferenceKeyFor(CanonicalMediaIdentity.opaque()), isNull);
      expect(SourcePreferenceStore.preferenceKeyFor(CanonicalMediaIdentity.movie(title: '', year: 2021)), isNull);
      // An episode missing its indices has no stable cross-session identity.
      expect(SourcePreferenceStore.preferenceKeyFor(CanonicalMediaIdentity.episode(showTitle: 'Severance')), isNull);
    });
  });

  group('profile scoping', () {
    test('a key belongs only to the scope before its first separator', () {
      expect(SourcePreferenceStore.keyBelongsToScope('uuid-a|movie:dune:2021', 'uuid-a'), isTrue);
      expect(SourcePreferenceStore.keyBelongsToScope('uuid-b|movie:dune:2021', 'uuid-a'), isFalse);
    });

    test('a scope is never matched by a prefix of another scope', () {
      expect(SourcePreferenceStore.keyBelongsToScope('uuid-ab|movie:dune:2021', 'uuid-a'), isFalse);
    });

    test('the signed-out namespace is its own scope, not everyone else', () {
      expect(SourcePreferenceStore.keyBelongsToScope('|movie:dune:2021', ''), isTrue);
      expect(SourcePreferenceStore.keyBelongsToScope('uuid-a|movie:dune:2021', ''), isFalse);
    });

    test('a title containing a pipe still resolves to the right scope', () {
      expect(SourcePreferenceStore.keyBelongsToScope('uuid-a|movie:a|b:2021', 'uuid-a'), isTrue);
    });

    test('a malformed key with no separator belongs to no scope', () {
      expect(SourcePreferenceStore.keyBelongsToScope('nonsense', 'uuid-a'), isFalse);
    });
  });

  group('LRU cap', () {
    Map<String, RememberedSourceChoice> entries(int count, {int Function(int)? age}) => {
      for (var i = 0; i < count; i++)
        'scope|key-$i': RememberedSourceChoice(sourceKey: 'nas:$i', updatedAt: age?.call(i) ?? i),
    };

    test('a map inside the cap is returned untouched', () {
      final input = entries(10);

      expect(SourcePreferenceStore.capped(input), same(input));
    });

    test('an over-full map keeps exactly the most recent entries', () {
      final capped = SourcePreferenceStore.capped(entries(SourcePreferenceStore.maxEntries + 5));

      expect(capped, hasLength(SourcePreferenceStore.maxEntries));
      // Ages ascend with the index, so the five oldest are the ones dropped.
      expect(capped.containsKey('scope|key-0'), isFalse);
      expect(capped.containsKey('scope|key-4'), isFalse);
      expect(capped.containsKey('scope|key-5'), isTrue);
      expect(capped.containsKey('scope|key-${SourcePreferenceStore.maxEntries + 4}'), isTrue);
    });

    test('recency, not insertion order, decides what survives', () {
      final capped = SourcePreferenceStore.capped(
        entries(SourcePreferenceStore.maxEntries + 1, age: (i) => i == 0 ? 1 << 40 : i),
      );

      expect(capped.containsKey('scope|key-0'), isTrue);
      expect(capped.containsKey('scope|key-1'), isFalse);
    });
  });

  group('RememberedSourceChoice', () {
    test('round-trips through JSON', () {
      const choice = RememberedSourceChoice(sourceKey: 'nas:i1', updatedAt: 1234);

      final decoded = RememberedSourceChoice.fromJson(choice.toJson());

      expect(decoded.sourceKey, 'nas:i1');
      expect(decoded.updatedAt, 1234);
      expect(decoded.isEmpty, isFalse);
    });

    test('malformed storage decodes to an empty choice rather than a bogus preference', () {
      final decoded = RememberedSourceChoice.fromJson(const {});

      expect(decoded.isEmpty, isTrue);
      expect(decoded.sourceKey, isEmpty);
    });
  });
}
