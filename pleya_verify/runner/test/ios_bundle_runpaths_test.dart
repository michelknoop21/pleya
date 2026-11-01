import 'dart:io';

import 'package:test/test.dart';

import 'package:pleya_verify_runner/src/driver/ios_bundle_runpaths.dart';

void main() {
  const packagePath = '/work with spaces/build/ios/Debug-iphonesimulator/PackageFrameworks';
  String command(String path) => 'cmd LC_RPATH\n cmdsize 144\n path $path (offset 12)\n';

  test('recognizes only the exact package runpath, including spaces and fat slices', () {
    expect(hasPackageFrameworkRunpath(command(packagePath) * 2, packagePath), isTrue);
    expect(hasPackageFrameworkRunpath(command('$packagePath-old'), packagePath), isFalse);
    expect(hasPackageFrameworkRunpath(command('@executable_path/Frameworks'), packagePath), isFalse);
    expect(hasPackageFrameworkRunpath(command('/usr/lib/swift'), packagePath), isFalse);
  });

  test(
    'rejects a copied-code symlink escaping the app before invoking any tool',
    () async {
      final temp = Directory.systemTemp.createTempSync('ios-verify-symlink-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final app = Directory('${temp.path}/Runner.app')..createSync();
      final original = File('${temp.path}/original')..writeAsStringSync('must stay untouched');
      Link('${app.path}/Runner').createSync(original.path);
      var calls = 0;
      await expectLater(
        signIsolatedIosBundle(
          app: app,
          packageFrameworks: Directory('${temp.path}/PackageFrameworks'),
          run: (executable, args, {timeout = const Duration(seconds: 30)}) async {
            calls++;
            return ProcessResult(1, 0, '', '');
          },
          log: (_) {},
        ),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('escapes'))),
      );
      expect(calls, 0);
      expect(original.readAsStringSync(), 'must stay untouched');
    },
    skip: Platform.isWindows ? 'requires symlink support' : false,
  );

  test(
    'real dyld uses the embedded framework; every changed code object is signed',
    () async {
      final fixture = await _fixture();
      // Deliberately different host and embedded libraries expose an accidental
      // host dependency even on a machine where Documents access was granted.
      expect((await _run(fixture.executable.path, [])).stdout.toString().trim(), '1');
      final originalPackage = fixture.source.readAsBytesSync();
      await signIsolatedIosBundle(app: fixture.app, packageFrameworks: fixture.packages, run: _run, log: (_) {});
      for (final target in [fixture.app.path, '${fixture.app.path}/Runner.debug.dylib', fixture.framework.path]) {
        expect((await _run('codesign', ['--verify', '--strict', target])).exitCode, 0, reason: target);
      }
      expect((await _run(fixture.executable.path, [])).stdout.toString().trim(), '2');
      expect(fixture.source.readAsBytesSync(), originalPackage);
    },
    skip: !Platform.isMacOS ? 'real Apple linker, dyld and codesign regression runs on macOS' : false,
  );

  test(
    'missing embedded package fails before changing the copied executable',
    () async {
      final fixture = await _fixture();
      fixture.framework.deleteSync(recursive: true);
      final before = fixture.executable.readAsBytesSync();
      await expectLater(
        signIsolatedIosBundle(app: fixture.app, packageFrameworks: fixture.packages, run: _run, log: (_) {}),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('missing'))),
      );
      expect(fixture.executable.readAsBytesSync(), before);
    },
    skip: !Platform.isMacOS ? 'real Apple linker fixture runs on macOS' : false,
  );
}

Future<ProcessResult> _run(String executable, List<String> args, {Duration timeout = const Duration(seconds: 30)}) =>
    Process.run(executable, args).timeout(timeout);

Future<void> _checked(String executable, List<String> args) async {
  final result = await _run(executable, args);
  if (result.exitCode != 0) throw StateError('$executable: ${result.stderr}');
}

Future<({Directory temp, Directory app, Directory packages, Directory framework, File executable, File source})>
_fixture() async {
  final temp = Directory.systemTemp.createTempSync('ios-verify-real-dyld-');
  addTearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });
  final app = Directory('${temp.path}/Runner.app')..createSync();
  final packages = Directory('${temp.path}/build/ios/Debug-iphonesimulator/PackageFrameworks')
    ..createSync(recursive: true);
  final framework = Directory('${app.path}/Frameworks/Fixture.framework')..createSync(recursive: true);
  final sourceFramework = Directory('${packages.path}/Fixture.framework')..createSync();
  File('${app.path}/Info.plist').writeAsStringSync(_plist('nl.michelknoop.pleya.verify', 'Runner', 'APPL'));
  File('${framework.path}/Info.plist').writeAsStringSync(_plist('pleya.verify.fixture', 'Fixture', 'FMWK'));
  final c = File('${temp.path}/fixture.c');
  final source = File('${sourceFramework.path}/Fixture');
  for (final value in [1, 2]) {
    c.writeAsStringSync('int fixture_value(void) { return $value; }\n');
    await _checked('xcrun', [
      'clang',
      '-dynamiclib',
      '-install_name',
      '@rpath/Fixture.framework/Fixture',
      '-Wl,-rpath,${packages.path}',
      c.path,
      '-o',
      value == 1 ? source.path : '${framework.path}/Fixture',
    ]);
  }
  c.writeAsStringSync('extern int fixture_value(void); int debug_value(void) { return fixture_value(); }\n');
  final debug = '${app.path}/Runner.debug.dylib';
  await _checked('xcrun', [
    'clang',
    '-dynamiclib',
    '-install_name',
    '@rpath/Runner.debug.dylib',
    '-Wl,-rpath,${packages.path}',
    '-Wl,-rpath,@loader_path/Frameworks',
    c.path,
    source.path,
    '-o',
    debug,
  ]);
  c.writeAsStringSync(
    '#include <stdio.h>\nextern int debug_value(void); int main(void) { printf("%d\\n", debug_value()); }\n',
  );
  final executable = File('${app.path}/Runner');
  await _checked('xcrun', [
    'clang',
    c.path,
    debug,
    '-Wl,-rpath,@executable_path',
    '-Wl,-rpath,${packages.path}',
    '-Wl,-rpath,@executable_path/Frameworks',
    '-o',
    executable.path,
  ]);
  await _checked('codesign', ['--force', '--sign', '-', framework.path]);
  await _checked('codesign', ['--force', '--sign', '-', debug]);
  await _checked('codesign', ['--force', '--deep', '--sign', '-', app.path]);
  return (temp: temp, app: app, packages: packages, framework: framework, executable: executable, source: source);
}

String _plist(String id, String executable, String kind) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>$id</string>
<key>CFBundleExecutable</key><string>$executable</string><key>CFBundlePackageType</key><string>$kind</string>
<key>CFBundleVersion</key><string>1</string></dict></plist>''';
