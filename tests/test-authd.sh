#!/usr/bin/env bash
# Self-check for bin/c7-authd and bin/c7-askpass. Run it directly:
#   tests/test-authd.sh
#
# The polkit half cannot be exercised here: registering as the session's
# authentication agent needs polkitd on the system bus, and a real PAM
# conversation needs a real password. What this file does cover is everything
# either side of that -- the queue, the NDJSON contract the shell binds to, the
# askpass socket, and the checks that stop a prompt being raised on behalf of a
# caller nobody can name. --no-polkit is in the daemon for exactly this reason.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
authd=$here/../bin/c7-authd
askpass=$here/../bin/c7-askpass
tmp=$(mktemp -d)
daemon_pid=''
cleanup() {
  [[ -n $daemon_pid ]] && kill "$daemon_pid" 2>/dev/null
  rm -rf -- "$tmp"
}
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

sock=$tmp/askpass.sock
out=$tmp/out.ndjson
err=$tmp/err.log
cmds=$tmp/cmds

# The command channel stays open for the daemon's whole life: a plain file
# redirect gives it EOF immediately and it shuts down before the first test.
mkfifo "$cmds"
: > "$out"
"$authd" --no-polkit --socket "$sock" < "$cmds" > "$out" 2> "$err" &
daemon_pid=$!
exec 9> "$cmds"

send() { printf '%s\n' "$1" >&9; }

# Wait for a line matching a pattern to appear in the event stream, so the test
# never races the daemon. Everything here is sub-second in practice; the
# timeout only decides how a genuine hang is reported.
wait_for() {
  local pattern=$1 label=$2 i
  for ((i = 0; i < 100; i++)); do
    grep -q -- "$pattern" "$out" && return 0
    sleep 0.05
  done
  fail "timed out waiting for $label
events so far:
$(cat "$out")
stderr:
$(cat "$err")"
}

event_id() {
  # The id of the first event matching the pattern.
  grep -m1 -- "$1" "$out" | sed 's/.*"id":"\([^"]*\)".*/\1/'
}

# --- 1. it announces itself before anything else --------------------------
# The shell keys its whole state off this line: without it, it cannot tell a
# daemon that came up without polkit from one that has not started yet.
wait_for '"ev":"ready"' 'the ready event'
head -1 "$out" | grep -q '"ev":"ready"' || fail "ready was not the first event:
$(cat "$out")"
head -1 "$out" | grep -q '"polkit":false' \
  || fail "--no-polkit still reported itself as the polkit agent: $(head -1 "$out")"
head -1 "$out" | grep -q "\"askpass\":\"$sock\"" \
  || fail "ready did not name the socket it is listening on: $(head -1 "$out")"

[[ -S $sock ]] || fail 'no askpass socket was created'
# It carries passwords in both directions; anyone else's read is a password.
perm=$(stat -c '%a' "$sock")
[[ $perm == 600 ]] || fail "askpass socket is mode $perm, expected 600"
dirperm=$(stat -c '%a' "$(dirname "$sock")")
[[ $dirperm == 7?? ]] || fail "askpass socket directory is mode $dirperm, expected 7xx"

# --- 2. a request arrives, is drawn, and answers its caller ---------------
# Every one of these runs with 9>&-: a child that inherits the command channel
# holds the fifo's write end open, and section 7 -- which closes fd 9 to stand
# in for the shell dying -- would then wait forever for an EOF that cannot
# arrive.
#
# Stands in for sudo: c7-askpass refuses to prompt unless its own parent is
# sudo, so the test gives it one. A copy of the shell named `sudo` is enough --
# /proc/<pid>/comm is what the check reads, and what an attacker could not
# forge without already being able to run a process of that name as this user.
mkdir -p "$tmp/fakebin"
cp "$(command -v bash)" "$tmp/fakebin/sudo"
# A quoted heredoc: everything the wrapper needs arrives in the environment
# instead, so nothing in it is expanded twice. (An unquoted one ate the `$?`
# below, and the wrapper then reported success for every cancelled prompt.)
cat > "$tmp/run-askpass" <<'SH'
#!/usr/bin/env bash
# Execs the copy named sudo, which then RUNS c7-askpass rather than exec'ing
# it: the check reads the parent's comm, so the parent has to still be there.
# The trailing exit is load-bearing twice over -- bash execs the last command
# of a -c script without forking, which would leave c7-askpass with no sudo
# parent at all, and it is what carries c7-askpass's own status out, which
# several assertions below turn on.
exec "$FAKE_SUDO" -c '"$0" "$@"; exit $?' "$ASKPASS" "Password:"
SH
export FAKE_SUDO=$tmp/fakebin/sudo ASKPASS=$askpass
chmod +x "$tmp/run-askpass"

C7_AUTHD_SOCKET=$sock "$tmp/run-askpass" > "$tmp/secret.out" 2> "$tmp/askpass.err" 9>&- &
askpass_pid=$!

wait_for '"ev":"request"' 'the sudo request'
req=$(event_id '"ev":"request"')
[[ -n $req ]] || fail "the request event carried no id: $(cat "$out")"

grep -q '"kind":"sudo"' "$out" || fail "the request was not marked as a sudo prompt:
$(cat "$out")"
# The design's first rule: always name the caller. A sudo prompt that cannot
# say which command it is for is the shape of a phishing dialog.
grep -q '"command":' "$out" || fail "the sudo request named no command:
$(cat "$out")"
# It must become the head of the queue on its own -- nothing else is in front.
wait_for '"ev":"active"' 'the request becoming active'
grep -q '"ev":"prompt"' "$out" || fail "no prompt event, so the field never unlocks:
$(cat "$out")"

send "{\"cmd\":\"respond\",\"id\":\"$req\",\"secret\":\"hunter2\"}"
wait_for '"ev":"close"' 'the request closing'

wait "$askpass_pid" || fail "c7-askpass exited non-zero after a successful answer:
$(cat "$tmp/askpass.err")"
[[ $(cat "$tmp/secret.out") == hunter2 ]] \
  || fail "the secret did not reach sudo: got $(cat "$tmp/secret.out")"

# The identity row names the user and stops there. It carried a "wheel" chip
# once, filled in by looking up the account's group membership -- which reads
# next to a password field as "this is why you may answer this", while being a
# fact about the account and not about the request. polkit resolves identities
# to a user before the agent sees them, so there is no group to report; putting
# one there again would be asserting a reason nothing checked.
grep -q '"group"' "$out" \
  && fail "an event carries a group field again:\n$(grep '\"group\"' "$out")"
grep -q '"user":' "$out" || fail "no event names the user authenticating:\n$(cat "$out")"

# --- 3. the secret is never written anywhere it could be read -------------
# Not to stderr, not to the event stream. This is the one assertion in the file
# that is about a leak rather than a behaviour, so it is checked over the whole
# transcript rather than one line.
grep -q hunter2 "$out" && fail "the password was echoed back into the event stream"
grep -q hunter2 "$err" && fail "the password was logged to stderr"

# --- 4. cancelling refuses the caller rather than hanging it --------------
C7_AUTHD_SOCKET=$sock "$tmp/run-askpass" > "$tmp/secret2.out" 2>/dev/null 9>&- &
askpass2=$!
for ((i = 0; i < 100; i++)); do
  req2=$(grep '"ev":"request"' "$out" | sed -n '2s/.*"id":"\([^"]*\)".*/\1/p')
  [[ -n $req2 ]] && break
  sleep 0.05
done
[[ -n ${req2:-} ]] || fail "the second request never arrived:
$(cat "$out")"

send "{\"cmd\":\"cancel\",\"id\":\"$req2\"}"
rc=0; wait "$askpass2" || rc=$?
((rc != 0)) || fail 'a cancelled prompt still handed sudo a password'
[[ ! -s $tmp/secret2.out ]] || fail 'a cancelled prompt wrote something to stdout'

# --- 5. only sudo may raise a sudo prompt ---------------------------------
# Run directly, so the parent is this shell rather than sudo. A helper that
# prompts for anyone is a password box any program can raise on demand.
rc=0
C7_AUTHD_SOCKET=$sock "$askpass" "Password:" > "$tmp/direct.out" 2> "$tmp/direct.err" || rc=$?
((rc != 0)) || fail 'c7-askpass prompted for a caller that was not sudo'
grep -qi 'refusing' "$tmp/direct.err" \
  || fail "the refusal did not say why: $(cat "$tmp/direct.err")"
[[ ! -s $tmp/direct.out ]] || fail 'the refused call still wrote to stdout'

# --- 6. no shell, no prompt, and a way out --------------------------------
# sudo -A with a dead socket must fail with something a person can act on, not
# hang or print a stack trace.
rc=0
C7_AUTHD_SOCKET=$tmp/nothing.sock "$tmp/run-askpass" > /dev/null 2> "$tmp/nosock.err" || rc=$?
((rc != 0)) || fail 'c7-askpass succeeded with no daemon listening'
grep -q 'c7shell' "$tmp/nosock.err" \
  || fail "the no-daemon message does not say what is missing: $(cat "$tmp/nosock.err")"
grep -q 'without -A' "$tmp/nosock.err" \
  || fail "the no-daemon message offers no way to authenticate: $(cat "$tmp/nosock.err")"
grep -q Traceback "$tmp/nosock.err" && fail "c7-askpass crashed instead of failing:
$(cat "$tmp/nosock.err")"

# --- 7. losing the shell releases every caller ----------------------------
# The daemon is a child of qs. If qs dies while a prompt is up, sudo must be
# told no rather than left waiting on a socket nobody is reading.
#
# The refusal here is belt and braces: closing the socket would release the
# caller on its own, so this assertion passes with or without the explicit
# {"ok":false} the daemon sends first. What it does pin down is that the daemon
# neither outlives the shell nor leaves its socket behind -- a stale socket is
# worse than none, since the next c7-askpass connects to it and waits.
C7_AUTHD_SOCKET=$sock "$tmp/run-askpass" > /dev/null 2>&1 9>&- &
askpass3=$!
for ((i = 0; i < 100; i++)); do
  n=$(grep -c '"ev":"request"' "$out")
  ((n >= 3)) && break
  sleep 0.05
done
((n >= 3)) || fail "the third request never arrived:
$(cat "$out")"

exec 9>&-           # EOF on the command channel: the shell has gone
rc=0; wait "$askpass3" || rc=$?
((rc != 0)) || fail 'the daemon shut down without refusing the prompt it was holding'

for ((i = 0; i < 100; i++)); do
  kill -0 "$daemon_pid" 2>/dev/null || break
  sleep 0.05
done
kill -0 "$daemon_pid" 2>/dev/null && fail 'the daemon outlived the shell that started it'
daemon_pid=''
[[ ! -e $sock ]] || fail 'the daemon left its socket behind on the way out'

echo 'PASS: c7-authd / c7-askpass'
