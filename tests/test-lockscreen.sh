#!/usr/bin/env bash
# Self-check for hypr/hyprlock.conf. Run it directly: tests/test-lockscreen.sh
#
# hyprlock refuses to start when its config is missing OR when a key in it does
# not exist -- and what "refuses to start" looks like from the desk is SUPER+L
# doing nothing at all, plus hypridle's lock_cmd and before_sleep_cmd failing
# silently, so the machine idles and suspends unlocked. Nothing in the session
# reports it. So the config is parsed here, by hyprlock itself, against a
# Wayland display that does not exist: it validates the whole file before it
# tries to connect, which is what lets this run without locking anybody's
# screen.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
conf=$here/../hypr/hyprlock.conf
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f $conf ]] || fail 'hypr/hyprlock.conf is missing -- SUPER+L, the power menu lock row and the idle lock all do nothing without it'

# The lock has to demand a password on resume: hypridle locks before sleep, and
# an empty submission must not be treated as an attempt.
grep -q '^\s*ignore_empty_input\s*=\s*true' "$conf" \
  || fail 'ignore_empty_input is not enabled, so stray keys count as failed attempts'
# `grace` is a CLI flag in hyprlock 0.9, not a config key: setting it here is
# both ignored and a config error, and a grace period on a before-sleep lock
# means the screen unlocks itself on resume.
grep -qE '^\s*grace\s*=' "$conf" \
  && fail 'grace is not a config key in hyprlock 0.9 (it is a CLI flag), and a grace period defeats the before-sleep lock'

command -v hyprlock >/dev/null || {
  echo 'SKIP: hyprlock not installed, only the file itself was checked'
  exit 0
}

# A display name nothing is listening on, so hyprlock parses the config, reports
# what it thinks of it, and then dies on the connection instead of locking a
# real screen. It exits non-zero doing that, which is expected and ignored --
# only its opinion of the config is under test.
log=$tmp/parse.log
# Through an inner shell with its stderr closed: hyprlock aborts on the failed
# connection, and it is the *shell* that prints "Aborted" for a signal death --
# noise in the test output for the one outcome that is expected here.
bash -c 'WAYLAND_DISPLAY=c7shell-test-no-such-display timeout 30 hyprlock --config "$1" >"$2" 2>&1' \
  _ "$conf" "$log" 2>/dev/null || true

grep -q 'Couldn.t connect to a wayland compositor' "$log" \
  || fail "hyprlock did not get as far as connecting; it never validated the config:\n$(cat "$log")"

if grep -qE 'Config has errors|does not exist' "$log"; then
  fail "hyprlock rejects hypr/hyprlock.conf:\n$(grep -E 'Config error|does not exist' "$log")"
fi

echo 'PASS: lock screen config'
