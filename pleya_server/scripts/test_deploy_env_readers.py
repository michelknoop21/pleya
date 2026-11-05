#!/usr/bin/env python3
"""Het echte deployscript met synthetische env en uitsluitend lokale SSH/buildstubs."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SOURCE = Path(os.environ.get(
    "PLEYA_DEPLOY_SCRIPT", str(Path(__file__).resolve().parents[1] / "deploy-nas.sh")
))

SSH_STUB = r'''#!/usr/bin/env python3
import json, os, subprocess, sys
assert sys.argv[1] == 'synology', sys.argv
command = sys.argv[2]
with open(os.environ['DEPLOY_TEST_LOG'], 'a') as log:
    log.write(json.dumps({'ssh': command}) + '\n')
if command == 'test -e /dev/dri/renderD128':
    sys.exit(1)
if 'docker compose' in command and 'up -d --build' in command:
    open(os.environ['DEPLOY_TEST_STARTED'], 'w').close()
    sys.exit(0)
if 'docker network inspect' in command:
    sys.exit(0)
command = command.replace(os.environ['DEPLOY_TEST_REMOTE'], os.environ['DEPLOY_TEST_LOCAL'])
sys.exit(subprocess.run(['/bin/sh', '-c', command]).returncode)
'''

CURL_STUB = r'''#!/usr/bin/env python3
import json, os, sys
with open(os.environ['DEPLOY_TEST_LOG'], 'a') as log:
    log.write(json.dumps({'curl': sys.argv[-1]}) + '\n')
sys.exit(0 if sys.argv[-1] == os.environ['DEPLOY_TEST_URL'] else 1)
'''

TAR_STUB = r'''#!/usr/bin/env python3
import os, subprocess, sys
if sys.argv[1] == 'xzf' and os.environ.get('DEPLOY_TEST_FAIL_EXTRACT') == '1':
    subprocess.run([os.environ['DEPLOY_TEST_TAR'], *sys.argv[1:]], check=True)
    sys.exit(73)
if sys.argv[1] == 'czf' and os.environ.get('DEPLOY_TEST_CORRUPT_UPLOAD') == '1':
    sys.stdout.write('broken archive')
    sys.exit(0)
sys.exit(subprocess.run([os.environ['DEPLOY_TEST_TAR'], *sys.argv[1:]]).returncode)
'''


class DeployEnvReadersTest(unittest.TestCase):
    def test_actual_deploy_readers(self):
        cases = [
            ("defaults", "prod", None, [], [], True),
            ("single_equals_in_path", "prod", None, ["./backup=active"], ["8832"], True),
            ("different_backup", "prod", None, ["./missing", "./backup=active"], ["8832"], True),
            ("identical_backup", "prod", None, ["./data/backups", "./data/backups"], ["8832"], True),
            ("different_port", "prod", None, ["./data/backups"], ["9999", "8832"], True),
            ("identical_port", "prod", None, ["./data/backups"], ["8832", "8832"], True),
            ("private_test_both", "test", "/volume1/pleya-private", ["./missing", "./backup=active"], ["9999", "8833"], True),
            ("test_rejects_production_port", "test", "/volume1/pleya-private", ["./data/backups"], ["8832", "8833"], False),
            ("failed_extract", "prod", None, [], [], False),
            ("corrupt_upload", "prod", None, [], [], False),
            ("missing_index", "prod", None, [], [], False),
            ("fresh_deploy", "prod", None, [], [], True),
            ("failed_extract_fresh", "prod", None, [], [], False),
        ]
        for name, instance, root, backups, ports, accepted in cases:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                work = Path(temporary)
                server = work / "server"
                server.mkdir()
                shutil.copyfile(SOURCE, server / "deploy-nas.sh")
                for filename in ("Dockerfile", "compose.yaml", "compose.test.yaml", "compose.hwaccel.yaml",
                                 ".dockerignore", "go.mod", "go.sum", "cmd/main.go",
                                 "internal/web/dist/index.html", "internal/web/dist/new.js"):
                    target = server / filename
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_text("new bundle")
                if name == "missing_index":
                    (server / "internal/web/dist/index.html").unlink()
                web = work / "pleya_web/scripts"
                web.mkdir(parents=True)
                build = web / "build-into-server.sh"
                build.write_text('#!/bin/sh\ntouch "$DEPLOY_TEST_BUILD"\n')
                build.chmod(0o755)
                remote = work / "synthetic-nas"
                (remote / "data/backups").mkdir(parents=True)
                (remote / "backup=active").mkdir()
                leaf = "pleya-server-test" if instance == "test" else "pleya-server"
                values = ["POSTGRES_PASSWORD=synthetic-only-not-a-credential"]
                if instance == "test":
                    values += ["PLEYA_SERVER_CONTAINER=pleya-server-test",
                               "PLEYA_SERVER_DB_CONTAINER=pleya-server-test-db",
                               "PLEYA_SERVER_NETWORK=pleya-server-test_default"]
                values += ["PLEYA_SERVER_BACKUP_HOST=" + value for value in backups]
                values += ["PLEYA_SERVER_HOST_PORT=" + value for value in ports]
                (remote / ".env").write_text("\n".join(values) + "\n")
                original_env = (remote / ".env").read_bytes()
                dist = remote / "internal/web/dist"
                dist.mkdir(parents=True)
                (dist / "index.html").write_text("previous bundle")
                (dist / "stale.js").write_text("old chunk")
                if name in ("fresh_deploy", "failed_extract_fresh"):
                    shutil.rmtree(dist)
                original_dist = {path.name: path.read_text() for path in dist.glob("*")}
                binary = work / "bin"
                binary.mkdir()
                for tool, source in {"ssh": SSH_STUB, "curl": CURL_STUB,
                                     "tar": TAR_STUB,
                                     "sleep": "#!/bin/sh\nexit 0\n",
                                     "docker": "#!/bin/sh\nexit 91\n"}.items():
                    target = binary / tool
                    target.write_text(source)
                    target.chmod(0o755)
                log = work / "calls.jsonl"
                env = dict(os.environ)
                env.pop("PLEYA_DEPLOY_ROOT", None)
                if root is not None:
                    env["PLEYA_DEPLOY_ROOT"] = root
                env.update(PATH=str(binary) + os.pathsep + env["PATH"],
                           PLEYA_INSTANCE=instance,
                           DEPLOY_TEST_REMOTE=(root or "/volume1/docker") + "/" + leaf,
                           DEPLOY_TEST_LOCAL=str(remote),
                           DEPLOY_TEST_LOG=str(log), DEPLOY_TEST_BUILD=str(work / "built"),
                           DEPLOY_TEST_TAR=shutil.which("tar"), DEPLOY_TEST_STARTED=str(work / "started"),
                           DEPLOY_TEST_FAIL_EXTRACT="1" if name.startswith("failed_extract") else "0",
                           DEPLOY_TEST_CORRUPT_UPLOAD="1" if name == "corrupt_upload" else "0",
                           DEPLOY_TEST_URL="http://127.0.0.1:" + ("8833" if instance == "test" else "8832") + "/readyz")
                result = subprocess.run(["sh", str(server / "deploy-nas.sh")], env=env,
                                        capture_output=True, text=True, timeout=20)
                self.assertEqual(result.returncode, 0 if accepted else 1, result.stdout + result.stderr)
                self.assertEqual((work / "built").exists(), accepted or name in
                                 ("failed_extract", "corrupt_upload", "missing_index", "failed_extract_fresh"))
                self.assertEqual((work / "started").exists(), accepted)
                self.assertEqual((remote / ".env").read_bytes(), original_env)
                self.assertEqual({path.name: path.read_text() for path in dist.glob("*")},
                                 {"index.html": "new bundle", "new.js": "new bundle"} if accepted else original_dist)
                self.assertEqual(list(remote.glob(".deploy-sources.*")), [])
                calls = [json.loads(line) for line in log.read_text().splitlines()]
                urls = [call["curl"] for call in calls if "curl" in call]
                self.assertEqual(urls, [env["DEPLOY_TEST_URL"]] if accepted else [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
