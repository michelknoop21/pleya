import 'dart:io';

import 'package:pleya_verify_runner/src/transport/verify_client.dart';
import 'package:test/test.dart';

/// Parses `### `METHOD /path`` headers out of the transport spec — the
/// same minimal shape `test/automation/transport_contract_test.dart` (the
/// app side of [C1]) reads, so a new endpoint added to one side without the
/// other fails somewhere. A header may carry example query params (e.g.
/// `GET /v1/events?since=N`); [VerifyClient.implementedEndpoints] lists the
/// bare path, so those are stripped here rather than by loosening the
/// shared regex the app-side test also uses.
List<VerifyEndpoint> _specEndpoints(String contents) {
  final pattern = RegExp(r'^### `([A-Z]+) (/\S+)`$', multiLine: true);
  return [for (final m in pattern.allMatches(contents)) (method: m.group(1)!, path: m.group(2)!.split('?').first)];
}

void main() {
  // Resolved relative to the package root (`pleya_verify/runner/`), which is
  // `dart test`'s working directory.
  final specFile = File('../contract/verify_api_v1.md');

  test('spec file exists and declares at least /v1/health', () {
    expect(specFile.existsSync(), isTrue, reason: 'pleya_verify/contract/verify_api_v1.md must exist');
    final endpoints = _specEndpoints(specFile.readAsStringSync());
    expect(endpoints, contains((method: 'GET', path: '/v1/health')));
  });

  test('VerifyClient implements exactly the endpoints the spec documents', () {
    final specEndpoints = _specEndpoints(specFile.readAsStringSync()).toSet();
    final clientEndpoints = VerifyClient.implementedEndpoints.toSet();

    final missingFromClient = specEndpoints.difference(clientEndpoints);
    expect(
      missingFromClient,
      isEmpty,
      reason: 'Spec endpoints with no VerifyClient method (add one, and list it in implementedEndpoints)',
    );

    final missingFromSpec = clientEndpoints.difference(specEndpoints);
    expect(
      missingFromSpec,
      isEmpty,
      reason: 'VerifyClient claims an endpoint the spec does not document — remove it or update the spec',
    );
  });
}
