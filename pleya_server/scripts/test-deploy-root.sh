#!/usr/bin/env sh
# Draai het echte deployscript tot de eerste SSH, zonder NAS of Webbuild.
set -eu

HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
DEPLOY_SCRIPT=${PLEYA_DEPLOY_SCRIPT:-$HERE/../deploy-nas.sh}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
mkdir "$WORK/bin"
cat > "$WORK/bin/ssh" <<'SH'
#!/usr/bin/env sh
printf '%s\n' "$@" >> "$DEPLOY_TEST_SSH_LOG"
exit 1
SH
chmod +x "$WORK/bin/ssh"
export DEPLOY_TEST_SSH_LOG="$WORK/ssh.log"
PATH="$WORK/bin:$PATH"
export PATH

valid() {
  root=$1
  instance=$2
  expected=$3
  rm -f "$DEPLOY_TEST_SSH_LOG"
  if [ "$root" = UNSET ]; then
    unset PLEYA_DEPLOY_ROOT
  else
    PLEYA_DEPLOY_ROOT=$root
    export PLEYA_DEPLOY_ROOT
  fi
  if PLEYA_INSTANCE="$instance" sh "$DEPLOY_SCRIPT" > "$WORK/out" 2>&1; then
    echo "FAIL: fake SSH-fout werd genegeerd" >&2
    exit 1
  fi
  [ -f "$DEPLOY_TEST_SSH_LOG" ]
  [ "$(head -n 1 "$DEPLOY_TEST_SSH_LOG")" = synology ]
  grep -F "$expected/.env" "$DEPLOY_TEST_SSH_LOG" > /dev/null
  [ "$(grep -c '^synology$' "$DEPLOY_TEST_SSH_LOG")" -eq 1 ]
  echo "PASS: $root / $instance -> $expected"
}

reject() {
  rm -f "$DEPLOY_TEST_SSH_LOG"
  if PLEYA_DEPLOY_ROOT="$1" PLEYA_INSTANCE="${2:-prod}" sh "$DEPLOY_SCRIPT" > "$WORK/out" 2>&1; then
    echo "FAIL: ongeldige deployroot/instance toegestaan" >&2
    exit 1
  fi
  [ ! -e "$DEPLOY_TEST_SSH_LOG" ]
  grep -E 'onbekende PLEYA_DEPLOY_ROOT|onbekende PLEYA_INSTANCE' "$WORK/out" > /dev/null
  echo "PASS: ongeldige root/instance geweigerd vóór SSH"
}

valid UNSET prod /volume1/docker/pleya-server
valid UNSET test /volume1/docker/pleya-server-test
valid /volume1/docker prod /volume1/docker/pleya-server
valid /volume1/docker test /volume1/docker/pleya-server-test
valid /volume1/pleya-private prod /volume1/pleya-private/pleya-server
valid /volume1/pleya-private test /volume1/pleya-private/pleya-server-test

reject ''
reject /
reject /volume1/docker/
reject /volume1/pleya-private/
reject /volume1/docker/../pleya-private
reject /tmp/pleya-private
reject '/volume1/pleya-private; touch unexpected'
reject '/volume1/pleya-private$(touch unexpected)'
reject "$(printf '/volume1/pleya-private\nextra')"
reject /volume1/docker invalid
reject /volume1/pleya-private invalid
echo 'PASS: 6 echte padkeuzes, 11 afwijzingen; geen NAS-contact/build'
