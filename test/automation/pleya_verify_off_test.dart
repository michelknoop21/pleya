import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_bootstrap.dart';
import 'package:pleya/automation/pleya_verify.dart';

void main() {
  test('kPleyaVerify is false in a normal `flutter test` run', () {
    expect(kPleyaVerify, isFalse);
  });

  test('AutomationBootstrap.start() is a no-op when kPleyaVerify is false', () async {
    await AutomationBootstrap.start();
    expect(AutomationBootstrap.instanceOrNull, isNull);
  });
}
