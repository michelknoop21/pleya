#!/usr/bin/env python3
"""Revalidate a precomputed Verify commit identity after queue admission."""
import os
import subprocess
import sys


def main():
    command = sys.argv[1:]
    expected = [value.split('=', 2)[-1] for value in command if value.startswith('--dart-define=GIT_COMMIT=')]
    if expected:
        head = subprocess.run(['git', 'rev-parse', 'HEAD'], capture_output=True, text=True, timeout=5)
        if head.returncode or head.stdout.strip() != expected[-1]:
            print('Verify build: source HEAD changed while waiting; restart against the current source', file=sys.stderr)
            return 75
    os.execvp(command[0], command)


if __name__ == '__main__':
    sys.exit(main())
