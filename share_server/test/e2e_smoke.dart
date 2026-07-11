import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:pleya_share_server/src/pairing.dart';
import 'package:pleya_share_server/src/scanner.dart';
import 'package:pleya_share_server/src/server.dart';

/// End-to-end smoke test: boots the server in-process on a random port and
/// walks the full guest flow — pair, re-auth, library, Range-stream, watch.
/// Run with: dart run test/e2e_smoke.dart
Future<void> main() async {
  final tmp = Directory.systemTemp.createTempSync('pleya-share-e2e');
  final movies = Directory('${tmp.path}/movies')..createSync();
  final movieFile = File('${movies.path}/Test Film (2024).mp4')..writeAsBytesSync(List.generate(1000, (i) => i % 256));
  Directory('${tmp.path}/shows/My Show/Season 1').createSync(recursive: true);
  File('${tmp.path}/shows/My Show/Season 1/S01E02 - Pilot.mkv').writeAsBytesSync(List.filled(64, 7));

  final server = PleyaShareServer(
    roots: [
      MediaRoot(id: 'lib-movies', path: movies.path, name: 'Films', type: 'movies'),
      MediaRoot(id: 'lib-shows', path: '${tmp.path}/shows', name: 'Series', type: 'tvshows'),
    ],
    name: 'e2e-host',
    port: 0,
    dataDir: Directory('${tmp.path}/data'),
    fixedCode: '123456',
  );
  // Bind on an ephemeral port: port 0 → read back from the HttpServer.
  await server.start();
  final port = server.boundPort!;
  final base = 'http://127.0.0.1:$port';
  final http = HttpClient();

  Future<Map<String, dynamic>> call(String method, String path, {Map<String, Object?>? body, String? token}) async {
    final uri = Uri.parse('$base$path').replace(queryParameters: token != null ? {'token': token} : null);
    final request = await http.openUrl(method, uri);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    if (response.statusCode != 200) throw StateError('$method $path → ${response.statusCode}');
    return jsonDecode(text) as Map<String, dynamic>;
  }

  // 1. Wrong code is rejected.
  final badNonce = PleyaSharePairing.randomBytes(32);
  final badStart = await call('POST', '/pair/start', body: {'clientNonce': base64Encode(badNonce)});
  final badKey = await PleyaSharePairing.derivePairingKey('000000', base64Decode(badStart['salt'] as String));
  final badTag = PleyaSharePairing.computeAuthTag(
    key: badKey,
    hostNonce: base64Decode(badStart['hostNonce'] as String),
    clientNonce: badNonce,
    context: 'pair',
  );
  try {
    await call('POST', '/pair/complete', body: {
      'clientNonce': base64Encode(badNonce),
      'authTag': badTag,
      'deviceName': 'evil',
    });
    throw StateError('wrong code was accepted!');
  } on StateError catch (e) {
    assert(e.message.contains('403'), 'expected 403, got: ${e.message}');
  }

  // 2. Correct pairing.
  final nonce = PleyaSharePairing.randomBytes(32);
  final start = await call('POST', '/pair/start', body: {'clientNonce': base64Encode(nonce)});
  final hostNonce = base64Decode(start['hostNonce'] as String);
  final key = await PleyaSharePairing.derivePairingKey('123456', base64Decode(start['salt'] as String));
  final tag = PleyaSharePairing.computeAuthTag(key: key, hostNonce: hostNonce, clientNonce: nonce, context: 'pair');
  final complete = await call('POST', '/pair/complete', body: {
    'clientNonce': base64Encode(nonce),
    'authTag': tag,
    'deviceName': 'e2e-guest',
  });
  final sessionKey = await PleyaSharePairing.deriveSessionKey(key, hostNonce, nonce);
  final payload = await _decrypt(sessionKey, complete['payload'] as String);
  final pairId = payload['pairId'] as String;
  final pairSecret = base64Decode(payload['pairSecret'] as String);
  var token = payload['token'] as String;
  assert(pairId.isNotEmpty && token.isNotEmpty);

  // 3. Re-auth with pairSecret (simulates app restart).
  final nonce2 = PleyaSharePairing.randomBytes(32);
  final auth = await call('POST', '/auth/start', body: {'pairId': pairId, 'clientNonce': base64Encode(nonce2)});
  final hostNonce2 = base64Decode(auth['hostNonce'] as String);
  final tag2 = PleyaSharePairing.computeAuthTag(
    key: pairSecret,
    hostNonce: hostNonce2,
    clientNonce: nonce2,
    context: 'reconnect',
  );
  final auth2 = await call('POST', '/auth/complete', body: {
    'pairId': pairId,
    'clientNonce': base64Encode(nonce2),
    'authTag': tag2,
  });
  final sessionKey2 = await PleyaSharePairing.deriveSessionKey(pairSecret, hostNonce2, nonce2);
  token = (await _decrypt(sessionKey2, auth2['payload'] as String))['token'] as String;

  // 4. Library: movie + show/season/episode with parsed metadata.
  final library = await call('GET', '/library', token: token);
  final items = (library['items'] as List).cast<Map<String, dynamic>>();
  final movie = items.firstWhere((i) => i['kind'] == 'movie');
  assert(movie['title'] == 'Test Film' && movie['year'] == 2024, 'movie parse: $movie');
  final episode = items.firstWhere((i) => i['kind'] == 'episode');
  assert(episode['index'] == 2 && episode['grandparentTitle'] == 'My Show', 'episode parse: $episode');
  assert(items.any((i) => i['kind'] == 'show') && items.any((i) => i['kind'] == 'season'));

  // 5. Range-stream the movie.
  final encoded = base64UrlEncode(utf8.encode(movieFile.path)).replaceAll('=', '');
  final streamReq = await http.getUrl(Uri.parse('$base/stream/$encoded?token=$token'));
  streamReq.headers.set(HttpHeaders.rangeHeader, 'bytes=100-199');
  final streamRes = await streamReq.close();
  assert(streamRes.statusCode == 206, 'expected 206, got ${streamRes.statusCode}');
  final bytes = (await streamRes.fold<BytesBuilder>(BytesBuilder(), (b, chunk) => b..add(chunk))).toBytes();
  assert(bytes.length == 100 && bytes.first == 100, 'range bytes wrong: len=${bytes.length} first=${bytes.first}');

  // 6. Watch state round-trips per guest.
  await call('POST', '/watch', body: {'itemId': movieFile.path, 'progressMs': 4321, 'watched': false}, token: token);
  final library2 = await call('GET', '/library', token: token);
  final movie2 = (library2['items'] as List).cast<Map<String, dynamic>>().firstWhere((i) => i['kind'] == 'movie');
  assert(movie2['viewOffsetMs'] == 4321, 'watch overlay missing: $movie2');

  // 7. Unauthorized without token.
  final noTokenRes = await (await http.getUrl(Uri.parse('$base/library'))).close();
  assert(noTokenRes.statusCode == 401);

  await server.stop();
  http.close(force: true);
  tmp.deleteSync(recursive: true);
  stdout.writeln('e2e smoke: ALL OK');
}

Future<Map<String, Object?>> _decrypt(List<int> sessionKey, String encoded) async {
  final data = base64Decode(encoded);
  final box = SecretBox(
    data.sublist(12, data.length - 16),
    nonce: data.sublist(0, 12),
    mac: Mac(data.sublist(data.length - 16)),
  );
  final plain = await AesGcm.with256bits().decrypt(box, secretKey: SecretKey(sessionKey));
  return jsonDecode(utf8.decode(plain)) as Map<String, Object?>;
}
