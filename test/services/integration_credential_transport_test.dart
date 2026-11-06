import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/integration_credential_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.pleya/icloud_kvs');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('private credential transport carries account and CAS tag without using KVS writes', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'credentialRead')
        return {'account': 'apple-account', 'tag': 'revision-2', 'payload': 'private'};
      if (call.method == 'credentialWrite') return null;
      fail('Credentials must never reach ordinary KVS methods');
    });
    final transport = CloudKitIntegrationCredentialTransport();
    final snapshot = await transport.read();
    await transport.write(snapshot, 'next-private-payload');

    expect(calls.map((call) => call.method), ['credentialRead', 'credentialWrite']);
    expect(calls.last.arguments, {'account': 'apple-account', 'tag': 'revision-2', 'payload': 'next-private-payload'});
  });

  test('missing account cannot become an empty, writable cloud snapshot', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => {});
    await expectLater(CloudKitIntegrationCredentialTransport().read(), throwsFormatException);
  });
}
