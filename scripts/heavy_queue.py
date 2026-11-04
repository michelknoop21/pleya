#!/usr/bin/env python3
"""One local, cooperative FIFO for heavy Pleya work. No service or PID signalling."""
import argparse
from contextlib import contextmanager
import errno
import fcntl
import hashlib
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import time
import uuid

CONTEXT = 'PLEYA_HEAVY_QUEUE_FDS'
ADMISSION = 'PLEYA_HEAVY_QUEUE_ADMISSION'
# Exported by Xcode to script phases; xcode_appletv.sh cannot run without them.
BUILD_SCRIPT_ENV = ('BUILT_PRODUCTS_DIR', 'TARGET_BUILD_DIR')


class QueueError(Exception):
    pass


def lock(fd):
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return True
    except OSError as error:
        if error.errno not in (errno.EACCES, errno.EAGAIN):
            raise
        return False


from pleya_heavy_process import TaskProcess


class Queue(TaskProcess):
    def __init__(self):
        # /tmp is shared across terminals, unlike per-session TMPDIR.
        self.admission = None
        self.path = Path(os.environ.get('PLEYA_HEAVY_QUEUE_DIR',
                                      f'/tmp/pleya-heavy-{os.getuid()}'))
        try:
            self.path.mkdir(mode=0o700)
        except FileExistsError:
            pass
        info = self.path.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise QueueError('queue directory must be a private directory owned by this user')
        self.directory = os.open(self.path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        self.control = self.open('control.lock')
        self.slot = self.open('slot.lock')

    def open(self, name, exclusive=False, create=True):
        flags = os.O_RDWR | os.O_NOFOLLOW
        if create:
            flags |= os.O_CREAT
        if exclusive:
            flags |= os.O_EXCL
        fd = os.open(name, flags, 0o600, dir_fd=self.directory)
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077 or info.st_nlink != 1:
            os.close(fd)
            raise QueueError('unsafe queue file: ' + name)
        return fd

    @contextmanager
    def transaction(self):
        deadline = time.monotonic() + 5
        while not lock(self.control):
            if time.monotonic() >= deadline:
                raise QueueError('queue metadata busy for 5s; not unlocking another process')
            time.sleep(0.05)
        try:
            yield
        finally:
            fcntl.flock(self.control, fcntl.LOCK_UN)

    def records(self):
        records = []
        for name in sorted(os.listdir(self.directory)):
            if not (len(name) == 60 and name[:20].isdigit() and name[20] == '-'
                    and all(char in '0123456789abcdef' for char in name[21:53]) and name.endswith('.ticket')):
                continue
            fd = self.open(name)
            try:
                if lock(fd):
                    # Only an unheld lease is stale. Never trust or signal a stored PID.
                    os.unlink(name, dir_fd=self.directory)
                    continue
                os.lseek(fd, 0, os.SEEK_SET)
                record = json.loads(os.read(fd, 16384))
                record['id'] = name[:-7]
                records.append(record)
            except (ValueError, KeyError) as error:
                raise QueueError('locked ticket has invalid metadata; refusing recovery: ' + name) from error
            finally:
                os.close(fd)
        return records

    @staticmethod
    def write(fd, record):
        data = json.dumps(record).encode()
        os.lseek(fd, 0, os.SEEK_SET)
        os.write(fd, data)
        os.ftruncate(fd, len(data))

    @staticmethod
    def script_phase(row):
        # The one supported detached caller: a build script phase started by a tool inside
        # this task, in its own session and without descriptors. The token reaches descendants
        # only through the environment; the ticket name does not qualify, status prints it.
        # A daemon without the build settings stays refused, even with a valid token.
        token = os.environ.get(ADMISSION, '').encode()
        return (all(os.environ.get(name) for name in BUILD_SCRIPT_ENV)
                and row.get('admission') == hashlib.sha256(token).hexdigest())

    def group_context(self, name):
        # A live private ticket plus this task's session group can replace lost FDs.
        # Stored PIDs alone never establish ownership.
        with self.transaction():
            fd = self.open(name, create=False)
            try:
                if lock(fd):
                    raise ValueError('ticket lease is not held')
                if lock(self.slot):
                    fcntl.flock(self.slot, fcntl.LOCK_UN)
                    raise ValueError('slot lease is not held')
                row = json.loads(os.read(fd, 16384))
                if row.get('state') != 'active':
                    raise ValueError('ticket is not active')
                if row.get('supervisor_pid') == os.getpgrp():
                    return None, None, name
                if self.script_phase(row):
                    return self.slot, None, name
                raise ValueError('caller is outside the active task group')
            finally:
                os.close(fd)

    @staticmethod
    def ticket_record(fd):
        return json.loads(os.pread(fd, 16384, 0))

    def mark_ticket(self, fd, **updates):
        signals = {signal.SIGINT, signal.SIGTERM, signal.SIGHUP, signal.SIGALRM}
        old_mask = signal.pthread_sigmask(signal.SIG_BLOCK, signals)
        try:
            with self.transaction():
                row = self.ticket_record(fd)
                row.update(updates)
                self.write(fd, row)
        finally:
            signal.pthread_sigmask(signal.SIG_SETMASK, old_mask)

    def new_ticket(self, label, state, parent=None):
        with self.transaction():
            rows = self.records()
            # Same transaction as promotion: a nested ticket exists before its parent can go.
            if parent and not any(row['id'] == parent[:-7] and row.get('state') == 'active' for row in rows):
                raise QueueError('lost inherited queue lease; refusing work outside its active task group')
            if parent:
                # Reaping unlinks the file; cancel and deadline marks stay readable through this FD.
                self.parent_ticket = self.open(parent, create=False)
            sequence = max((int(row['id'][:20]) for row in rows), default=0) + 1
            name = f'{sequence:020d}-{uuid.uuid4().hex}.ticket'
            fd = self.open(name, exclusive=True)
            if not lock(fd):
                raise QueueError('new ticket unexpectedly locked')
            self.admission = uuid.uuid4().hex
            self.write(fd, dict(pid=os.getpid(), label=label, cwd=os.getcwd(), state=state,
                                parent=parent, queued_at=time.time(),
                                admission=hashlib.sha256(self.admission.encode()).hexdigest()))
            return fd, name

    def inherited(self):
        context = os.environ.get(CONTEXT)
        if context is None:
            return None
        try:
            slot_text, ticket_text, name = context.split(':')
            if '/' in name or not name.endswith('.ticket'):
                raise ValueError('invalid ticket name')
            slot_fd, ticket_fd = int(slot_text), int(ticket_text)
            for fd, filename in [(slot_fd, 'slot.lock'), (ticket_fd, name)]:
                actual = os.fstat(fd)
                expected = os.stat(filename, dir_fd=self.directory, follow_symlinks=False)
                if (actual.st_dev, actual.st_ino) != (expected.st_dev, expected.st_ino) or not lock(fd):
                    raise ValueError('inherited lease does not match queue')
            return slot_fd, ticket_fd, name
        except (ValueError, OSError) as error:
            try:
                if '/' not in name and name.endswith('.ticket'):
                    return self.group_context(name)
            except (ValueError, OSError, UnboundLocalError):
                pass
            raise QueueError('lost inherited queue lease; refusing work outside its active task group') from error

    def execute(self, command, slot, ticket, name):
        if slot is not None:
            os.set_inheritable(slot, True)
            os.set_inheritable(ticket, True)
            os.environ[CONTEXT] = f'{slot}:{ticket}:{name}'
            if self.admission:
                os.environ[ADMISSION] = self.admission
        # Nested commands retain the existing lease; the supervisor owns the task group.
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(sig, signal.SIG_DFL)
        try:
            os.execvp(command[0], command)
        except FileNotFoundError:
            print('heavy-queue: executable not found: ' + command[0], file=sys.stderr)
            raise SystemExit(127)
        except PermissionError:
            raise SystemExit(126)




    def run(self, args):
        command = args.command
        if command and command[0] == '--':
            command = command[1:]
        if not command:
            raise QueueError('run needs a command after --')
        inherited = self.inherited()
        if inherited:
            if args.run_timeout:
                raise QueueError('a timed entrypoint must run directly, without an outer queue wrapper')
            slot, ticket, name = inherited
            if slot is None or (ticket is not None
                                and self.ticket_record(ticket).get('supervisor_pid') == os.getpgrp()):
                self.execute(command, *inherited)
            # A standard PTY changed group but retained the authenticated lease.
            # Its own guardian keeps that lease alive even if its parent crashes.
            # A script phase has no slot descriptor: its live active ticket blocks
            # promotion and its supervisors adopt the slot once the outer build ends.
            if ticket is not None:
                os.close(self.slot)
                self.slot = slot
            nested, child_name = self.new_ticket(args.label or Path(command[0]).name, 'active', parent=name)
            self.supervise(command, nested, child_name, None, args.kill_after)
        inspection = subprocess.run(['/usr/bin/pgrep', '-g', str(os.getpgrp())],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=5)
        if inspection.returncode not in (0, 1):
            raise QueueError('own process-group inspection is unavailable; no work started')
        label = args.label or Path(command[0]).name
        if len(label) > 100 or any(ord(char) < 32 for char in label):
            raise QueueError('label must be at most 100 characters without control characters')
        ticket = None
        try:
            ticket, name = self.new_ticket(label, 'waiting')
            record = self.ticket_record(ticket)
            print(f'heavy-queue: queued {name[:-7]} {label}', file=sys.stderr, flush=True)
            deadline = time.monotonic() + args.wait_timeout
            while True:
                with self.transaction():
                    records = self.records()
                    own = next(row for row in records if row['id'] == name[:-7])
                    if own.get('cancelled'):
                        raise SystemExit(130)
                    # A nested ticket can sort after this one, and the slot alone does not cover it.
                    if (records[0]['id'] == own['id'] and not any(row.get('state') == 'active' for row in records)
                            and lock(self.slot)):
                        record.update(state='active', started_at=time.time())
                        self.write(ticket, record)
                        break
                if time.monotonic() >= deadline:
                    print('heavy-queue: wait timed out; active work is untouched', file=sys.stderr)
                    raise SystemExit(124)
                time.sleep(0.2)
            print(f'heavy-queue: active {name[:-7]} {label}', file=sys.stderr, flush=True)
            self.supervise(command, ticket, name, args.run_timeout, args.kill_after)
        finally:
            if ticket is not None:
                os.close(ticket)
            # A subsequent transaction reaps the now-unlocked ticket, including after SIGKILL.

    def status(self, as_json):
        with self.transaction():
            records = self.records()
        result = {state: [row for row in records if row['state'] == state]
                  for state in ('active', 'waiting')}
        if as_json:
            print(json.dumps(result))
        else:
            print('Heavy Pleya queue: ' + str(self.path))
            for state in ('active', 'waiting'):
                for row in result[state]:
                    print(f"{state:7} {row['id']} pid={row['pid']} {row['label']} {row['cwd']}")
            if not records:
                print('idle')

    def cancel(self, identity):
        if len(identity) != 53 or not identity[:20].isdigit() or identity[20] != '-' or any(
                char not in '0123456789abcdef' for char in identity[21:]):
            raise QueueError('cancel needs the waiting ticket ID from status')
        with self.transaction():
            rows = self.records()
            row = next((row for row in rows if row['id'] == identity), None)
            if row is None or row['state'] != 'waiting':
                raise QueueError('not a waiting ticket; active work is never cancelled here')
            fd = self.open(identity + '.ticket')
            try:
                row['cancelled'] = True
                self.write(fd, row)
            finally:
                os.close(fd)


def duration(value):
    suffix = value[-1:]
    multiplier = {'s': 1, 'm': 60, 'h': 3600, 'd': 86400}.get(suffix, 1)
    try:
        seconds = float(value[:-1] if suffix in 'smhd' else value) * multiplier
        if not 0 <= seconds < float('inf'):
            raise ValueError()
        return seconds
    except ValueError:
        raise argparse.ArgumentTypeError('use finite seconds or a duration such as 30m') from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest='action', required=True)
    run = subs.add_parser('run')
    run.add_argument('--label')
    run.add_argument('--wait-timeout', type=duration, default=7200)
    run.add_argument('--run-timeout', type=duration)
    run.add_argument('--kill-after', type=duration, default=15)
    run.add_argument('command', nargs=argparse.REMAINDER)
    status = subs.add_parser('status')
    status.add_argument('--json', action='store_true')
    cancel = subs.add_parser('cancel')
    cancel.add_argument('id')
    subs.add_parser('owns')
    subs.add_parser('scope')
    args = parser.parse_args()
    if args.action == 'run' and args.kill_after == 0:
        parser.error('kill-after must be positive')
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, lambda number, frame: sys.exit(128 + number))
    try:
        queue = Queue()
        if args.action == 'run':
            queue.run(args)
        elif args.action == 'status':
            queue.status(args.json)
        elif args.action == 'cancel':
            queue.cancel(args.id)
        else:
            inherited = queue.inherited()
            if not inherited:
                raise QueueError('no inherited queue lease')
            if inherited[0] is not None and inherited[1] is None:
                if args.action == 'scope':
                    return 10
                raise QueueError('a detached script phase must enter through run first')
            if args.action == 'scope' and inherited[0] is not None:
                return 0 if queue.ticket_record(inherited[1]).get('supervisor_pid') == os.getpgrp() else 10
    except (QueueError, OSError, subprocess.TimeoutExpired) as error:
        print('heavy-queue: ' + str(error), file=sys.stderr)
        return 75
    return 0


if __name__ == '__main__':
    sys.exit(main())
