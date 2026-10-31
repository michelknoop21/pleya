import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_server.dart';

void main() {
  test('POST /v1/window knows the three names configure_view accepts', () {
    expect(automationOrientations('portrait'), [DeviceOrientation.portraitUp]);
    expect(automationOrientations('landscapeLeft'), [DeviceOrientation.landscapeLeft]);
    expect(automationOrientations('landscapeRight'), [DeviceOrientation.landscapeRight]);
  });

  test('an unknown name is refused rather than guessed', () {
    expect(automationOrientations('diagonal'), isNull);
  });
}
