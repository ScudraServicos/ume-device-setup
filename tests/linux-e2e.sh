#!/usr/bin/env bash
# End-to-end test of ume-account-migrate.sh on a disposable Linux container.
# Runs every phase through a real pseudo-terminal (expect), as the real users.
#   usage: tests/linux-e2e.sh [image]   (default ubuntu:24.04; also try fedora:41)
set -euo pipefail
IMAGE="${1:-ubuntu:24.04}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Fedora keeps /etc/shadow at mode 000; under rootless Docker, setuid sudo can only
# read it with --privileged (still confined to the rootless user namespace).
DOCKER_OPTS=()
case "${IMAGE}" in fedora*|*rhel*|*rocky*|*alma*) DOCKER_OPTS=(--privileged) ;; esac
docker run --rm -i ${DOCKER_OPTS[@]+"${DOCKER_OPTS[@]}"} -v "${ROOT}:/src:ro" "${IMAGE}" bash -s <<'IN_CONTAINER'
set -euo pipefail
if command -v apt-get >/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >/dev/null && apt-get install -y -qq sudo expect passwd cron procps >/dev/null
  ADMIN_GROUP=sudo
else
  dnf install -y -q sudo expect passwd cronie procps-ng shadow-utils util-linux authselect >/dev/null
  # Container images ship without a PAM profile; select the one a real install uses.
  authselect select local --force >/dev/null
  ADMIN_GROUP=wheel
fi
install -m 0755 /src/ume-account-migrate.sh /opt/m.sh

# --- fixture: a user "jsilva" whose email is joao.silva@example.com ---------
useradd -m -s /bin/bash -G "${ADMIN_GROUP}" jsilva
echo 'jsilva:Old-pass-123' | chpasswd
echo 'export FOO=/home/jsilva/bin' >> /home/jsilva/.bashrc
echo secret-data > /home/jsilva/notes.txt && chown jsilva: /home/jsilva/notes.txt
echo 'jsilva ALL=(ALL) NOPASSWD: /usr/bin/true' > /etc/sudoers.d/90-jsilva && chmod 0440 /etc/sudoers.d/90-jsilva
grep -q '^jsilva:' /etc/subuid 2>/dev/null || echo 'jsilva:200000:65536' >> /etc/subuid
mkdir -p /var/spool/cron/crontabs && echo '0 1 * * * true' > /var/spool/cron/crontabs/jsilva
OLD_UID="$(id -u jsilva)"

# sudo asks for the invoking user's password, as on a real laptop.
cat > /tmp/drive.exp <<'EXP'
set timeout 60
set user [lindex $argv 0]; set pass [lindex $argv 1]; set args [lrange $argv 2 end]
spawn su -P - $user -c "bash /opt/m.sh $args"
expect {
  -re {\[sudo\] password for [^:]+: $}           { send "$pass\r"; exp_continue }
  -re {UME work email.*: $}             { send "joao.silva@example.com\r"; exp_continue }
  -re {Type .*yes.* to continue: $}     { send "yes\r"; exp_continue }
  -re {(New|Retype new) password: $}    { send "Temp-pass-456\r"; exp_continue }
  eof
}
lassign [wait] pid spawnid os_error rc
exit $rc
EXP
drive() { expect -f /tmp/drive.exp "$@"; }
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

echo "### --check as jsilva (must change nothing)"
out="$(drive jsilva Old-pass-123 --check 2>&1)" || { echo "$out"; fail "--check exit code"; }
echo "${out}" | grep -q "do not match" || fail "--check did not report mismatch"
id ume-migrate >/dev/null 2>&1 && fail "--check created an account"
pass "--check is read-only"

echo "### run 1 as jsilva"
drive jsilva Old-pass-123 || fail "run 1 exit code"
id ume-migrate >/dev/null || fail "helper not created"
[[ "$(cat /home/ume-migrate/.config/gnome-initial-setup-done)" == yes ]] || fail "GNOME welcome wizard not skipped for helper"
grep -q '^PHASE=1$' /var/lib/ume-account-migrate/state || fail "state not phase 1"
pass "run 1"

echo "### run 1 again as jsilva -> only a reminder"
drive jsilva Old-pass-123 | grep -q "Run 1 is already done" || fail "no reminder"
pass "idempotent reminder"

echo "### leave a background process for jsilva, then run 2 as ume-migrate"
su - jsilva -c 'nohup sleep 1000 >/dev/null 2>&1 &'
drive ume-migrate Temp-pass-456 || fail "run 2 exit code"
id joao.silva >/dev/null || fail "new user missing"
id jsilva >/dev/null 2>&1 && fail "old user still exists"
[[ "$(id -u joao.silva)" == "${OLD_UID}" ]] || fail "UID changed"
[[ "$(getent passwd joao.silva | cut -d: -f6)" == /home/joao.silva ]] || fail "home not moved"
[[ -L /home/jsilva && "$(readlink /home/jsilva)" == /home/joao.silva ]] || fail "compat symlink missing"
[[ "$(cat /home/joao.silva/notes.txt)" == secret-data ]] || fail "data lost"
getent group joao.silva >/dev/null || fail "private group not renamed"
grep -q '^joao.silva:' /etc/subuid || fail "subuid not updated"
grep -qw joao.silva /etc/sudoers.d/90-jsilva || fail "sudoers not updated"
visudo -c >/dev/null || fail "sudoers invalid"
[[ -f /var/spool/cron/crontabs/joao.silva ]] || fail "crontab not moved"
id -nG joao.silva | grep -qw "$( [[ -f /etc/debian_version ]] && echo sudo || echo wheel )" || fail "admin group lost"
grep -q '^PHASE=2$' /var/lib/ume-account-migrate/state || fail "state not phase 2"
grep -q '^\[.*\] UNDO: usermod -l jsilva joao.silva' /var/log/ume-account-migrate/*run2.log || fail "undo not logged"
grep -q 'Temp-pass-456\|Old-pass-123' /var/log/ume-account-migrate/*.log && fail "password leaked to log"
pass "run 2"

echo "### run 3 as joao.silva (old password)"
out="$(drive joao.silva Old-pass-123)" || { echo "${out}"; fail "run 3 exit code"; }
echo "${out}" | grep -q "Device Enrollment" || fail "run 3 did not show JumpCloud install steps"
echo "${out}" | grep -q "TAKE OVER an existing account, accept: it must be 'joao.silva'" || fail "run 3 takeover name"
id ume-migrate >/dev/null 2>&1 && fail "helper not removed"
[[ -e /var/lib/ume-account-migrate/state ]] && fail "state not cleared"
pass "run 3"

echo "### check again -> all good"
out="$(drive joao.silva Old-pass-123 --check)"
echo "${out}" | grep -q "All good" || fail "final check not OK"
echo "${out}" | grep -q "Device Enrollment" || fail "check did not show JumpCloud install steps"
pass "final check"

echo "### --cancel path on a second user"
useradd -m -s /bin/bash -G "${ADMIN_GROUP}" msouza && echo 'msouza:Pw-789' | chpasswd
sed -i 's/joao.silva@example.com/maria.souza@example.com/' /tmp/drive.exp
drive msouza Pw-789 || fail "cancel: run 1"
drive msouza Pw-789 --cancel || fail "cancel exit code"
id ume-migrate >/dev/null 2>&1 && fail "cancel left helper"
[[ -e /var/lib/ume-account-migrate/state ]] && fail "cancel left state"
id msouza >/dev/null || fail "cancel touched user"
pass "--cancel"

echo "ALL TESTS PASSED on $(. /etc/os-release; echo "${PRETTY_NAME}")"
IN_CONTAINER
