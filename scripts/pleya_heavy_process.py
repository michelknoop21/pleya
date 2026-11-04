"""Per-task process supervision shared by the queue launcher."""
import fcntl
import json
import os
import signal
import select
import subprocess
import sys
import threading
import time


class TaskProcess:
    @staticmethod
    def finish_like(status):
        if os.WIFSIGNALED(status):
            number = os.WTERMSIG(status)
            if number != signal.SIGKILL:
                signal.signal(number, signal.SIG_DFL)
            os.kill(os.getpid(), number)
        os._exit(os.WEXITSTATUS(status))

    @staticmethod
    def wait_for_group(group):
        # The guardian remains this group's leader, so its ID cannot be reused.
        # A tool may close inherited descriptors; the guardian still owns the lease.
        while True:
            probe = subprocess.Popen(['/usr/bin/pgrep', '-g', str(group)],
                                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            try:
                output, _ = probe.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                probe.kill()
                probe.communicate()
                raise
            if probe.returncode not in (0, 1):
                raise RuntimeError('cannot inspect own task group; keeping its lease')
            members = {int(value) for value in output.split()}
            if not members - {group, probe.pid}:
                return
            time.sleep(0.2)

    def adopt_slot(self, nested):
        # A script phase starts without a kernel lease: wait for the outer release so a
        # waiter on older code cannot slip past. A retained descriptor returns at once.
        if nested:
            threading.Thread(target=fcntl.flock, args=(self.slot, fcntl.LOCK_EX), daemon=True).start()

    def supervise(self, command, ticket, name, run_timeout, kill_after):
        signals = {signal.SIGINT, signal.SIGTERM, signal.SIGHUP}
        old_mask = signal.pthread_sigmask(signal.SIG_BLOCK, signals | {signal.SIGALRM})
        relay_read, relay_write = os.pipe()
        os.set_blocking(relay_write, False)
        guardian = os.fork()
        if guardian == 0:
            os.close(relay_write)
            os.setsid()
            group = os.getpid()
            self.mark_ticket(ticket, supervisor_pid=group)
            record = self.ticket_record(ticket)
            parent = record.get('parent')
            inherited_deadline = [None]

            def forward(number, frame):
                self.mark_ticket(ticket, cancel_signal=number)
                signal.signal(number, signal.SIG_IGN)
                try:
                    os.killpg(group, number)
                finally:
                    signal.signal(number, forward)

            for number in signals:
                signal.signal(number, forward)
            worker = os.fork()
            if worker == 0:
                for number in signals:
                    signal.signal(number, signal.SIG_DFL)
                signal.pthread_sigmask(signal.SIG_SETMASK, old_mask)
                self.execute(command, self.slot, ticket, name)
            def read_signals():
                channel = relay_read
                observed = set()
                while channel is not None or parent:
                    ready = select.select([] if channel is None else [channel], [], [], .1 if parent else None)[0]
                    if ready:
                        data = os.read(channel, 32)
                        if not data:
                            os.close(channel)
                            channel = None
                        for number in data:
                            os.kill(os.getpid(), number)
                    ancestor = parent
                    try:
                        while ancestor:
                            if ancestor == parent:
                                row = self.ticket_record(self.parent_ticket)
                            else:
                                fd = self.open(ancestor, create=False)
                                try:
                                    row = self.ticket_record(fd)
                                finally:
                                    os.close(fd)
                            if row.get('timed_out') and 'timeout' not in observed:
                                observed.add('timeout')
                                inherited_deadline[0] = row.get('kill_at', time.time() + kill_after)
                                os.kill(os.getpid(), signal.SIGALRM)
                            number = row.get('cancel_signal')
                            if number and not row.get('timed_out') and (ancestor, number) not in observed:
                                observed.add((ancestor, number))
                                os.kill(os.getpid(), number)
                            ancestor = row.get('parent')
                    except (OSError, ValueError, KeyError):
                        # A concurrent metadata write is retried; never free a live lease.
                        pass

            timed_out = False

            def expire(number, frame):
                nonlocal timed_out
                if timed_out:
                    os.killpg(group, signal.SIGKILL)
                timed_out = True
                deadline = inherited_deadline[0] or time.time() + kill_after
                self.mark_ticket(ticket, timed_out=True, kill_at=deadline)
                signal.setitimer(signal.ITIMER_REAL, max(.001, deadline - time.time()))
                try:
                    print('heavy-queue: runtime timeout; terminating own task group', file=sys.stderr, flush=True)
                except OSError:
                    pass
                forward(signal.SIGTERM, None)

            signal.signal(signal.SIGALRM, expire)
            if run_timeout:
                signal.setitimer(signal.ITIMER_REAL, run_timeout)
            self.adopt_slot(parent)
            threading.Thread(target=read_signals, daemon=True).start()
            signal.pthread_sigmask(signal.SIG_SETMASK, old_mask)
            _, status = os.waitpid(worker, 0)
            while True:
                try:
                    self.wait_for_group(group)
                    break
                except (RuntimeError, subprocess.TimeoutExpired) as error:
                    # Fail closed if group inspection fails. Waiters have a bounded timeout.
                    print('heavy-queue: ' + str(error), file=sys.stderr, flush=True)
                    time.sleep(1)
            signal.setitimer(signal.ITIMER_REAL, 0)
            if timed_out:
                os._exit(124)
            self.finish_like(status)

        os.close(relay_read)
        self.adopt_slot(self.ticket_record(ticket).get('parent'))

        def relay(number, frame):
            # A pipe cannot target a reused PID, even after the guardian has exited.
            try:
                os.write(relay_write, bytes([number]))
            except (BrokenPipeError, BlockingIOError):
                pass

        for number in signals:
            signal.signal(number, relay)
        signal.pthread_sigmask(signal.SIG_SETMASK, old_mask)
        _, status = os.waitpid(guardian, 0)
        # If the guardian itself was killed, the parent still holds the lease
        # until the task group ends. There is deliberately no force-unlock.
        if os.WIFSIGNALED(status):
            while True:
                try:
                    self.wait_for_group(guardian)
                    break
                except (RuntimeError, subprocess.TimeoutExpired):
                    time.sleep(1)
        if self.ticket_record(ticket).get('timed_out'):
            os._exit(124)
        self.finish_like(status)
