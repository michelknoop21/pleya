import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('verify-local builds the embedded web bundle before a release image', () {
    final script = File('pleya_server/scripts/verify-local.sh');
    expect(script.existsSync(), isTrue);

    final source = script.readAsStringSync();
    final webBuild = source.indexOf('../pleya_web/scripts/build-into-server.sh');
    final firstImageBuild = source.indexOf('docker build');

    expect(webBuild, greaterThanOrEqualTo(0), reason: 'a clean checkout has no embedded web bundle');
    expect(firstImageBuild, greaterThanOrEqualTo(0), reason: 'the release-image proof unexpectedly disappeared');
    expect(
      webBuild,
      lessThan(firstImageBuild),
      reason: 'the web bundle must exist before any Dockerfile release build starts',
    );
  });

  test('the embedded web build bootstraps locked dependencies on a clean checkout', () {
    final script = File('pleya_web/scripts/build-into-server.sh');
    expect(script.existsSync(), isTrue);

    final source = script.readAsStringSync();
    final install = source.indexOf('bun install --frozen-lockfile');
    final build = source.indexOf('bun run build');

    expect(install, greaterThanOrEqualTo(0), reason: 'a clean checkout has no node_modules directory');
    expect(build, greaterThanOrEqualTo(0));
    expect(install, lessThan(build), reason: 'Vite must be installed before Bun starts the web build');
  });
}
