import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/settings/logs_screen.dart';
import 'package:pleya/utils/app_logger.dart';
import 'package:pleya/utils/log_upload.dart';
import 'package:pleya/utils/media_server_http_client.dart';

import '../test_helpers/notice_layer.dart';

/// Swallows console output. Entries still land in [MemoryLogOutput] because
/// recording happens in the printer, not the output — so the buffer fills
/// without 400 lines of noise in every test run.
class _SilentOutput extends LogOutput {
  @override
  // ignore: no-empty-block - deliberately drops everything
  void output(OutputEvent event) {}
}

/// device_info_plus talks over a platform channel with no implementation under
/// test, and its model classes cast every field eagerly — so the mock has to be
/// complete even though the header only reads osRelease and model. Tests run on
/// the macOS host, hence the macOS shape.
void installDeviceInfoMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/device_info'),
    (call) async => <String, dynamic>{
      'computerName': 'test-mac',
      'hostName': 'test-mac.local',
      'arch': 'arm64',
      'model': 'Mac16,1',
      'modelName': 'MacBook Pro',
      'kernelVersion': 'Darwin 25.5.0',
      'osRelease': '26.5',
      'majorVersion': 26,
      'minorVersion': 5,
      'patchVersion': 0,
      'activeCPUs': 10,
      'memorySize': 17179869184,
      'cpuFrequency': 0,
      'systemGUID': null,
    },
  );
}

/// Records what the upload action sent and how often.
///
/// The relay answers everything but a stored log in `text/plain`, which is what
/// used to turn each distinct refusal into one FormatException and one generic
/// line on screen.
final class _Relay {
  _Relay(this.handler);

  final Future<http.Response> Function(http.Request request) handler;
  final List<String> requests = [];

  MediaServerHttpClient client() => MediaServerHttpClient(
    client: MockClient((request) {
      requests.add(request.body);
      return handler(request);
    }),
  );
}

_Relay _answering(int status, String body, {Map<String, String> headers = const {'content-type': 'text/plain'}}) =>
    _Relay((_) async => http.Response(body, status, headers: headers));

_Relay _accepting() => _answering(200, '{"id":"abc12345"}', headers: const {'content-type': 'application/json'});

/// The log screen is opened precisely when a session has produced a lot to
/// read, so it must not pay for entries that are off screen. It used to build
/// every entry into one `RichText`, which meant a long diagnostic session had
/// to lay out tens of thousands of spans before anything painted.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
    PackageInfo.setMockInitialValues(
      appName: 'Pleya',
      packageName: 'nl.michelknoop.pleya',
      version: '2.8.0',
      buildNumber: '212',
      buildSignature: '',
    );
    installDeviceInfoMock();
  });

  late Logger previousLogger;

  setUp(() {
    // Error notices are persistent by design, so one left standing by the
    // previous test blocks the next one from being shown at all.
    resetNotices();
    MemoryLogOutput.clearLogs();
    previousLogger = appLogger;
    appLogger = Logger(printer: MemoryAwareLogPrinter(SimplePrinter()), output: _SilentOutput(), level: Level.info);
  });

  tearDown(() {
    appLogger = previousLogger;
    MemoryLogOutput.clearLogs();
  });

  Future<void> pumpLogs(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LogsScreen()));
    await tester.pump();
  }

  testWidgets('builds only the entries near the viewport, not the whole buffer', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (var i = 0; i < 400; i++) {
      appLogger.i('entry $i');
    }
    expect(MemoryLogOutput.getLogs(), hasLength(400));

    await pumpLogs(tester);

    final built = tester.widgetList(find.byType(SelectableText)).length;
    expect(built, greaterThan(0), reason: 'the visible entries should render');
    expect(built, lessThan(100), reason: 'a lazy list must not build all 400 entries up front; got $built');
  });

  testWidgets('shows the empty state when nothing has been logged', (tester) async {
    await pumpLogs(tester);

    expect(find.text(t.messages.noLogsAvailable), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
  });

  Future<_Relay> pumpAndUpload(WidgetTester tester, _Relay relay, {int taps = 1, DateTime Function()? clock}) async {
    final client = relay.client();
    addTearDown(client.close);

    appLogger.i('something worth reporting');
    await tester.pumpWidget(
      MaterialApp(
        builder: noticeLayer,
        home: LogsScreen(uploadClient: client, uploadClock: clock),
      ),
    );
    await tester.pump();

    for (var i = 0; i < taps; i++) {
      await tester.tap(find.byTooltip(t.logs.uploadLogs), warnIfMissed: false);
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    return relay;
  }

  testWidgets('shows the log ID when the relay accepts the upload', (tester) async {
    await pumpAndUpload(tester, _accepting());

    expect(find.text(t.messages.logsUploaded), findsOneWidget);
    expect(find.text('abc12345'), findsOneWidget);
  });

  testWidgets('names the size limit on 413 instead of the generic failure', (tester) async {
    await pumpAndUpload(tester, _answering(413, 'Log too large (max 1MB)\n'));

    expect(find.text(t.messages.logsUploadTooLarge), findsOneWidget);
    expect(find.text(t.messages.logsUploadFailed), findsNothing);
  });

  testWidgets('says how long to wait on 429', (tester) async {
    await pumpAndUpload(tester, _answering(429, 'Rate limited: 1 upload per minute\n'));

    expect(find.text(t.messages.logsUploadRateLimited(seconds: 60)), findsOneWidget);
  });

  testWidgets('honours Retry-After when the server sends one', (tester) async {
    await pumpAndUpload(
      tester,
      _answering(429, 'Rate limited\n', headers: const {'content-type': 'text/plain', 'retry-after': '20'}),
    );

    expect(find.text(t.messages.logsUploadRateLimited(seconds: 20)), findsOneWidget);
  });

  testWidgets('honours the date form of Retry-After too', (tester) async {
    // RFC 9110 allows a delay in seconds or an HTTP date, and a relay behind a
    // proxy may well send the second. Since the value now decides how long the
    // action stays shut, reading only one form means overruling the server.
    final now = DateTime(2026, 8, 21, 21, 53, 39);
    final relay = _answering(
      429,
      'Rate limited\n',
      headers: {
        'content-type': 'text/plain',
        'retry-after': HttpDate.format(now.toUtc().add(const Duration(seconds: 30))),
      },
    );

    await pumpAndUpload(tester, relay, clock: () => now);

    expect(find.text(t.messages.logsUploadRateLimited(seconds: 30)), findsOneWidget);
    expect(find.text(t.messages.logsUploadRateLimited(seconds: 60)), findsNothing);

    await tester.tap(find.byTooltip(t.logs.uploadLogs), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(relay.requests, hasLength(1), reason: 'the date the server named has not passed yet');
  });

  testWidgets('a Retry-After it cannot read falls back to the known window', (tester) async {
    final relay = await pumpAndUpload(
      tester,
      _answering(429, 'Rate limited\n', headers: const {'content-type': 'text/plain', 'retry-after': 'soon'}),
    );

    expect(find.text(t.messages.logsUploadRateLimited(seconds: 60)), findsOneWidget);
    expect(relay.requests, hasLength(1));
  });

  testWidgets('a 429 blocks the next press instead of asking again', (tester) async {
    // The in-flight guard only catches a press that overlaps a request, and a
    // refusal comes back in about sixty milliseconds. During the PS-4 round
    // that produced eleven POSTs and eleven 429s in seven seconds, one per
    // press (log kzq7c, 21:53:39 to 21:53:46).
    final relay = await pumpAndUpload(tester, _answering(429, 'Rate limited: 1 upload per minute\n'));
    expect(relay.requests, hasLength(1));
    expect(find.text(t.messages.logsUploadRateLimited(seconds: 60)), findsOneWidget);

    await tester.tap(find.byTooltip(t.logs.uploadLogs), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(relay.requests, hasLength(1), reason: 'the second press must not reach the relay inside the window');
    expect(find.text(t.messages.logsUploadRateLimited(seconds: 60)), findsOneWidget);
  });

  testWidgets('the block lasts as long as Retry-After says, not the fallback', (tester) async {
    final relay = await pumpAndUpload(
      tester,
      _answering(429, 'Rate limited\n', headers: const {'content-type': 'text/plain', 'retry-after': '20'}),
    );

    await tester.tap(find.byTooltip(t.logs.uploadLogs), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(relay.requests, hasLength(1));
    expect(find.text(t.messages.logsUploadRateLimited(seconds: 20)), findsOneWidget);
    expect(find.text(t.messages.logsUploadRateLimited(seconds: 60)), findsNothing);
  });

  testWidgets('the block lifts once the window has passed', (tester) async {
    // The clock is the test's, not the machine's: nobody waits out a real
    // minute to prove a minute-long window ends.
    var now = DateTime(2026, 8, 21, 21, 53, 39);
    var status = 429;
    final relay = _Relay(
      (_) async => status == 429
          ? http.Response('Rate limited\n', 429, headers: const {'content-type': 'text/plain'})
          : http.Response('{"id":"abc12345"}', 200, headers: const {'content-type': 'application/json'}),
    );

    await pumpAndUpload(tester, relay, clock: () => now);
    expect(relay.requests, hasLength(1));

    now = now.add(const Duration(seconds: 59));
    await tester.tap(find.byTooltip(t.logs.uploadLogs), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(relay.requests, hasLength(1), reason: 'one second short of the window is still short');
    expect(find.text(t.messages.logsUploadRateLimited(seconds: 1)), findsOneWidget);

    now = now.add(const Duration(seconds: 2));
    status = 200;
    await tester.tap(find.byTooltip(t.logs.uploadLogs), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(relay.requests, hasLength(2), reason: 'the window passed, so the press must reach the relay');
    expect(find.text('abc12345'), findsOneWidget);
  });

  testWidgets('a relay that refuses without saying for how long gets asked less often', (tester) async {
    // No `Retry-After` means the minute is a guess. A refusal on the far side
    // of that guess says the guess was wrong, so the next one is longer —
    // bounded, so it cannot grow into never asking again.
    var now = DateTime(2026, 8, 21, 21, 53, 39);
    final relay = _answering(429, 'Rate limited\n');

    await pumpAndUpload(tester, relay, clock: () => now);
    expect(relay.requests, hasLength(1));

    now = now.add(const Duration(seconds: 61));
    await tester.tap(find.byTooltip(t.logs.uploadLogs), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(relay.requests, hasLength(2));
    expect(find.text(t.messages.logsUploadRateLimited(seconds: 120)), findsOneWidget);

    now = now.add(const Duration(seconds: 61));
    await tester.tap(find.byTooltip(t.logs.uploadLogs), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(relay.requests, hasLength(2), reason: 'the doubled window has not passed yet');
  });

  testWidgets('names a refused upload as a refusal', (tester) async {
    await pumpAndUpload(tester, _answering(400, 'Empty body\n'));

    expect(find.text(t.messages.logsUploadRefused(status: 400)), findsOneWidget);
  });

  testWidgets('names a server-side failure as the server having a problem', (tester) async {
    await pumpAndUpload(tester, _answering(503, 'Log store full\n'));

    expect(find.text(t.messages.logsUploadServerError(status: 503)), findsOneWidget);
  });

  testWidgets('reports an unreachable server as a network problem', (tester) async {
    await pumpAndUpload(tester, _Relay((_) async => throw http.ClientException('Failed host lookup')));

    expect(find.text(t.messages.logsUploadNetworkError), findsOneWidget);
    expect(find.text(t.messages.logsUploadFailed), findsNothing);
  });

  testWidgets('reports a timeout as a network problem', (tester) async {
    await pumpAndUpload(tester, _Relay((_) async => throw TimeoutException('connect')));

    expect(find.text(t.messages.logsUploadNetworkError), findsOneWidget);
  });

  testWidgets('a second press while uploading does not fire a second request', (tester) async {
    // Pressing again after a slow first attempt would hit the relay's
    // one-per-minute limit and report a rate limit the user caused.
    final completer = Completer<http.Response>();
    final relay = await pumpAndUpload(tester, _Relay((_) => completer.future), taps: 3);

    expect(relay.requests, hasLength(1));
    final uploadButton = tester.widget<IconButton>(
      find.ancestor(of: find.byTooltip(t.logs.uploadLogs), matching: find.byType(IconButton)),
    );
    expect(uploadButton.onPressed, isNull, reason: 'the action must be disabled while an upload is in flight');

    completer.complete(http.Response('{"id":"abc12345"}', 200, headers: const {'content-type': 'application/json'}));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(t.messages.logsUploaded), findsOneWidget);
  });

  testWidgets('uploads no more than the relay accepts', (tester) async {
    for (var i = 0; i < 4000; i++) {
      appLogger.i('entry $i ${'x' * 400}');
    }

    final relay = await pumpAndUpload(tester, _accepting());

    expect(relay.requests, hasLength(1));
    expect(utf8.encode(relay.requests.single).length, lessThanOrEqualTo(logUploadMaxBytes));
    expect(relay.requests.single, contains('KB of older log lines dropped'));
  });

  testWidgets('still renders when the device probe fails', (tester) async {
    // The header is built unawaited from initState, so an unguarded throw here
    // used to surface as an unhandled async error and cost the version line too.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/device_info'),
      (call) async => throw PlatformException(code: 'UNAVAILABLE'),
    );
    addTearDown(installDeviceInfoMock);

    appLogger.i('entry after a failing probe');
    await pumpLogs(tester);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(SelectableText), findsWidgets);
  });
}
