import 'dart:io';

import 'package:pleya_share_server/src/scanner.dart';
import 'package:pleya_share_server/src/server.dart';

/// Headless Pleya Share host for NAS/Docker.
///
/// Usage:
///   pleya_share_server --media /media/movies:movies:Films \
///                      --media /media/series:tvshows:Series \
///                      [--name "NAS"] [--port 48634] [--data /data] [--code 123456]
///
/// Environment variable equivalents (used when flags are absent):
///   PLEYA_MEDIA  comma-separated `path[:type[:name]]` entries
///   PLEYA_NAME, PLEYA_PORT, PLEYA_DATA, PLEYA_CODE
Future<void> main(List<String> args) async {
  final mediaSpecs = <String>[];
  String? name;
  int? port;
  String? data;
  String? code;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--media':
        mediaSpecs.add(args[++i]);
      case '--name':
        name = args[++i];
      case '--port':
        port = int.parse(args[++i]);
      case '--data':
        data = args[++i];
      case '--code':
        code = args[++i];
      case '--help' || '-h':
        stdout.writeln('usage: pleya_share_server --media <path[:type[:name]]> [--name N] '
            '[--port 48634] [--data DIR] [--code 123456]');
        return;
      default:
        stderr.writeln('unknown argument: ${args[i]}');
        exitCode = 64;
        return;
    }
  }

  final env = Platform.environment;
  if (mediaSpecs.isEmpty && env['PLEYA_MEDIA'] != null) {
    mediaSpecs.addAll(env['PLEYA_MEDIA']!.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
  }
  name ??= env['PLEYA_NAME'] ?? Platform.localHostname;
  port ??= int.tryParse(env['PLEYA_PORT'] ?? '') ?? 48634;
  data ??= env['PLEYA_DATA'] ?? './data';
  code ??= env['PLEYA_CODE'];

  if (mediaSpecs.isEmpty) {
    stderr.writeln('no media roots configured — pass --media or set PLEYA_MEDIA');
    exitCode = 64;
    return;
  }
  if (code != null && !RegExp(r'^\d{6}$').hasMatch(code)) {
    stderr.writeln('--code must be exactly 6 digits');
    exitCode = 64;
    return;
  }

  final roots = <MediaRoot>[];
  for (final spec in mediaSpecs) {
    final parts = spec.split(':');
    final path = parts[0];
    final type = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : 'mixed';
    final rootName = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : path.split('/').last;
    if (!const {'movies', 'tvshows', 'mixed'}.contains(type)) {
      stderr.writeln('invalid library type "$type" in "$spec" (movies|tvshows|mixed)');
      exitCode = 64;
      return;
    }
    roots.add(MediaRoot(id: 'share-$rootName-${roots.length}', path: path, name: rootName, type: type));
  }

  final server = PleyaShareServer(
    roots: roots,
    name: name,
    port: port,
    dataDir: Directory(data),
    fixedCode: code,
  );
  await server.start();

  // Keep running until SIGTERM/SIGINT (Docker stop).
  await Future.any([ProcessSignal.sigint.watch().first, ProcessSignal.sigterm.watch().first]);
  stdout.writeln('shutting down');
  await server.stop();
}
