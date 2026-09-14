import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/screens/main_screen.dart';

void main() {
  group('shouldRecoverTvTopNavFocusAfterReconnect', () {
    test('recovers focus when the reconnect pill had it and we just went online', () {
      expect(shouldRecoverTvTopNavFocusAfterReconnect(reconnectItemWasFocused: true, isOfflineNow: false), isTrue);
    });

    test('does not recover when the reconnect pill was not focused', () {
      expect(shouldRecoverTvTopNavFocusAfterReconnect(reconnectItemWasFocused: false, isOfflineNow: false), isFalse);
    });

    test('does not recover while still offline', () {
      expect(shouldRecoverTvTopNavFocusAfterReconnect(reconnectItemWasFocused: true, isOfflineNow: true), isFalse);
    });
  });
}
