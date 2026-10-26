#!/usr/bin/env python3
"""Guard pinned plugin provenance, reviewed local changes and native packaging."""
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SpmPluginsTest(unittest.TestCase):
    def test_vendored_implementation_matches_pins(self):
        origins = json.loads((ROOT / 'third_party/upstream.json').read_text())
        for name, origin in origins.items():
            if 'declaration' in origin:
                self.assertIn(origin['declaration'], (ROOT / 'pubspec.yaml').read_text())
            base = ROOT / 'third_party' / name
            for relative, digest in {**origin['files'], **origin.get('local_files', {})}.items():
                with self.subTest(package=name, file=relative):
                    path = base / relative
                    if '/Classes/' in relative:
                        platform, filename = relative.split('/Classes/', 1)
                        path = base / platform / name / 'Sources' / name / filename
                    data = path.read_bytes()
                    if relative.endswith('.podspec') and name != 'cupertino_http':
                        data = data.replace(
                            f'{name}/Sources/{name}/**/*'.encode(), b'Classes/**/*'
                        )
                    self.assertEqual(hashlib.sha256(data).hexdigest(), digest)

    def test_all_apple_plugins_support_spm(self):
        # A removed manifest must fail even before Flutter generates plugin metadata.
        packages = {
            'universal_gamepad': ['ios', 'macos'],
            'os_media_controls': ['ios', 'macos'],
            'cupertino_http': ['darwin'],
            'screen_retriever_macos': ['macos'],
            'auto_updater_macos': ['macos'],
            'pleya_aware': ['ios'],
        }
        for name, platforms in packages.items():
            parent = 'plugins' if name == 'pleya_aware' else 'third_party'
            for platform in platforms:
                with self.subTest(package=name, platform=platform):
                    package = ROOT / parent / name / platform / name
                    self.assertTrue((package / 'Package.swift').is_file())
                    self.assertTrue(any((package / 'Sources' / name).iterdir()))
        pubspec = (ROOT / 'pubspec.yaml').read_text()
        for name in packages.keys() - {'pleya_aware'}:
            self.assertIn(f'  {name}:\n    path: third_party/{name}', pubspec)


if __name__ == '__main__':
    unittest.main()
