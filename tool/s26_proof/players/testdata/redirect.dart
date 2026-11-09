// Fetches a URL with an Authorization header using dart:io's HttpClient, the
// client behind package:http's IOClient in the app. Args: url proxyHostPort
// rootPem secret. Prints the final status code.
import 'dart:io';

Future<void> main(List<String> args) async {
  final ctx = SecurityContext(withTrustedRoots: false)..setTrustedCertificates(args[2]);
  final client = HttpClient(context: ctx)..findProxy = (_) => 'PROXY ${args[1]}';
  final req = await client.getUrl(Uri.parse(args[0]));
  req.headers.set(HttpHeaders.authorizationHeader, args[3]);
  final resp = await req.close();
  await resp.drain<void>();
  stdout.writeln(resp.statusCode);
  client.close();
}
