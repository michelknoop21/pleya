import 'package:flutter/services.dart';

class IntegrationCredentialSnapshot {
  const IntegrationCredentialSnapshot({required this.account, required this.payload, this.tag});
  final String account;
  final String? payload;
  final String? tag;
}

abstract class IntegrationCredentialTransport {
  Future<IntegrationCredentialSnapshot> read();
  Future<void> write(IntegrationCredentialSnapshot expected, String payload);
}

/// Only the native private CloudKit path implements this channel. In particular
/// there is no KVS, plaintext file or shared-vault-key fallback.
class CloudKitIntegrationCredentialTransport implements IntegrationCredentialTransport {
  static const _channel = MethodChannel('com.pleya/icloud_kvs');

  @override
  Future<IntegrationCredentialSnapshot> read() async {
    final value = await _channel.invokeMapMethod<String, dynamic>('credentialRead');
    if (value == null || value['account'] is! String) {
      throw const FormatException('Missing credential account');
    }
    return IntegrationCredentialSnapshot(
      account: value['account'] as String,
      payload: value['payload'] as String?,
      tag: value['tag'] as String?,
    );
  }

  @override
  Future<void> write(IntegrationCredentialSnapshot expected, String payload) => _channel.invokeMethod<void>(
    'credentialWrite',
    {'account': expected.account, 'tag': expected.tag, 'payload': payload},
  );
}
