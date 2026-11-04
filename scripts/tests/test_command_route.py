#!/usr/bin/env python3
"""Routing probes use tiny local repositories, never installed launchers."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[1] / 'pleya_command_route.py'
spec = importlib.util.spec_from_file_location('pleya_route', MODULE)
route = importlib.util.module_from_spec(spec)
spec.loader.exec_module(route)


class RoutingTest(unittest.TestCase):
    def test_heavy_subcommands_and_light_exceptions(self):
        cases = [
            ('flutter', ['test', 'test/foo.dart'], True),
            ('flutter', ['--device-id', 'phone', 'build', 'ios'], True),
            ('flutter', ['--version'], False),
            ('flutter', ['doctor'], False),
            ('dart', ['format', 'lib'], False),
            ('dart', ['run', '--enable-asserts', 'build_runner', 'build'], True),
            ('dart', ['run', 'slang'], True),
            ('dart', ['run', 'pleya_verify/runner/bin/verify.dart'], False),
            ('dart', ['test'], True),
            ('xcodebuild', [], True),
            ('xcodebuild', ['-workspace', 'Runner.xcworkspace', 'archive'], True),
            ('xcodebuild', ['-showBuildSettings'], False),
            ('xcrun', ['--sdk', 'iphoneos', 'xcodebuild', 'build'], True),
            ('xcrun', ['--sdk', 'iphoneos', '--find', 'xcodebuild'], False),
            ('xcrun', ['-f', 'xcodebuild'], False),
            ('xcrun', ['simctl', 'list'], False),
            ('fastlane', ['ios_beta'], True),
            ('fastlane', ['tvos_archive'], True),
            ('fastlane', ['lanes'], False),
            ('fastlane', ['notes_show', 'build:42'], False),
        ]
        for kind, arguments, expected in cases:
            with self.subTest(kind=kind, arguments=arguments):
                self.assertEqual(route.heavy(kind, arguments), expected)

    def test_common_repository_identity_covers_worktree_not_other_project(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo = root / 'project'
            other = root / 'other'
            tree = root / 'worktree'
            for path in [repo, other]:
                subprocess.run(['git', 'init', '-q', str(path)], check=True)
            (repo / 'source').write_text('fixture\n')
            subprocess.run(['git', '-C', str(repo), 'add', 'source'], check=True)
            subprocess.run(['git', '-C', str(repo), '-c', 'user.name=Michel Knoop',
                            '-c', 'user.email=info@michelknoop.nl', 'commit', '-qm', 'queue fixture'], check=True)
            subprocess.run(['git', '-C', str(repo), 'worktree', 'add', '-q', '--detach', str(tree)], check=True)
            config = root / 'roots.json'
            config.write_text(json.dumps({'git_common_dirs': [str((repo / '.git').resolve())]}))
            self.assertTrue(route.is_pleya(repo, config))
            self.assertTrue(route.is_pleya(tree, config))
            self.assertFalse(route.is_pleya(other, config))
            env = dict(os.environ, PLEYA_HEAVY_ROOTS_FILE=str(config))
            for cwd, expected in [(repo, 10), (tree, 10), (other, 0)]:
                result = subprocess.run(['python3', str(MODULE), 'flutter', 'build', 'bundle'],
                                        cwd=cwd, env=env, capture_output=True, timeout=4)
                self.assertEqual(result.returncode, expected, result.stderr)
            stale = dict(env, PLEYA_HEAVY_QUEUE_FDS='source-identity-probe')
            result = subprocess.run(['python3', str(MODULE), 'flutter', 'build', 'bundle',
                                     '--dart-define=GIT_COMMIT=' + '0' * 40],
                                    cwd=tree, env=stale, capture_output=True, timeout=4)
            self.assertEqual(result.returncode, 75)
            self.assertIn(b'source HEAD changed', result.stderr)


if __name__ == '__main__':
    unittest.main()
