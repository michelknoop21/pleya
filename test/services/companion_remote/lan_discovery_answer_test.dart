import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/companion_remote/lan_discovery_service.dart';

Map<String, dynamic> _beacon({String app = 'pleya', String platform = 'tvOS', String clientId = 'tv-1'}) => {
  'app': app,
  'platform': platform,
  'clientId': clientId,
};

void main() {
  group('LanDiscoveryService.shouldAnswerBeacon (A-23d: een iPhone antwoordt de Apple TV)', () {
    test('beantwoordt de beacon van een Apple TV', () {
      expect(LanDiscoveryService.shouldAnswerBeacon(_beacon(), ownClientIds: {'phone-1'}), isTrue);
    });

    test('beantwoordt zijn eigen beacon niet', () {
      expect(LanDiscoveryService.shouldAnswerBeacon(_beacon(clientId: 'phone-1'), ownClientIds: {'phone-1'}), isFalse);
    });

    test('beantwoordt geen ander apparaat dan een Apple TV', () {
      expect(LanDiscoveryService.shouldAnswerBeacon(_beacon(platform: 'iOS'), ownClientIds: {'phone-1'}), isFalse);
      expect(LanDiscoveryService.shouldAnswerBeacon(_beacon(platform: 'macOS'), ownClientIds: {'phone-1'}), isFalse);
    });

    test('negeert pakketten van een andere app', () {
      expect(LanDiscoveryService.shouldAnswerBeacon(_beacon(app: 'other'), ownClientIds: {'phone-1'}), isFalse);
    });
  });
}
