import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/settings/logs_screen.dart';
import 'package:pleya/utils/app_logger.dart';

/// Swallows console output. Entries still land in [MemoryLogOutput] because
/// recording happens in the printer, not the output — so the buffer fills
/// without 400 lines of noise in every test run.
class _SilentOutput extends LogOutput {
  @override
  // ignore: no-empty-block - deliberately drops everything
  void output(OutputEvent event) {}
}

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
    // device_info_plus talks over a platform channel with no implementation
    // under test, and its model classes cast every field eagerly — so the mock
    // has to be complete even though the header only reads osRelease and
    // model. Tests run on the macOS host, hence the macOS shape.
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
  });

  late Logger previousLogger;

  setUp(() {
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
}
