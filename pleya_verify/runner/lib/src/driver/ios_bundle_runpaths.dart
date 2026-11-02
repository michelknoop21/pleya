import 'dart:io';

import 'simulator_boot.dart';

/// Prepare only the copied Verify app, never Xcode's original product.
/// SwiftPM's absolute build runpath precedes the embedded frameworks on Xcode
/// 27. A checkout in Documents then stalls dyld in a host privacy check before
/// main. The installed app must use its own packaged framework instead.
Future<void> signIsolatedIosBundle({
  required Directory app,
  required Directory packageFrameworks,
  required ProcessRunner run,
  required void Function(String) log,
}) async {
  final appRoot = app.resolveSymbolicLinksSync();
  final packagePath = packageFrameworks.absolute.uri.normalizePath().toFilePath().replaceFirst(RegExp(r'/$'), '');
  final binaries = <File>[File('${app.path}/Runner')];
  final frameworkRoot = Directory('${app.path}/Frameworks');
  for (final entry in app.listSync()) {
    if (entry.path.endsWith('.dylib')) binaries.add(File(entry.path));
  }
  if (frameworkRoot.existsSync()) {
    for (final entry in frameworkRoot.listSync()) {
      if (entry.path.endsWith('.framework')) {
        final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
        binaries.add(File('${entry.path}/${name.substring(0, name.length - '.framework'.length)}'));
      } else if (entry.path.endsWith('.dylib')) {
        binaries.add(File(entry.path));
      }
    }
  }

  Future<ProcessResult> checked(String executable, List<String> args) async {
    final result = await run(executable, args);
    if (result.exitCode != 0) {
      throw StateError('$executable failed preparing isolated iOS app (exit ${result.exitCode}): ${result.stderr}');
    }
    return result;
  }

  // Validate the whole plan before changing any binary. In particular a copied
  // framework symlink must not let this preparation alter the original build.
  for (final binary in binaries) {
    if (!binary.resolveSymbolicLinksSync().startsWith('$appRoot/')) {
      throw StateError('iOS Verify binary escapes the copied app: ${binary.path}');
    }
  }
  final changed = <File, String>{};
  for (final binary in binaries) {
    final commands = await checked('otool', ['-l', binary.path]);
    if (!hasPackageFrameworkRunpath(commands.stdout as String, packagePath)) continue;
    final dependencies = await checked('otool', ['-L', binary.path]);
    for (final line in (dependencies.stdout as String).split('\n').skip(1)) {
      final dependency = line.trim().split(' (').first;
      if (!dependency.startsWith('@rpath/')) continue;
      final relative = dependency.substring('@rpath/'.length);
      if (relative.split('/').contains('..')) throw StateError('Unexpected package dependency: $dependency');
      if (File('$packagePath/$relative').existsSync() && !File('${frameworkRoot.path}/$relative').existsSync()) {
        throw StateError('Package framework is missing from the isolated app: $dependency');
      }
    }
    changed[binary] = binary.parent.path.endsWith('.framework') ? binary.parent.path : binary.path;
  }
  for (final binary in changed.keys) {
    log('removing host PackageFrameworks runpath from ${binary.path}');
    await checked('install_name_tool', ['-delete_rpath', packagePath, binary.path]);
  }

  // --deep on the outer app alone does not reliably re-sign already-signed
  // loose debug dylibs or frameworks after install_name_tool changes them.
  // Sign changed nested code explicitly, then the outer app, inside out.
  final nested = changed.entries.where((e) => e.key.path != '${app.path}/Runner').map((e) => e.value).toSet();
  for (final target in nested) {
    await checked('codesign', ['--force', '--sign', '-', target]);
  }
  log('codesign --force --deep --sign - ${app.path}');
  await checked('codesign', ['--force', '--deep', '--sign', '-', app.path]);
  for (final target in [...nested, app.path]) {
    await checked('codesign', ['--verify', '--strict', target]);
  }
}

/// Match only the exact build directory supplied by the iOS driver. Preserve
/// system and @loader_path/@executable_path entries; fat binaries repeat paths.
bool hasPackageFrameworkRunpath(String loadCommands, String packagePath) => RegExp(
  r'cmd LC_RPATH\s+cmdsize \d+\s+path (.+) \(offset \d+\)',
).allMatches(loadCommands).any((m) => m.group(1) == packagePath);
