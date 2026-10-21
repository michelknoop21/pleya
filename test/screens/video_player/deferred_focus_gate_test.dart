import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/screens/video_player/deferred_focus_gate.dart';

void main() {
  group('DeferredFocusGate', () {
    test('vraagt direct als niets blokkeert', () {
      var requests = 0;
      DeferredFocusGate(isBlocked: () => false, request: () => requests++).ask();
      expect(requests, 1);
    });

    test('houdt een verzoek vast achter het infopaneel en speelt het af bij loslaten', () {
      var blocked = true;
      var requests = 0;
      final gate = DeferredFocusGate(isBlocked: () => blocked, request: () => requests++);

      gate.ask();
      expect(requests, 0);
      expect(gate.pending, isTrue);

      gate.retry();
      expect(requests, 0, reason: 'nog geblokkeerd');

      blocked = false;
      gate.retry();
      expect(requests, 1);
      gate.retry();
      expect(requests, 1, reason: 'een verzoek wordt één keer afgespeeld');
    });

    test('cancel gooit een openstaand verzoek weg', () {
      var blocked = true;
      var requests = 0;
      final gate = DeferredFocusGate(isBlocked: () => blocked, request: () => requests++);
      gate.ask();
      gate.cancel();
      blocked = false;
      gate.retry();
      expect(requests, 0);
    });
  });
}
