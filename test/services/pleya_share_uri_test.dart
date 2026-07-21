import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/pleya_share/pleya_share_uri.dart';

void main() {
  test('pair URI round-trips ips, port, code, salt', () {
    const original = PleyaSharePairUri(
      ips: ['192.168.1.5', '10.0.0.2'],
      port: 48634,
      code: '123456',
      saltB64: 'c2FsdA==',
    );
    final parsed = PleyaSharePairUri.tryParse(original.build())!;
    expect(parsed.ips, ['192.168.1.5', '10.0.0.2']);
    expect(parsed.port, 48634);
    expect(parsed.code, '123456');
    expect(parsed.saltB64, 'c2FsdA==');
  });

  test('rejects non-pair and malformed links', () {
    expect(PleyaSharePairUri.tryParse('https://example.com'), isNull);
    expect(PleyaSharePairUri.tryParse('pleya-share://pair?code=12&salt=x&ips=1.1.1.1'), isNull); // bad code
    expect(PleyaSharePairUri.tryParse('pleya-share://pair?code=123456&salt=x'), isNull); // no ips
    expect(PleyaSharePairUri.tryParse('garbage'), isNull);
  });

  test('defaults the port when omitted', () {
    final parsed = PleyaSharePairUri.tryParse('pleya-share://pair?code=123456&salt=abc&ips=1.2.3.4')!;
    expect(parsed.port, 48634);
  });
}
