import 'package:pleya_verify_runner/src/driver/ios_simulator_driver.dart';
import 'package:test/test.dart';

Map<String, Object?> _devices(List<Map<String, Object?>> iphones) => {
  'com.apple.CoreSimulator.SimRuntime.iOS-26-5': iphones,
  'com.apple.CoreSimulator.SimRuntime.tvOS-26-5': [
    {'name': 'Apple TV 4K', 'udid': 'TV', 'state': 'Booted'},
  ],
};

Map<String, Object?> _iphone(String udid, {bool booted = false}) => {
  'name': 'iPhone $udid',
  'udid': udid,
  'state': booted ? 'Booted' : 'Shutdown',
};

/// Without `PLEYA_VERIFY_IOS_UDID` the driver picks a simulator itself. It may
/// pick one booted iPhone, fall back to an available one, and must refuse to
/// guess between two booted ones (27 September 2026).
void main() {
  test('one booted iPhone is used, whatever else is listed', () {
    expect(pickIosSimulator(_devices([_iphone('A'), _iphone('B', booted: true), _iphone('C')])), 'B');
  });

  test('nothing booted falls back to an available iPhone', () {
    expect(pickIosSimulator(_devices([_iphone('A'), _iphone('C')])), isIn(['A', 'C']));
  });

  test('two booted iPhones are refused with both named and the variable to set', () {
    expect(
      () => pickIosSimulator(_devices([_iphone('A', booted: true), _iphone('B', booted: true)])),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('iPhone A A'), contains('iPhone B B'), contains('PLEYA_VERIFY_IOS_UDID')),
        ),
      ),
    );
  });

  test('no iPhone at all is an error, not a tvOS device', () {
    expect(() => pickIosSimulator(_devices([])), throwsStateError);
  });
}
