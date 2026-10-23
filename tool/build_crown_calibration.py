#!/usr/bin/env python3
"""Build the synthetic crown entrypoint with an isolated, signed app identity."""
import hashlib
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
VERIFY_ID = 'nl.michelknoop.pleya.verify'


def main():
    if sys.argv[1:] not in (['device'], ['simulator'], ['app-simulator']):
        raise SystemExit('Usage: python3 tool/build_crown_calibration.py device|simulator|app-simulator')
    simulator = sys.argv[1] != 'device'
    target = 'lib/main.dart' if sys.argv[1] == 'app-simulator' else 'tool/crown_calibration.dart'
    project = ROOT / 'ios/Runner.xcodeproj/project.pbxproj'
    info = ROOT / 'ios/Runner/Info.plist'
    for path in (project, info):
        for diff in (['git', 'diff', '--quiet', '--', str(path)],
                     ['git', 'diff', '--cached', '--quiet', '--', str(path)]):
            subprocess.run(diff, cwd=ROOT, check=True)
    subprocess.run(['bash', 'scripts/check_flutter_version.sh'], cwd=ROOT, check=True)
    subprocess.run(['bash', 'scripts/prune_old_builds.sh'], cwd=ROOT, check=True)
    source_files = sorted(str(p.relative_to(ROOT)) for p in (ROOT / 'lib/widgets/scroll_crown').glob('*.dart'))
    source_files += ['tool/crown_calibration.dart', 'tool/crown_calibration_model.dart']
    digest = hashlib.sha256()
    for name in source_files:
        digest.update(name.encode())
        digest.update((ROOT / name).read_bytes())
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    original_project, original_info = project.read_bytes(), info.read_bytes()
    source = original_project.decode()
    id_setting = 'PRODUCT_BUNDLE_IDENTIFIER = nl.michelknoop.pleya;'
    entitlement_setting = 'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'
    # Assert the three Runner configurations, never apply an ID override to dependencies.
    assert source.count(id_setting) == 3, 'Unexpected Runner bundle settings; inspect before building'
    assert source.count(entitlement_setting) == 3, 'Unexpected Runner entitlement settings'
    with tempfile.TemporaryDirectory(prefix='pleya-crown-native-', dir='/tmp') as temporary:
        tmp = Path(temporary)
        entitlements = tmp / 'Verify.entitlements'
        entitlements.write_bytes(plistlib.dumps({}))
        config = tmp / 'Architecture.xcconfig'
        config.write_text('ARCHS = arm64\nONLY_ACTIVE_ARCH = YES\n')
        env = dict(os.environ)
        env['XCODE_XCCONFIG_FILE'] = str(config)
        env['PATH'] = str(ROOT / 'scripts/xattr-fast') + os.pathsep + env['PATH']
        isolated = source.replace(id_setting, f'PRODUCT_BUNDLE_IDENTIFIER = {VERIFY_ID};')
        isolated = isolated.replace(entitlement_setting, f'CODE_SIGN_ENTITLEMENTS = {entitlements};')
        metadata = plistlib.loads(original_info)
        metadata['CFBundleDisplayName'] = 'Pleya kroonmeting'
        try:
            project.write_text(isolated)
            info.write_bytes(plistlib.dumps(metadata))
            manifest = ROOT / 'ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift'
            if manifest.exists():
                subprocess.run(['bash', 'scripts/fix_ios_spm.sh'], cwd=ROOT, env=env, check=True)
            subprocess.run(['flutter', 'build', 'ios', '--debug' if simulator else '--profile',
                            *(['--simulator'] if simulator else []), '--no-pub',
                            '--target', target, '--dart-define=PLEYA_VERIFY=true',
                            f'--dart-define=GIT_COMMIT={commit}',
                            f'--dart-define=CALIBRATION_SOURCE_SHA256={digest.hexdigest()}'],
                           cwd=ROOT, env=env, check=True)
        finally:
            project.write_bytes(original_project)
            info.write_bytes(original_info)
    app = ROOT / 'build/ios' / ('iphonesimulator' if simulator else 'iphoneos') / 'Runner.app'
    assert plistlib.loads((app / 'Info.plist').read_bytes())['CFBundleIdentifier'] == VERIFY_ID
    for framework_info in app.glob('Frameworks/*.framework/Info.plist'):
        assert plistlib.loads(framework_info.read_bytes()).get('CFBundleIdentifier') != VERIFY_ID, framework_info
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    print(f'Isolated crown app: {app}\nCalibration source SHA256: {digest.hexdigest()}')


if __name__ == '__main__':
    main()
