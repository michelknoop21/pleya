import 'dart:async';
import 'dart:convert';

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

import '../test_helpers/notices.dart';

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
    MemoryLogOutput.clearLogs();
    // The notice controller is global and caps how many notices are visible at
    // once, so a message left behind by the previous test pushes this test's
    // own message into the queue, where `noticeTitles()` cannot see it.
    resetNotices();
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

  Future<_Relay> pumpAndUpload(WidgetTester tester, _Relay relay, {int taps = 1}) async {
    final client = relay.client();
    addTearDown(client.close);

    appLogger.i('something worth reporting');
    await tester.pumpWidget(MaterialApp(home: LogsScreen(uploadClient: client)));
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

    expect(noticeTitles(), contains(t.messages.logsUploadTooLarge));
    expect(noticeTitles(), isNot(contains(t.messages.logsUploadFailed)));
  });

  testWidgets('says how long to wait on 429', (tester) async {
    await pumpAndUpload(tester, _answering(429, 'Rate limited: 1 upload per minute\n'));

    expect(noticeTitles(), contains(t.messages.logsUploadRateLimited(seconds: 60)));
  });

  testWidgets('honours Retry-After when the server sends one', (tester) async {
    await pumpAndUpload(
      tester,
      _answering(429, 'Rate limited\n', headers: const {'content-type': 'text/plain', 'retry-after': '20'}),
    );

    expect(noticeTitles(), contains(t.messages.logsUploadRateLimited(seconds: 20)));
  });

  testWidgets('names a refused upload as a refusal', (tester) async {
    await pumpAndUpload(tester, _answering(400, 'Empty body\n'));

    expect(noticeTitles(), contains(t.messages.logsUploadRefused(status: 400)));
  });

  testWidgets('names a server-side failure as the server having a problem', (tester) async {
    await pumpAndUpload(tester, _answering(503, 'Log store full\n'));

    expect(noticeTitles(), contains(t.messages.logsUploadServerError(status: 503)));
  });

  testWidgets('reports an unreachable server as a network problem', (tester) async {
    await pumpAndUpload(tester, _Relay((_) async => throw http.ClientException('Failed host lookup')));

    expect(noticeTitles(), contains(t.messages.logsUploadNetworkError));
    expect(noticeTitles(), isNot(contains(t.messages.logsUploadFailed)));
  });

  testWidgets('reports a timeout as a network problem', (tester) async {
    await pumpAndUpload(tester, _Relay((_) async => throw TimeoutException('connect')));

    expect(noticeTitles(), contains(t.messages.logsUploadNetworkError));
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
