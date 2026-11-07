import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/integration_credential_codec.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/seerr/seerr_session.dart';

import '../test_helpers/prefs.dart';

/// The paired runner starts separate Dart VMs, so CredentialVault's cached key
/// cannot accidentally be shared between the simulated sending/receiving device.
void main() {
  const role = String.fromEnvironment('CREDENTIAL_TEST_ROLE', defaultValue: 'standalone');
  const directory = String.fromEnvironment('CREDENTIAL_TEST_DIR');
  const key = 'user_plex-home-plex.a1b2c3d4e5f60718-e434272903092b4e_seerr_session';
  test('credential codec uses the receiving device key ($role)', () async {
    resetSharedPreferencesForTest();
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString('credential_vault_key_v1', base64Encode(List.filled(32, role == 'source' ? 7 : 9)));
    File? wire;
    if (role != 'standalone') {
      final folder = Directory(directory);
      expect(folder.parent.resolveSymbolicLinksSync(), Directory('/tmp').resolveSymbolicLinksSync());
      expect(folder.uri.pathSegments.where((s) => s.isNotEmpty).last, startsWith('pleya-credential-isolation-'));
      wire = File('${folder.path}/wire.json');
    }
    if (role == 'source') {
      const source = SeerrSession(
        baseUrl: 'https://requests.test',
        authMode: SeerrAuthMode.apiKey,
        apiKey: 'synthetic-secret',
      );
      final payload = await IntegrationCredentialCodec.toCloud(key, await source.encode());
      await wire!.writeAsString(jsonEncode(payload));
      return;
    }
    final payload = role == 'receiver'
        ? Map<String, dynamic>.from(jsonDecode(await wire!.readAsString()) as Map)
        : <String, dynamic>{'base_url': 'https://requests.test', 'auth_mode': 'apiKey', 'api_key': 'synthetic-secret'};
    final local = await IntegrationCredentialCodec.fromCloud(key, payload);
    expect((await SeerrSession.decode(local)).apiKey, 'synthetic-secret');
    final protected = jsonDecode(local)['api_key'] as String;
    final box = jsonDecode(protected.substring('enc:v1:'.length));
    final secretBox = SecretBox(
      base64Decode(box['c'] as String),
      nonce: base64Decode(box['n'] as String),
      mac: Mac(base64Decode(box['m'] as String)),
    );
    final algorithm = AesGcm.with256bits();
    expect(
      utf8.decode(await algorithm.decrypt(secretBox, secretKey: SecretKey(List.filled(32, 9)))),
      'synthetic-secret',
    );
    await expectLater(algorithm.decrypt(secretBox, secretKey: SecretKey(List.filled(32, 7))), throwsA(anything));
  });
}
