/// Discovering which port a launched Pleya build actually bound, instead of
/// assuming the base port.
///
/// **Why this exists.** `AutomationServer.start()`
/// (`lib/automation/automation_server.dart`) walks `47317..47326` when the
/// base port is occupied, so a driver that hardcodes `127.0.0.1:47317` can
/// silently drive a *different* process than the one it just launched — a
/// leftover instance from an earlier run answers `/v1/health` perfectly and
/// the scenario reports PASS on evidence collected from the wrong app.
/// That exact contamination happened by hand during Fase 10 and had to be
/// traced with `lsof`; it is the worst failure mode this tool can have,
/// because it is indistinguishable from a real pass.
///
/// The app already publishes what is needed: `AutomationServer` writes
/// `<temporary dir>/pleya-verify/instance.json` (`{port, protocolVersion,
/// pid, token}`) before it logs its `listening on` line. `token` is the
/// per-launch bearer secret every `/v1/*` request now requires (see
/// [VerifyInstance.token]) — only this file carries it, and only a driver
/// reading it here ever sees it. Drivers [clearInstanceFile]
/// it *before* launching and [awaitInstance] afterwards, which makes a stale
/// read structurally impossible rather than heuristically unlikely: a file
/// that reappears after deletion can only have been written by the process
/// this driver started.
///
/// **Drivers pass a *list* of candidate paths, not one.** "Where
/// `getTemporaryDirectory()` points" is a `path_provider` implementation
/// detail, and not the one its name suggests: on both iOS and macOS it
/// resolves to `NSCachesDirectory`, so the file lands under
/// `Library/Caches/pleya-verify/`, not under `tmp/`. This was established by
/// running it, after a first attempt that assumed `NSTemporaryDirectory()`
/// found nothing and failed the launch. Probing the observed path first and
/// the plausible alternative second means a `path_provider` bump degrades
/// into "still works" instead of "every scenario fails to launch".
///
/// Pure `dart:io` — no Flutter import, so the driver-less Ubuntu CI job can
/// still load this library.
library;

import 'dart:convert';
import 'dart:io';

/// One launched app instance, as it announced itself on disk.
class VerifyInstance {
  final int port;
  final int protocolVersion;
  final int? pid;

  /// The per-launch bearer token `AutomationServer.start()` minted and
  /// wrote into `instance.json` alongside `port`/`pid` — see the auth
  /// contract on `AutomationServer` (`lib/automation/automation_server.dart`)
  /// and `pleya_verify/contract/verify_api_v1.md`. A driver reads it here
  /// and threads it into its [VerifyClient]; nothing else in this class
  /// exposes it. Deliberately absent from [toJson] and [toString] — an
  /// evidence bundle records *which* instance a run drove, never the secret
  /// that let it drive it.
  final String? token;

  /// Where this came from — an `instance.json` path, or `'driver log'` for
  /// [parseListeningPort]'s fallback. Recorded in the evidence bundle so a
  /// run says which channel identified the instance it drove.
  final String source;

  const VerifyInstance({
    required this.port,
    required this.protocolVersion,
    this.pid,
    this.token,
    required this.source,
  });

  Map<String, Object?> toJson() => {
    'port': port,
    'protocolVersion': protocolVersion,
    if (pid != null) 'pid': pid,
    'source': source,
  };

  @override
  String toString() => 'VerifyInstance(port: $port, pid: $pid, source: $source)';
}

/// Thrown when no instance announced itself in time — never swallowed into
/// a fallback on the base port, because "assume 47317" is the bug this
/// whole library exists to remove.
class InstanceDiscoveryException implements Exception {
  final String message;

  const InstanceDiscoveryException(this.message);

  @override
  String toString() => 'InstanceDiscoveryException: $message';
}

/// Removes a previous run's announcement from every candidate path, so
/// [awaitInstance] cannot read one. Safe when a file (or its whole
/// directory) does not exist.
void clearInstanceFile(Iterable<File> candidates) {
  for (final file in candidates) {
    try {
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // Left in place — [awaitInstance]'s `notBefore` check still rejects it.
    }
  }
}

/// Polls [candidates] until one holds an announcement written no earlier
/// than [notBefore], then decodes it. Candidates are checked in order, so
/// put the path the app is known to use first.
///
/// A file older than [notBefore] is *not* an error to report immediately —
/// it means [clearInstanceFile] could not remove it and the app has not yet
/// overwritten it, so polling continues and only the timeout message
/// mentions it. That keeps the "stale file" case loud instead of letting it
/// resolve to a wrong-but-plausible port.
Future<VerifyInstance> awaitInstance({
  required List<File> candidates,
  required DateTime notBefore,
  Duration timeout = const Duration(seconds: 20),
  Duration pollInterval = const Duration(milliseconds: 200),
}) async {
  if (candidates.isEmpty) {
    throw const InstanceDiscoveryException('no candidate instance.json path to watch');
  }
  final deadline = DateTime.now().add(timeout);
  var sawStale = false;
  Object? lastDecodeError;

  while (DateTime.now().isBefore(deadline)) {
    for (final file in candidates) {
      if (!file.existsSync()) continue;
      if (file.lastModifiedSync().isBefore(notBefore)) {
        sawStale = true;
        continue;
      }
      try {
        return _decode(file.readAsStringSync(), source: file.path);
      } catch (e) {
        // A half-written file — the app writes it in one go, but a read
        // can still land mid-write. Retry rather than fail the launch.
        lastDecodeError = e;
      }
    }
    await Future<void>.delayed(pollInterval);
  }

  final detail = StringBuffer(
    'no Pleya Verify instance announced itself within $timeout at any of: '
    '${candidates.map((f) => f.path).join(', ')}',
  );
  if (sawStale) {
    detail.write(
      ' — a file from before this launch is still there, which means the app never (re)wrote it: '
      'either it was not built with --dart-define=PLEYA_VERIFY=true, or it crashed before AutomationServer.start()',
    );
  }
  if (lastDecodeError != null) {
    detail.write(' — last decode error: $lastDecodeError');
  }
  throw InstanceDiscoveryException(detail.toString());
}

VerifyInstance _decode(String json, {required String source}) {
  final decoded = jsonDecode(json);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('instance.json is not a JSON object');
  }
  final port = decoded['port'];
  if (port is! int) {
    throw FormatException('instance.json has no integer "port" field (got: ${decoded['port']})');
  }
  return VerifyInstance(
    port: port,
    protocolVersion: decoded['protocolVersion'] is int ? decoded['protocolVersion'] as int : 0,
    pid: decoded['pid'] is int ? decoded['pid'] as int : null,
    token: decoded['token'] is String ? decoded['token'] as String : null,
    source: source,
  );
}

/// Cross-checks a `/v1/health` body against the instance a driver *meant*
/// to reach — the gate that actually closes the wrong-instance hole.
///
/// Discovering the port is not on its own enough: between reading
/// `instance.json` and the first request, the announced process could have
/// died and a leftover one could still own that port. `health.port` proves
/// the responder is the process that announced itself, and `health.bootedAt`
/// after [notBefore] proves it booted for *this* launch and is not an
/// instance from an earlier run.
///
/// A missing field is a hard failure too — an old build without these keys
/// is exactly the kind of mismatch worth stopping on.
void assertHealthIdentity(
  Map<String, Object?> health, {
  required VerifyInstance instance,
  required DateTime notBefore,
}) {
  final port = health['port'];
  if (port != instance.port) {
    throw InstanceDiscoveryException(
      'the app answering /v1/health reports port $port, but this driver launched the instance that '
      'announced port ${instance.port} (${instance.source}) — refusing to drive an instance this run did not start',
    );
  }

  final bootedAtRaw = health['bootedAt'];
  final bootedAt = bootedAtRaw is String ? DateTime.tryParse(bootedAtRaw) : null;
  if (bootedAt == null) {
    throw InstanceDiscoveryException(
      '/v1/health has no parseable "bootedAt" (got: $bootedAtRaw) — cannot prove this instance '
      'booted for this run',
    );
  }
  if (bootedAt.isBefore(notBefore)) {
    throw InstanceDiscoveryException(
      'the app answering /v1/health booted at $bootedAt, before this launch started at $notBefore — '
      'that is a leftover instance from an earlier run, not the one this driver started',
    );
  }
}

final RegExp _listeningLine = RegExp(r'\[PleyaVerify\] listening on 127\.0\.0\.1:(\d+)');

/// The fallback channel for a target whose temporary directory the runner
/// cannot locate: `AutomationServer.start()` logs
/// `[PleyaVerify] listening on 127.0.0.1:<port>` on boot, and a driver that
/// captures the app's stdout (macOS does) has that line in its own log.
///
/// Returns the *last* match, so a driver log spanning more than one launch
/// yields the current instance rather than the first one ever seen.
VerifyInstance? parseListeningPort(Iterable<String> driverLogLines) {
  int? port;
  for (final line in driverLogLines) {
    for (final match in _listeningLine.allMatches(line)) {
      port = int.tryParse(match.group(1)!) ?? port;
    }
  }
  if (port == null) return null;
  return VerifyInstance(port: port, protocolVersion: 1, source: 'driver log');
}
