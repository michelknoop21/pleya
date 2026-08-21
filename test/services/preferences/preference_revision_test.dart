import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/preferences/preference_revision.dart';

/// The conflict rule for ordinary scalar preferences.
///
/// Without this, `replace` means "whatever the transport handed us last", which
/// is arrival order dressed up as a decision: change a setting on a laptop that
/// is offline and the older cloud value still wins when it reconnects.
void main() {
  PreferenceRevision rev(Object? value, int at, String device, {bool deleted = false}) =>
      PreferenceRevision(value: value, updatedAt: at, deviceId: device, deleted: deleted);

  group('last-writer-wins', () {
    test('the newer change wins regardless of which side it is on', () {
      final older = rev(10, 1000, 'appletv');
      final newer = rev(20, 2000, 'macbook');

      expect(PreferenceRevision.resolve(older, newer), newer);
      expect(PreferenceRevision.resolve(newer, older), newer);
    });

    test('an offline edit made later still beats an older cloud value', () {
      // The scenario the whole envelope exists for: 09:00 in the cloud, 10:05
      // made offline on another device, reconcile at 10:30.
      final cloudAt0900 = rev('dark', 1000 * 60 * 60 * 9, 'appletv');
      final offlineAt1005 = rev('light', 1000 * 60 * 60 * 10 + 1000 * 60 * 5, 'macbook');

      expect(PreferenceRevision.resolve(cloudAt0900, offlineAt1005).value, 'light');
    });

    test('an exact tie is broken by device id, so both sides reach the same answer', () {
      final a = rev(1, 5000, 'aaa');
      final b = rev(2, 5000, 'bbb');

      expect(PreferenceRevision.resolve(a, b), b);
      expect(PreferenceRevision.resolve(b, a), b, reason: 'order of comparison must not change the winner');
    });

    test('resolving is stable when repeated', () {
      final a = rev(1, 5000, 'aaa');
      final b = rev(2, 6000, 'bbb');
      final once = PreferenceRevision.resolve(a, b);

      expect(PreferenceRevision.resolve(once, b), once);
      expect(PreferenceRevision.resolve(b, once), once);
    });
  });

  group('tombstones', () {
    test('a newer delete removes a value an older snapshot still holds', () {
      final value = rev('x', 1000, 'appletv');
      final deletion = rev(null, 2000, 'macbook', deleted: true);

      expect(PreferenceRevision.resolve(value, deletion).deleted, isTrue);
    });

    test('a value written after a delete comes back', () {
      final deletion = rev(null, 1000, 'macbook', deleted: true);
      final rewritten = rev('x', 2000, 'macbook');

      expect(PreferenceRevision.resolve(deletion, rewritten).value, 'x');
    });

    test('a delete survives a round trip through the wire format', () {
      final deletion = rev(null, 4242, 'macbook', deleted: true);
      final parsed = PreferenceRevision.decode(deletion.encode());

      expect(parsed, deletion);
      expect(parsed!.deleted, isTrue);
      expect(parsed.value, isNull);
    });
  });

  group('encoding', () {
    test('every SharedPreferences type survives a round trip', () {
      for (final value in <Object>[true, 42, 3.5, 'text']) {
        final parsed = PreferenceRevision.decode(rev(value, 1, 'd').encode());
        expect(parsed?.value, value);
      }
      final list = PreferenceRevision.decode(rev(['a', 'b'], 1, 'd').encode());
      expect(list?.value, ['a', 'b']);
    });

    test('a bare v1 value is not mistaken for an envelope', () {
      expect(PreferenceRevision.decode('44'), isNull);
      expect(PreferenceRevision.decode('{"type":"int","value":44}'), isNull);
      expect(PreferenceRevision.decode('not json'), isNull);
      expect(PreferenceRevision.decode(null), isNull);
    });
  });

  group('which sources count as a user change', () {
    test('a deliberate change stamps a fresh timestamp', () {
      for (final source in [PreferenceSource.local, PreferenceSource.import, PreferenceSource.reset]) {
        expect(
          PreferenceMutation.set('k', 1, source: source).stampsUserChange,
          isTrue,
          reason: '${source.name} is the user deciding something',
        );
      }
    });

    test('a migration does not, or the last device to upgrade owns every setting', () {
      expect(PreferenceMutation.set('k', 1, source: PreferenceSource.migration).stampsUserChange, isFalse);
      expect(PreferenceMutation.set('k', 1, source: PreferenceSource.migration).mayTravel, isFalse);
    });

    test('applying a remote change neither stamps nor echoes', () {
      const applied = PreferenceMutation.set('k', 1, source: PreferenceSource.remote);
      expect(applied.stampsUserChange, isFalse);
      expect(applied.mayTravel, isFalse);
    });
  });
}
