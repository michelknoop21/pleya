#!/usr/bin/env python3
"""Probe whether a standard tool invocation needs the local Pleya queue."""
import json
import os
from pathlib import Path
import subprocess
import sys


def command_words(arguments):
    value_options = {'-d', '--device-id', '--local-engine', '--local-engine-host',
                     '--local-engine-src-path', '--packages', '--sdk', '-sdk',
                     '--toolchain', '-toolchain'}
    result = []
    skip = False
    for value in arguments:
        if skip:
            skip = False
        elif value in value_options:
            skip = True
        elif value == '--':
            break
        elif not value.startswith('-'):
            result.append(value)
    return result


def heavy(kind, arguments):
    words = command_words(arguments)
    if (not words and kind != 'xcodebuild') or any(value in arguments for value in ('--help', '-h', '--version')):
        return False
    first = words[0] if words else ''
    if kind == 'flutter':
        return first in {'build', 'test', 'analyze', 'run', 'drive', 'pub', 'packages'}
    if kind == 'dart':
        return first in {'test', 'analyze', 'compile'} or (
            first == 'run' and len(words) > 1 and words[1].split(':')[0] in
            {'build_runner', 'slang', 'dart_code_linter'})
    if kind == 'fastlane':
        return first not in {'lanes', 'actions', 'action', 'docs', 'help', 'env',
                             'notes', 'notes_show', 'whats_new', 'whats_new_show',
                             'attach_builds', 'add_testers', 'external'}
    if kind == 'xcrun':
        if '--find' in arguments or '-find' in arguments or '-f' in arguments or first != 'xcodebuild':
            return False
        arguments = arguments[arguments.index('xcodebuild') + 1:]
    if kind in {'xcodebuild', 'xcrun'}:
        return not any(value in arguments for value in
                       ('-version', '-list', '-showsdks', '-showBuildSettings', '-showdestinations', '-help'))
    return False


def git_environment():
    environment = dict(os.environ)
    for name in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_PREFIX'):
        environment.pop(name, None)
    return environment


def is_pleya(directory, roots_file):
    data = json.loads(Path(roots_file).read_text())
    environment = git_environment()
    result = subprocess.run(['git', '-C', str(directory), 'rev-parse', '--git-common-dir'],
                            capture_output=True, text=True, env=environment, timeout=3)
    if result.returncode:
        return False
    common = Path(result.stdout.strip())
    if not common.is_absolute():
        common = Path(directory) / common
    return str(common.resolve()) in data['git_common_dirs']


def main():
    if len(sys.argv) < 2:
        return 75
    if not heavy(sys.argv[1], sys.argv[2:]):
        return 0
    roots_file = os.environ.get('PLEYA_HEAVY_ROOTS_FILE',
                                str(Path(__file__).with_name('pleya-heavy-roots.json')))
    try:
        if not is_pleya(Path.cwd(), roots_file):
            return 0
        if sys.argv[1] == 'flutter' and os.environ.get('PLEYA_HEAVY_QUEUE_FDS'):
            expected = [value.split('=', 2)[-1] for value in sys.argv[2:]
                        if value.startswith('--dart-define=GIT_COMMIT=')]
            if expected:
                result = subprocess.run(['git', 'rev-parse', 'HEAD'], capture_output=True,
                                        text=True, env=git_environment(), timeout=3)
                head, commit = result.stdout.strip(), expected[-1]
                # Verify geeft de volledige sha mee, de release-lanes een korte.
                if result.returncode or len(commit) < 7 or not head.startswith(commit):
                    print('pleya-routing: source HEAD changed while waiting; build not started', file=sys.stderr)
                    return 75
        return 10
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired):
        print('pleya-routing: cannot establish repository scope; command not started', file=sys.stderr)
        return 75


if __name__ == '__main__':
    sys.exit(main())
