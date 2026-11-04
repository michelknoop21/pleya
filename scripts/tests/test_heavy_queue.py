#!/usr/bin/env python3
"""Small subprocess fixtures; never starts Flutter, Xcode or a simulator."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

QUEUE = Path(__file__).resolve().parents[1] / 'heavy_queue.py'
OLD_QUEUE = os.environ.get('PLEYA_HEAVY_OLD_QUEUE')
ADMISSION = 'PLEYA_HEAVY_QUEUE_ADMISSION'
# xcode_appletv.sh depends on these two settings; a plain daemon does not have them.
XCODE_ENV = {'BUILT_PRODUCTS_DIR': '/fixture/products', 'TARGET_BUILD_DIR': '/fixture/target'}
HARD_TIMEOUT = 30

HOLD = '''
import sys, time
from pathlib import Path
root, name, code = Path(sys.argv[1]), sys.argv[2], int(sys.argv[3])
(root / (name + '.start')).write_text(str(time.time()))
deadline = time.monotonic() + 12
while not (root / (name + '.release')).exists() and time.monotonic() < deadline:
    time.sleep(.02)
(root / (name + '.end')).write_text(str(time.time()))
raise SystemExit(code)
'''

# A build tool inside the task starts a script phase: new session, no inherited descriptors.
PHASE = '''
import json, os, subprocess, sys, time
from pathlib import Path
spec = json.loads(sys.argv[1])
deadline = time.monotonic() + 12
while spec.get('gate') and not Path(spec['gate']).exists() and time.monotonic() < deadline:
    time.sleep(.02)
options = dict(env=dict(os.environ, **spec['env']), start_new_session=True, close_fds=True,
               cwd=spec.get('cwd'))
if spec.get('background'):
    subprocess.Popen(spec['command'], **options)
    code = 0
else:
    code = subprocess.run(spec['command'], **options).returncode
if spec.get('then'):
    os.execv(sys.executable, [sys.executable, *spec['then']])
raise SystemExit(code)
'''

# Keeps running after SIGTERM for `linger` seconds and logs a heartbeat, so the moment of the
# real end is observable. A large linger is a TERM-ignoring leaf that only SIGKILL stops.
SLOW_TERM = '''
import signal, sys, time
from pathlib import Path
root, name, linger = Path(sys.argv[1]), sys.argv[2], float(sys.argv[3])
stopping = []
signal.signal(signal.SIGTERM, lambda *_: stopping.append(time.monotonic()))
(root / (name + '.start')).write_text(str(time.time()))
beats = open(root / (name + '.beats'), 'a', buffering=1)
deadline = time.monotonic() + 12
while (time.monotonic() < deadline and not (root / (name + '.release')).exists()
       and not (stopping and time.monotonic() > stopping[0] + linger)):
    beats.write(str(time.time()) + chr(10))
    time.sleep(.02)
(root / (name + '.end')).write_text(str(time.time()))
'''

LEAVE_CHILD = '''
import subprocess, sys, time
from pathlib import Path
subprocess.Popen(sys.argv[2:], close_fds=True)
deadline = time.monotonic() + 4
while not Path(sys.argv[1]).exists() and time.monotonic() < deadline:
    time.sleep(.02)
'''


class HeavyQueueTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.env = dict(os.environ, PLEYA_HEAVY_QUEUE_DIR=str(self.root / 'queue'))
        self.env.pop('PLEYA_HEAVY_QUEUE_FDS', None)
        self.env.pop(ADMISSION, None)
        self.children = []
        self.holds = set()
        for filename, source in [('hold.py', HOLD), ('phase.py', PHASE), ('leave.py', LEAVE_CHILD),
                                 ('slow_term.py', SLOW_TERM)]:
            (self.root / filename).write_text(source)

        def expired(number, frame):
            raise TimeoutError('hard test timeout')
        signal.signal(signal.SIGALRM, expired)
        signal.alarm(HARD_TIMEOUT)
        self.addCleanup(signal.alarm, 0)

    def tearDown(self):
        for name in self.holds:
            (self.root / (name + '.release')).touch()
        for child in self.children:
            if child.poll() is None:
                child.terminate()
            child.communicate(timeout=4)
        self.temp.cleanup()

    def start(self, label, code, *options, cwd=None):
        child = subprocess.Popen(
            [sys.executable, str(QUEUE), 'run', '--label', label, *options,
             '--', sys.executable, '-c', code],
            env=self.env, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        self.children.append(child)
        return child

    def call(self, *args):
        return subprocess.run([sys.executable, str(QUEUE), *args], env=self.env,
                              capture_output=True, text=True, timeout=4)

    def status(self):
        result = self.call('status', '--json')
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def until(self, predicate, timeout=4):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            result = predicate()
            if result:
                return result
            time.sleep(0.03)
        self.fail('fixture condition did not occur')

    def holding(self, label='active'):
        marker = self.root / (label + '.started')
        child = self.start(label, f'from pathlib import Path; import time; '
                           f'Path({str(marker)!r}).touch(); time.sleep(30)')
        self.until(marker.exists)
        return child

    def test_fifo_no_overlap_between_worktrees_and_visible_status(self):
        active = self.holding()
        log = self.root / 'order'
        queued = []
        for i in range(3):
            worktree = self.root / str(i)
            worktree.mkdir()
            code = (f'from pathlib import Path; import time; p=Path({str(log)!r}); '
                    f'f=p.open("a"); f.write("{i}:start\\n"); f.flush(); '
                    f'time.sleep(.08); f.write("{i}:end\\n"); f.close()')
            queued.append(self.start(f'job-{i}', code, cwd=worktree))
            self.until(lambda: len(self.status()['waiting']) == i + 1)
        state = self.status()
        self.assertEqual(state['active'][0]['label'], 'active')
        self.assertEqual([x['label'] for x in state['waiting']], ['job-0', 'job-1', 'job-2'])
        active.terminate()
        self.assertEqual(active.wait(timeout=3), -signal.SIGTERM)
        for child in queued:
            self.assertEqual(child.wait(timeout=4), 0)
        self.assertEqual(log.read_text().splitlines(),
                         ['0:start', '0:end', '1:start', '1:end', '2:start', '2:end'])
        self.assertEqual(self.status()['active'], [])

    def test_error_and_signal_exit_status_release_slot(self):
        child = self.start('failure', 'raise SystemExit(37)')
        self.assertEqual(child.wait(timeout=3), 37)
        for sig in [signal.SIGTERM, signal.SIGKILL]:
            marker = self.root / ('signal-' + str(sig))
            child = self.start('signal', f'from pathlib import Path; import time; '
                               f'Path({str(marker)!r}).touch(); time.sleep(.4)')
            self.until(marker.exists)
            child.send_signal(sig)
            self.assertEqual(child.wait(timeout=3), -sig)
            next_job = self.start('next', 'pass')
            self.assertEqual(next_job.wait(timeout=3), 0)

    def test_cancel_waiter_and_wait_timeout_do_not_touch_active(self):
        active = self.holding()
        never = self.root / 'must-not-run'
        waiter = self.start('cancel-me', f'from pathlib import Path; Path({str(never)!r}).touch()')
        state = self.until(lambda: self.status()['waiting'])
        self.assertEqual(self.call('cancel', state[0]['id']).returncode, 0)
        self.assertEqual(waiter.wait(timeout=3), 130)
        self.assertFalse(never.exists())
        timeout = self.start('timeout', 'pass', '--wait-timeout', '.15')
        self.assertEqual(timeout.wait(timeout=3), 124)
        self.assertIsNone(active.poll())
        self.assertNotEqual(self.call('cancel', self.status()['active'][0]['id']).returncode, 0)

    def test_waiting_signal_and_stale_records_use_locks_not_pids(self):
        active = self.holding()
        waiter = self.start('waiter', 'raise SystemExit(91)')
        self.until(lambda: self.status()['waiting'])
        waiter.terminate()
        self.assertEqual(waiter.wait(timeout=3), 143)
        stale = self.root / 'queue' / ('00000000000000000000-' + '0' * 32 + '.ticket')
        stale.write_text(json.dumps({'pid': active.pid, 'state': 'active', 'label': 'stale'}))
        stale.chmod(0o600)
        self.assertEqual(self.status()['waiting'], [])
        self.assertFalse(stale.exists())
        self.assertIsNone(active.poll())

    def test_inherited_lock_survives_parent_crash(self):
        marker = self.root / 'child'
        code = (f'import os,time; from pathlib import Path; p=os.fork(); '
                f'Path({str(marker)!r}).write_text(str(p)) if p else time.sleep(.7); '
                'os._exit(0)')
        holder = self.start('fork', code)
        self.until(marker.exists)
        next_job = self.start('after-fork', 'pass')
        time.sleep(.15)
        self.assertIsNone(next_job.poll(), 'descendant still owns the inherited lease')
        self.assertEqual(holder.wait(timeout=3), 0)
        self.assertEqual(next_job.wait(timeout=3), 0)

    def test_closed_descriptor_child_is_protected_after_wrapper_sigkill(self):
        marker = self.root / 'child-started'
        done = self.root / 'child-done'
        child_code = (f'from pathlib import Path; import time; Path({str(marker)!r}).touch(); '
                      f'time.sleep(.8); Path({str(done)!r}).touch()')
        code = (f'import subprocess,sys; child=subprocess.Popen([sys.executable,"-c",{child_code!r}], '
                'close_fds=True); child.wait()')
        holder = self.start('crash-owner', code)
        self.until(marker.exists)
        holder.kill()
        self.assertEqual(holder.wait(timeout=3), -signal.SIGKILL)
        next_job = self.start('after-crash', f'from pathlib import Path; '
                              f'assert Path({str(done)!r}).exists(), "overlap after parent crash"')
        self.assertEqual(next_job.wait(timeout=4), 0, next_job.communicate()[1])

    def test_runtime_timeout_kills_own_term_ignoring_children_and_returns_124(self):
        marker = self.root / 'timeout-child-started'
        done = self.root / 'timeout-child-survived'
        child_code = (f'import signal,time; from pathlib import Path; '
                      f'signal.signal(signal.SIGTERM, signal.SIG_IGN); Path({str(marker)!r}).touch(); '
                      f'time.sleep(10); Path({str(done)!r}).touch()')
        code = (f'import signal,subprocess,sys; signal.signal(signal.SIGTERM, signal.SIG_IGN); '
                f'subprocess.Popen([sys.executable,"-c",{child_code!r}],close_fds=True).wait()')
        before = time.monotonic()
        holder = self.start('timeout-tree', code, '--run-timeout', '.25s', '--kill-after', '.15s')
        self.until(marker.exists)
        self.assertEqual(holder.wait(timeout=4), 124, holder.communicate()[1])
        self.assertLess(time.monotonic() - before, 4)
        self.assertFalse(done.exists())
        successor = self.start('after-timeout', 'pass')
        self.assertEqual(successor.wait(timeout=3), 0)

    def test_guardian_crash_does_not_release_while_its_worker_runs(self):
        marker = self.root / 'guardian-worker-started'
        done = self.root / 'guardian-worker-done'
        code = (f'from pathlib import Path; import time; Path({str(marker)!r}).touch(); '
                f'time.sleep(.7); Path({str(done)!r}).touch()')
        holder = self.start('guardian-crash', code)
        self.until(marker.exists)
        guardian = self.status()['active'][0]['supervisor_pid']
        os.kill(guardian, signal.SIGKILL)
        next_job = self.start('after-guardian', f'from pathlib import Path; '
                              f'assert Path({str(done)!r}).exists(), "overlap after guardian crash"')
        self.assertEqual(holder.wait(timeout=4), -signal.SIGKILL)
        self.assertEqual(next_job.wait(timeout=4), 0, next_job.communicate()[1])

    def test_old_cancel_id_cannot_cancel_a_new_generation(self):
        first = self.holding('generation-one')
        old_id = self.status()['active'][0]['id']
        first.terminate()
        first.wait(timeout=3)
        active = self.holding('generation-two')
        waiting = self.start('new-waiter', 'pass')
        self.until(lambda: self.status()['waiting'])
        self.assertNotEqual(self.call('cancel', old_id).returncode, 0)
        self.assertIsNone(waiting.poll())
        active.terminate()
        active.wait(timeout=3)
        self.assertEqual(waiting.wait(timeout=4), 0)

    def test_nested_entry_reuses_slot_and_forged_context_fails_closed(self):
        nested = self.start('outer',
            f'import os; os.execv({sys.executable!r}, [{sys.executable!r}, {str(QUEUE)!r}, '
            '"run", "--label", "inner", "--", "'+sys.executable+'", "-c", "raise SystemExit(19)"])')
        self.assertEqual(nested.wait(timeout=3), 19)
        env = dict(self.env, PLEYA_HEAVY_QUEUE_FDS='999:998:missing.ticket')
        bad = subprocess.run([sys.executable, str(QUEUE), 'run', '--', 'true'],
                             env=env, capture_output=True, timeout=3)
        self.assertEqual(bad.returncode, 75)
        timed = self.start('outer-timed',
            f'import os; os.execv({sys.executable!r}, [{sys.executable!r}, {str(QUEUE)!r}, '
            '"run", "--run-timeout", ".1", "--", "true"])')
        self.assertEqual(timed.wait(timeout=3), 75)

    def test_nested_tool_with_closed_fds_reuses_own_group_but_foreign_group_cannot(self):
        command = [sys.executable, str(QUEUE), 'run', '--', sys.executable, '-c', 'raise SystemExit(21)']
        child = self.start('closed-fd-nested',
            f'import subprocess; raise SystemExit(subprocess.run({command!r},close_fds=True).returncode)')
        self.assertEqual(child.wait(timeout=4), 21, child.communicate()[1])
        active = self.holding()
        row = self.status()['active'][0]
        stolen = dict(self.env, PLEYA_HEAVY_QUEUE_FDS='999:998:' + row['id'] + '.ticket')
        result = subprocess.run(command, env=stolen, capture_output=True, timeout=3)
        self.assertEqual(result.returncode, 75)
        self.assertIsNone(active.poll())

    def detached_nested(self, inner_code, *options):
        command = [sys.executable, str(QUEUE), 'run', '--label', 'pty-child', '--',
                   sys.executable, '-c', inner_code]
        outer = ('import os,sys; child=os.fork(); '
                 f'os.setsid() if child==0 else None; '
                 f'os.execv({sys.executable!r},{command!r}) if child==0 else None; '
                 '_,status=os.waitpid(child,0); raise SystemExit(os.waitstatus_to_exitcode(status))')
        return self.start('pty-parent', outer, *options)

    def test_standard_pty_group_then_closed_fds_keeps_nested_commands_working(self):
        command = [sys.executable, str(QUEUE), 'run', '--', sys.executable, '-c', 'raise SystemExit(22)']
        inner = f'import subprocess; raise SystemExit(subprocess.run({command!r},close_fds=True).returncode)'
        child = self.detached_nested(inner)
        self.assertEqual(child.wait(timeout=4), 22, child.communicate()[1])

    def test_parent_deadline_reaches_nested_pty_group(self):
        marker = self.root / 'nested-timeout-started'
        done = self.root / 'nested-timeout-survived'
        inner = (f'import signal,time; from pathlib import Path; '
                 f'signal.signal(signal.SIGTERM,signal.SIG_IGN); Path({str(marker)!r}).touch(); '
                 f'time.sleep(10); Path({str(done)!r}).touch()')
        child = self.detached_nested(inner, '--run-timeout', '.6s', '--kill-after', '.2s')
        self.until(marker.exists)
        self.assertEqual(child.wait(timeout=4), 124, child.communicate()[1])
        self.assertFalse(done.exists())
        successor = self.start('after-nested-timeout', 'pass')
        self.assertEqual(successor.wait(timeout=3), 0)

    def test_sigterm_reaches_nested_pty_group_without_releasing_early(self):
        marker = self.root / 'nested-term-started'
        child = self.detached_nested(f'import time; from pathlib import Path; '
                                     f'Path({str(marker)!r}).touch(); time.sleep(20)')
        self.until(marker.exists)
        child.terminate()
        self.assertEqual(child.wait(timeout=4), -signal.SIGTERM, child.communicate()[1])
        successor = self.start('after-nested-term', 'pass')
        self.assertEqual(successor.wait(timeout=3), 0)

    def test_real_codegen_entrypoint_waits_and_nested_script_keeps_lease(self):
        import shutil
        scripts = self.root / 'project' / 'scripts'
        scripts.mkdir(parents=True)
        for filename in ['heavy_queue.py', 'pleya_heavy_process.py', 'heavy_queue.sh', 'codegen.sh']:
            shutil.copy2(QUEUE.parent / filename, scripts / filename)
        for filename in ['check_flutter_version.sh', 'check_hooks_installed.sh']:
            p = scripts / filename
            p.write_text('#!/bin/sh\nexit 0\n')
            p.chmod(0o755)
        tool = self.root / 'dart'
        calls = self.root / 'dart-calls'
        tool.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "' + str(calls) + '"\n')
        tool.chmod(0o755)
        env = dict(self.env, PATH=str(self.root) + os.pathsep + os.environ['PATH'])
        active = self.holding()
        child = subprocess.Popen(['bash', str(scripts / 'codegen.sh')], env=env,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.children.append(child)
        self.until(lambda: self.status()['waiting'])
        self.assertFalse(calls.exists())
        active.terminate()
        active.wait(timeout=3)
        self.assertEqual(child.wait(timeout=4), 0, child.communicate()[1])
        self.assertEqual(calls.read_text().splitlines(),
                         ['run slang', 'run build_runner build --delete-conflicting-outputs'])
        nested = scripts / 'nested.sh'
        nested.write_text('#!/bin/bash\n. "$(dirname "$0")/heavy_queue.sh"\n'
                          'pleya_queue_script "$0" bash "$@"\n'
                          'bash "$(dirname "$0")/codegen.sh" || exit $?\nexit 29\n')
        result = subprocess.run(['bash', str(nested)], env=env, capture_output=True, timeout=4)
        self.assertEqual(result.returncode, 29, result.stderr)

    def test_separate_release_routes_lane_deadline_without_running_fastlane(self):
        import shutil
        scripts = self.root / 'release-project' / 'scripts'
        scripts.mkdir(parents=True)
        entrypoint = scripts / 'testflight_separate.sh'
        shutil.copy2(QUEUE.parent / entrypoint.name, entrypoint)
        (scripts.parent / '.env').touch()
        calls = self.root / 'release-call'
        env = dict(self.env, QUEUE_TEST_CALLS=str(calls), TESTFLIGHT_LANE_TIMEOUT='.2s')
        # Source the real entrypoint with only its Python launcher stubbed.
        # The existing PATH prelude cannot accidentally select a real release tool.
        result = subprocess.run(['sh', '-c',
            'python3() { printf "%s\\n" "$*" > "$QUEUE_TEST_CALLS"; return 124; }; . "$0"',
            str(entrypoint), 'ios'], env=env, capture_output=True, text=True, timeout=3)
        self.assertEqual(result.returncode, 1)
        self.assertIn('--run-timeout .2s --kill-after 15s -- fastlane ios_beta', calls.read_text())
        self.assertIn('ios:TIMEOUT', result.stdout)

    def hold_command(self, name, code=0):
        self.holds.add(name)
        return [sys.executable, str(self.root / 'hold.py'), str(self.root), name, str(code)]

    def run_command(self, label, command, *options, queue=QUEUE):
        return [sys.executable, str(queue), 'run', '--label', label, *options, '--', *command]

    def launch(self, label, command, *options, queue=QUEUE):
        child = subprocess.Popen(self.run_command(label, command, *options, queue=queue), env=self.env,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.children.append(child)
        return child

    def phase_command(self, command, gate=None, background=False, then=None, cwd=None, env=None):
        spec = dict(command=command, gate=gate and str(gate), background=background, then=then,
                    cwd=cwd and str(cwd), env=XCODE_ENV if env is None else env)
        return [sys.executable, str(self.root / 'phase.py'), json.dumps(spec)]

    def marker(self, name, part):
        return self.root / f'{name}.{part}'

    def moment(self, name, part):
        return float(self.marker(name, part).read_text())

    def wait_started(self, name):
        self.until(self.marker(name, 'start').exists, timeout=6)

    def release(self, name):
        self.marker(name, 'release').touch()

    def row(self, label):
        return next(row for row in self.status()['active'] if row['label'] == label)

    def wait_active(self, label):
        # Queue() creates slot.lock last; status must not race the first creator of a new directory.
        self.until((self.root / 'queue' / 'slot.lock').exists)
        self.until(lambda: [r for r in self.status()['active'] if r['label'] == label])

    def wait_queued(self, label):
        self.until(lambda: [r for r in self.status()['waiting'] if r['label'] == label])

    def slot_is_held(self):
        import fcntl
        fd = os.open(self.root / 'queue' / 'slot.lock', os.O_RDWR)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return False
        except OSError:
            return True
        finally:
            os.close(fd)

    def slow_term_command(self, name, linger):
        self.holds.add(name)
        return [sys.executable, str(self.root / 'slow_term.py'), str(self.root), name, str(linger)]

    def last_beat(self, name):
        # Only meaningful once the leaf is dead, or the file merely shows the present.
        self.until(lambda: not [r for r in self.status()['active'] if r['label'] == name], timeout=6)
        return float(self.marker(name, 'beats').read_text().splitlines()[-2])

    def outer_with_queued_waiter_then_script_phase(self, nested, *options, then='outer'):
        """Ticket order outer, waiter, nested: the waiter sorts before the nested ticket."""
        gate = self.root / 'gate'
        outer = self.launch('outer', self.phase_command(
            nested, gate=gate, background=True, then=self.hold_command(then)[1:]), *options)
        self.wait_active('outer')
        waiter = self.launch('waiter', self.hold_command('waiter'))
        self.wait_queued('waiter')
        gate.touch()
        return outer, waiter

    def route_fixture(self):
        import shlex
        import shutil
        repo = self.root / 'repo'
        repo.mkdir()
        subprocess.run(['git', 'init', '-q', str(repo)], check=True, timeout=5)
        roots = self.root / 'roots.json'
        roots.write_text(json.dumps({'git_common_dirs': [str((repo / '.git').resolve())]}))
        tools = self.root / 'tools'
        tools.mkdir()
        shutil.copy2(QUEUE.parent / 'pleya_command_route.py', tools / 'route.py')
        cli = tools / 'cli'
        cli.write_text(f'#!/bin/sh\nexec {shlex.quote(sys.executable)} {shlex.quote(str(QUEUE))} "$@"\n')
        cli.chmod(0o755)
        source = (QUEUE.parent / 'pleya_command_route.sh').read_text()
        source = source.replace('/Users/michelknoop/bin/pleya-heavy-route', str(tools / 'route.py'))
        (tools / 'route.sh').write_text(source.replace('/Users/michelknoop/bin/pleya-heavy', str(cli)))
        flutter = tools / 'flutter'
        work = shlex.join(self.hold_command('nested', 23))
        flutter.write_text(f'#!/bin/bash\n. {shlex.quote(str(tools / "route.sh"))}\n'
                           f'pleya_route_command flutter "$0" shell "$@"\nexec {work}\n')
        flutter.chmod(0o755)
        self.env['PLEYA_HEAVY_ROOTS_FILE'] = str(roots)
        return repo, flutter

    def test_script_phase_route_runs_inside_lease_without_queueing(self):
        repo, flutter = self.route_fixture()
        outer = self.launch('outer', self.phase_command([str(flutter), 'build', 'bundle'], cwd=repo))
        self.wait_started('nested')
        state = self.status()
        self.assertEqual(state['waiting'], [])
        nested = self.row('route-flutter')
        self.assertEqual(nested['parent'], self.row('outer')['id'] + '.ticket')
        self.release('nested')
        self.assertEqual(outer.wait(timeout=5), 23)
        self.assertEqual(outer.communicate()[1].count(b'heavy-queue: queued'), 1)

    def test_script_phase_scope_requests_registration_and_owns_stays_refused(self):
        import shlex
        command = (f'import subprocess,sys; '
                   f'print(subprocess.run([sys.executable,{str(QUEUE)!r},sys.argv[1]]).returncode,'
                   f'file=open({str(self.root)!r}+"/"+sys.argv[1],"w"))')
        outer = self.launch('outer', ['/bin/sh', '-c', ' && '.join([
            shlex.join(self.phase_command([sys.executable, '-c', command, action]))
            for action in ('scope', 'owns')])])
        self.assertEqual(outer.wait(timeout=5), 0, outer.communicate()[1])
        self.assertEqual((self.root / 'scope').read_text().strip(), '10')
        self.assertEqual((self.root / 'owns').read_text().strip(), '75')

    def test_independent_waiter_stays_out_while_outer_and_script_phase_run(self):
        nested = self.run_command('nested', self.hold_command('nested'))
        outer, waiter = self.outer_with_queued_waiter_then_script_phase(nested)
        self.wait_started('nested')
        self.wait_started('outer')
        time.sleep(.5)
        self.assertFalse(self.marker('waiter', 'start').exists())
        self.release('nested')
        self.until(self.marker('nested', 'end').exists)
        time.sleep(.5)
        self.assertFalse(self.marker('waiter', 'start').exists())
        self.release('outer')
        self.wait_started('waiter')
        self.assertGreaterEqual(self.moment('waiter', 'start'),
                                max(self.moment('outer', 'end'), self.moment('nested', 'end')))
        self.assertEqual(outer.wait(timeout=5), 0)

    def assert_orphan_keeps_waiter_out(self, stop_outer):
        nested = self.run_command('nested', self.hold_command('nested'))
        outer, waiter = self.outer_with_queued_waiter_then_script_phase(nested)
        self.wait_started('nested')
        self.wait_started('outer')
        stop_outer(outer)
        outer.wait(timeout=5)
        self.until(lambda: not [r for r in self.status()['active'] if r['label'] == 'outer'])
        self.until(self.slot_is_held)
        time.sleep(.5)
        self.assertFalse(self.marker('waiter', 'start').exists())
        impatient = self.launch('impatient', ['true'], '--wait-timeout', '.3')
        self.assertEqual(impatient.wait(timeout=4), 124)
        self.assertFalse(self.marker('nested', 'end').exists())
        self.assertEqual(self.row('nested')['state'], 'active')
        self.release('nested')
        self.wait_started('waiter')
        self.assertGreaterEqual(self.moment('waiter', 'start'), self.moment('nested', 'end'))

    def test_outer_normal_exit_with_running_script_phase_keeps_waiter_out(self):
        self.assert_orphan_keeps_waiter_out(lambda outer: self.release('outer'))

    def test_outer_sigkill_with_running_script_phase_keeps_waiter_out(self):
        def kill_outer(outer):
            os.killpg(self.row('outer')['supervisor_pid'], signal.SIGKILL)
            outer.kill()
        self.assert_orphan_keeps_waiter_out(kill_outer)

    def leaving_command(self):
        return [sys.executable, str(self.root / 'leave.py'), str(self.marker('leftover', 'start')),
                *self.hold_command('leftover')]

    def test_crashed_script_phase_guardian_with_leftover_child_keeps_waiter_out(self):
        nested = self.run_command('nested', self.leaving_command())
        outer, waiter = self.outer_with_queued_waiter_then_script_phase(nested)
        self.wait_started('leftover')
        self.wait_started('outer')
        os.kill(self.row('nested')['supervisor_pid'], signal.SIGKILL)
        self.release('outer')
        self.assertEqual(outer.wait(timeout=5), 0)
        self.until(self.slot_is_held)  # the caller adopts it, the guardian is gone
        time.sleep(.6)
        self.assertFalse(self.marker('waiter', 'start').exists(), 'overlap with leftover child')
        self.assertEqual(self.row('nested')['state'], 'active')
        self.release('leftover')
        self.wait_started('waiter')
        self.assertGreaterEqual(self.moment('waiter', 'start'), self.moment('leftover', 'end'))

    def test_guardian_adopts_slot_after_script_phase_caller_is_killed(self):
        nested = self.run_command('nested', self.hold_command('nested'))
        outer, waiter = self.outer_with_queued_waiter_then_script_phase(nested)
        self.wait_started('nested')
        self.wait_started('outer')
        os.kill(self.row('nested')['pid'], signal.SIGKILL)
        self.release('outer')
        self.assertEqual(outer.wait(timeout=5), 0)
        self.until(self.slot_is_held)
        time.sleep(.4)
        self.assertFalse(self.marker('waiter', 'start').exists(), 'overlap after caller crash')
        self.release('nested')
        self.wait_started('waiter')
        self.assertGreaterEqual(self.moment('waiter', 'start'), self.moment('nested', 'end'))

    def test_crashed_pty_guardian_with_leftover_child_keeps_waiter_out(self):
        child = self.detached_nested(
            f'import os,sys; os.execv({sys.executable!r}, {self.leaving_command()!r})')
        self.wait_started('leftover')
        os.kill(self.row('pty-child')['supervisor_pid'], signal.SIGKILL)
        waiter = self.launch('waiter', self.hold_command('waiter'))
        self.wait_queued('waiter')
        time.sleep(.6)
        self.assertFalse(self.marker('waiter', 'start').exists(), 'overlap with leftover child')
        self.release('leftover')
        self.wait_started('waiter')
        self.assertGreaterEqual(self.moment('waiter', 'start'), self.moment('leftover', 'end'))

    def test_worker_outliving_both_script_phase_supervisors_keeps_waiter_out(self):
        nested = self.run_command('nested', self.hold_command('nested'))
        outer, waiter = self.outer_with_queued_waiter_then_script_phase(nested)
        self.wait_started('nested')
        self.wait_started('outer')
        row = self.row('nested')
        os.kill(row['supervisor_pid'], signal.SIGKILL)
        os.kill(row['pid'], signal.SIGKILL)
        self.release('outer')
        self.assertEqual(outer.wait(timeout=5), 0)
        time.sleep(.6)
        self.assertFalse(self.slot_is_held(), 'only the live ticket is left as evidence')
        self.assertFalse(self.marker('waiter', 'start').exists(), 'overlap with surviving worker')
        self.release('nested')
        self.wait_started('waiter')
        self.assertGreaterEqual(self.moment('waiter', 'start'), self.moment('nested', 'end'))

    def test_limit_script_phase_both_supervisors_killed_waiter_passes_closed_fd_leftover(self):
        # Documented limit: no kernel lease survives two crashes, and a stored PID is no evidence.
        nested = self.run_command('nested', self.leaving_command())
        outer, waiter = self.outer_with_queued_waiter_then_script_phase(nested)
        self.wait_started('leftover')
        self.wait_started('outer')
        row = self.row('nested')
        os.kill(row['supervisor_pid'], signal.SIGKILL)
        os.kill(row['pid'], signal.SIGKILL)
        self.until(lambda: not [r for r in self.status()['active'] if r['label'] == 'nested'])
        self.release('outer')
        self.assertEqual(outer.wait(timeout=5), 0)
        self.until(self.marker('waiter', 'start').exists, timeout=9)
        self.assertFalse(self.marker('leftover', 'end').exists(), 'the test releases it only below')
        self.release('leftover')

    def test_limit_pty_both_supervisors_killed_waiter_passes_closed_fd_leftover(self):
        child = self.detached_nested(
            f'import os,sys; os.execv({sys.executable!r}, {self.leaving_command()!r})')
        self.wait_started('leftover')
        row = self.row('pty-child')
        os.kill(row['supervisor_pid'], signal.SIGKILL)
        os.kill(row['pid'], signal.SIGKILL)
        waiter = self.launch('waiter', self.hold_command('waiter'))
        self.until(self.marker('waiter', 'start').exists, timeout=9)
        self.assertFalse(self.marker('leftover', 'end').exists(), 'the test releases it only below')
        self.release('leftover')

    def test_outer_sigterm_stops_script_phase_and_release_waits_for_its_end(self):
        nested = self.run_command('nested', self.slow_term_command('nested', 1.2))
        outer, waiter = self.outer_with_queued_waiter_then_script_phase(nested)
        self.wait_started('nested')
        self.wait_started('outer')
        outer.terminate()
        self.assertEqual(outer.wait(timeout=5), -signal.SIGTERM)
        self.wait_started('waiter')
        self.assertGreaterEqual(self.moment('waiter', 'start'), self.moment('nested', 'end'))

    def test_outer_deadline_kills_term_ignoring_script_phase_and_release_waits(self):
        nested = self.run_command('nested', self.slow_term_command('nested', 30))
        outer, waiter = self.outer_with_queued_waiter_then_script_phase(
            nested, '--run-timeout', '2.5s', '--kill-after', '1s')
        self.wait_started('nested')
        self.assertEqual(outer.wait(timeout=6), 124)
        self.wait_started('waiter')
        self.assertGreaterEqual(self.moment('waiter', 'start'), self.last_beat('nested'))
        self.assertFalse(self.marker('nested', 'end').exists(), 'only SIGKILL may stop this leaf')

    def stall_guardian_until_parent_reaped(self, stop_outer):
        """The polling waiter removes the parent ticket before the guardian looks at it again."""
        outer_ticket = self.root / 'queue' / (self.row('outer')['id'] + '.ticket')
        guardian = self.row('nested')['supervisor_pid']

        def resume():
            try:
                os.kill(guardian, signal.SIGCONT)
            except ProcessLookupError:
                pass
        os.kill(guardian, signal.SIGSTOP)
        self.addCleanup(resume)
        stop_outer()
        self.until(lambda: not outer_ticket.exists(), timeout=6)
        resume()

    def test_outer_cancel_survives_reaping_of_parent_ticket(self):
        nested = self.run_command('nested', self.slow_term_command('nested', 0))
        outer, waiter = self.outer_with_queued_waiter_then_script_phase(nested)
        self.wait_started('nested')
        self.wait_started('outer')

        def stop_outer():
            outer.terminate()
            self.assertEqual(outer.wait(timeout=5), -signal.SIGTERM)
        self.stall_guardian_until_parent_reaped(stop_outer)
        self.wait_started('waiter')
        self.assertGreaterEqual(self.moment('waiter', 'start'), self.moment('nested', 'end'))

    def test_outer_deadline_survives_reaping_of_parent_ticket(self):
        nested = self.run_command('nested', self.slow_term_command('nested', 30))
        outer, waiter = self.outer_with_queued_waiter_then_script_phase(
            nested, '--run-timeout', '2s', '--kill-after', '.3s')
        self.wait_started('nested')
        self.stall_guardian_until_parent_reaped(lambda: self.assertEqual(outer.wait(timeout=6), 124))
        self.wait_started('waiter')
        self.assertGreaterEqual(self.moment('waiter', 'start'), self.last_beat('nested'))
        self.assertFalse(self.marker('nested', 'end').exists(), 'only SIGKILL may stop this leaf')

    def assert_refused(self, overrides):
        ran = self.root / 'must-not-run'
        env = dict(self.env, **overrides)
        command = self.run_command('forged', ['/usr/bin/touch', str(ran)])
        for argv in (command, [sys.executable, str(QUEUE), 'scope']):
            result = subprocess.run(argv, env=env, capture_output=True, text=True, timeout=4,
                                    start_new_session=True, close_fds=True)
            self.assertEqual(result.returncode, 75, (overrides, result.stderr))
        self.assertFalse(ran.exists())

    def lease_with_token(self, name):
        token_file = self.root / (name + '.token')
        code = (f'import os,sys; from pathlib import Path; '
                f'Path({str(token_file)!r}).write_text(os.environ.get({ADMISSION!r},"")); '
                f'os.execv({sys.executable!r}, {self.hold_command(name)!r})')
        child = self.launch(name, [sys.executable, '-c', code])
        self.wait_started(name)
        return child, token_file.read_text(), self.row(name)['id'] + '.ticket'

    def test_script_phase_admission_needs_live_lease_token_and_build_environment(self):
        finished, old_token, old_name = self.lease_with_token('finished')
        self.release('finished')
        self.assertEqual(finished.wait(timeout=4), 0)
        active, token, name = self.lease_with_token('active')
        count = len(self.status()['active'])
        context = f'999:998:{name}'
        valid = {'PLEYA_HEAVY_QUEUE_FDS': context, ADMISSION: token}
        self.assert_refused(valid)  # daemon: valid lineage, not a build script phase
        for name in XCODE_ENV:
            self.assert_refused({**valid, name: XCODE_ENV[name]})  # one of the two settings
            self.assert_refused({**valid, **XCODE_ENV, name: ''})  # exported but empty
        self.assert_refused({'PLEYA_HEAVY_QUEUE_FDS': context, **XCODE_ENV})  # name from status only
        self.assert_refused({**valid, **XCODE_ENV, ADMISSION: '0' * 32})
        self.assert_refused({**valid, **XCODE_ENV, ADMISSION: old_token})
        self.assert_refused({'PLEYA_HEAVY_QUEUE_FDS': f'999:998:{old_name}', ADMISSION: old_token, **XCODE_ENV})
        self.assert_refused({**valid, **XCODE_ENV, 'PLEYA_HEAVY_QUEUE_FDS':
                             '999:998:' + '0' * 20 + '-' + '0' * 32 + '.ticket'})
        for context_text in ['garbage', '1:2', '', 'x:y:../escape.ticket', '1:2:slot.lock']:
            self.assert_refused({**valid, **XCODE_ENV, 'PLEYA_HEAVY_QUEUE_FDS': context_text})
        self.assertEqual(len(self.status()['active']), count)
        self.assertIsNone(active.poll())

    def test_waiting_ticket_cannot_admit_a_script_phase(self):
        import hashlib
        active, _, _ = self.lease_with_token('active')
        waiter = self.launch('waiter', ['true'])
        self.wait_queued('waiter')
        row = self.status()['waiting'][0]
        path = self.root / 'queue' / (row['id'] + '.ticket')
        record = json.loads(path.read_text())
        record['admission'] = hashlib.sha256(b'known').hexdigest()
        path.write_text(json.dumps(record))
        self.assert_refused({'PLEYA_HEAVY_QUEUE_FDS': f'999:998:{path.name}', ADMISSION: 'known', **XCODE_ENV})

    def test_nested_ticket_needs_a_live_active_parent_in_one_transaction(self):
        active, _, _ = self.lease_with_token('active')
        waiter = self.launch('waiter', ['true'])
        self.wait_queued('waiter')
        dead = '0' * 20 + '-' + '0' * 32 + '.ticket'
        for parent in (dead, self.status()['waiting'][0]['id'] + '.ticket'):
            code = (f'import sys; sys.path.insert(0, {str(QUEUE.parent)!r}); import heavy_queue; '
                    f'q = heavy_queue.Queue()\ntry:\n    q.new_ticket("n", "active", parent={parent!r})\n'
                    f'except heavy_queue.QueueError:\n    raise SystemExit(75)')
            result = subprocess.run([sys.executable, '-c', code], capture_output=True, text=True, timeout=4,
                                    env=dict(self.env, PYTHONDONTWRITEBYTECODE='1'))
            self.assertEqual(result.returncode, 75, result.stderr)

    @unittest.skipUnless(OLD_QUEUE, 'set PLEYA_HEAVY_OLD_QUEUE to the previous heavy_queue.py')
    def test_old_code_lease_context_and_ticket_stay_respected(self):
        rc_file = self.root / 'scope.rc'
        import shlex
        work = shlex.join(self.hold_command('old-outer'))
        script = (f'{shlex.quote(sys.executable)} {shlex.quote(str(QUEUE))} scope; echo $? > {shlex.quote(str(rc_file))}; '
                  f'exec {work}')
        outer = self.launch('old-outer', ['/bin/sh', '-c', script], queue=OLD_QUEUE)
        self.wait_started('old-outer')
        self.assertNotIn('admission', self.row('old-outer'), 'this ticket must come from old code')
        self.assertEqual(rc_file.read_text().strip(), '0')
        name = self.row('old-outer')['id'] + '.ticket'
        self.assert_refused({'PLEYA_HEAVY_QUEUE_FDS': f'999:998:{name}', ADMISSION: 'x', **XCODE_ENV})
        waiter = self.launch('waiter', self.hold_command('waiter'))
        self.wait_queued('waiter')
        time.sleep(.4)
        self.assertFalse(self.marker('waiter', 'start').exists())
        self.assertIsNone(outer.poll())
        self.release('old-outer')
        self.wait_started('waiter')
        self.assertGreaterEqual(self.moment('waiter', 'start'), self.moment('old-outer', 'end'))

    @unittest.skipUnless(OLD_QUEUE, 'set PLEYA_HEAVY_OLD_QUEUE to the previous heavy_queue.py')
    def test_old_code_waiter_stays_out_of_orphaned_script_phase(self):
        gate = self.root / 'gate'
        nested = self.run_command('nested', self.hold_command('nested'))
        outer = self.launch('outer', self.phase_command(
            nested, gate=gate, background=True, then=self.hold_command('outer')[1:]))
        self.wait_active('outer')
        waiter = self.launch('old-waiter', self.hold_command('old-waiter'), queue=OLD_QUEUE)
        self.wait_queued('old-waiter')
        self.assertNotIn('admission', self.status()['waiting'][0], 'this waiter must run old code')
        gate.touch()
        self.wait_started('nested')
        self.release('outer')
        self.assertEqual(outer.wait(timeout=5), 0)
        self.until(self.slot_is_held)
        time.sleep(.8)
        self.assertFalse(self.marker('old-waiter', 'start').exists(), 'old waiter overlapped')
        self.release('nested')
        self.wait_started('old-waiter')
        self.assertGreaterEqual(self.moment('old-waiter', 'start'), self.moment('nested', 'end'))

    def test_reject_symlink_state_directory(self):
        target = self.root / 'target'
        target.mkdir()
        (self.root / 'queue').symlink_to(target, target_is_directory=True)
        self.assertNotEqual(self.call('status').returncode, 0)
        self.assertEqual(list(target.iterdir()), [])


if __name__ == '__main__':
    print('old-code tests: ' + (f'running against {OLD_QUEUE}' if OLD_QUEUE
                                else 'SKIPPED, set PLEYA_HEAVY_OLD_QUEUE'), file=sys.stderr)
    unittest.main()
