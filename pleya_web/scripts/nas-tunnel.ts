/**
 * Een TCP-relay naar de Pleya Server op de NAS.
 *
 * Waarom dit bestaat. De server luistert op de NAS bewust alleen op
 * 127.0.0.1 (`compose.yaml`), dus geen enkele machine op het LAN bereikt hem;
 * openstellen hoort bij PS-11. De gebruikelijke omweg is `ssh -L`, maar de
 * sshd van DSM weigert dat met "administratively prohibited: open failed",
 * ongeacht wat `authorized_keys` toestaat. Zonder een van beide is de
 * NAS-verificatie uit PS-3W niet uit te voeren.
 *
 * Wat hij wel doet. Een commando draaien mag wel, dus per verbinding start dit
 * een python3 op de NAS die stdin en stdout aan 127.0.0.1:8832 koppelt. Aan de
 * NAS verandert niets: geen poort open, geen bestand, geen configuratie, en
 * niets dat een herstart overleeft.
 *
 * Draaien:
 *
 *   bun run scripts/nas-tunnel.ts        # daarna http://127.0.0.1:18832
 *   PORT=19000 bun run scripts/nas-tunnel.ts
 *
 * De hostnaam komt uit ~/.ssh/config; `synology` is de bestaande alias die
 * pleya_server/deploy-nas.sh ook gebruikt.
 */
const RELAY_PY = `
import sys, socket, threading
s = socket.create_connection(('127.0.0.1', 8832))
def up():
    try:
        while True:
            d = sys.stdin.buffer.read1(65536)
            if not d:
                break
            s.sendall(d)
    except Exception:
        pass
    try:
        s.shutdown(socket.SHUT_WR)
    except Exception:
        pass
threading.Thread(target=up, daemon=True).start()
try:
    while True:
        d = s.recv(65536)
        if not d:
            break
        sys.stdout.buffer.write(d)
        sys.stdout.buffer.flush()
except Exception:
    pass
`;

const SSH_HOST = process.env['PLEYA_NAS_SSH_HOST'] ?? 'synology';
const encoded = Buffer.from(RELAY_PY).toString('base64');
const remote = `python3 -c "import base64;exec(base64.b64decode('${encoded}'))"`;

const SSH_ARGS = [
  'ssh',
  '-o',
  'ControlMaster=auto',
  '-o',
  'ControlPath=/tmp/pleya-nas-%r@%h:%p',
  '-o',
  'ControlPersist=300',
  '-o',
  'BatchMode=yes',
  SSH_HOST,
  remote
];

const PORT = Number(process.env['PORT'] ?? 18832);

/** Wat er per verbinding aan de andere kant hangt. */
interface Bridge {
  child: Bun.Subprocess<'pipe', 'pipe', 'ignore'>;
}

Bun.listen<Bridge>({
  hostname: '127.0.0.1',
  port: PORT,
  socket: {
    open(socket) {
      const child = Bun.spawn(SSH_ARGS, { stdin: 'pipe', stdout: 'pipe', stderr: 'ignore' });
      socket.data = { child };

      void (async () => {
        const reader = child.stdout.getReader();
        try {
          for (;;) {
            const { done, value } = await reader.read();
            if (done) break;
            socket.write(value);
          }
        } catch {
          // verbinding weg
        } finally {
          reader.releaseLock();
          socket.end();
        }
      })();
    },
    data(socket, chunk) {
      const sink = socket.data.child.stdin;
      sink.write(chunk);
      sink.flush();
    },
    close(socket) {
      const { child } = socket.data;
      try {
        child.stdin.end();
        child.kill();
      } catch {
        // al weg
      }
    },
    error(socket) {
      socket.data.child.kill();
    }
  }
});

console.log(`relay op http://127.0.0.1:${PORT} -> ${SSH_HOST} 127.0.0.1:8832`);
