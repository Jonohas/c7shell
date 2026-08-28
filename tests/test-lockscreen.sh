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

# --- the mockup's contract (design doc turn 11) -----------------------------
# The two states are the whole design: nothing on screen but the clock until a
# key is pressed, then a field at centre. hyprlock gives that for free through
# fade_on_empty -- without it the field is permanently up and the lock screen is
# simply a different lock screen.
grep -qE '^\s*fade_on_empty\s*=\s*true' "$conf" \
  || fail 'fade_on_empty is off, so the password field never hides and the resting state from the mockup does not exist'

# The live lines are a label cmd[] calling a command by name. If the config and
# the script ever disagree about that name the labels silently render empty,
# which looks exactly like "nothing is playing" and is why it is pinned here.
info=$here/../bin/c7shell-lock-info
[[ -x $info ]] || fail 'bin/c7shell-lock-info is missing or not executable -- the lock screen loses its now-playing and status lines'
for arg in media status; do
  grep -qE "cmd\[[^]]*\]\s*c7shell-lock-info $arg\b" "$conf" \
    || fail "no label calls c7shell-lock-info $arg"
done

# It is called every two seconds behind a lock screen, so "prints nothing" is
# the only acceptable way for it to have nothing to say: a non-zero exit or a
# stray error message would be drawn as the track title.
for arg in media status; do
  out=$("$info" "$arg" 2>"$tmp/err") \
    || fail "c7shell-lock-info $arg exited non-zero; hyprlock would draw nothing and log noise"
  [[ -s $tmp/err ]] && fail "c7shell-lock-info $arg wrote to stderr:\n$(cat "$tmp/err")"
  # Whatever it printed is one line: the labels are single-line.
  (($(wc -l <<<"$out") <= 1)) || fail "c7shell-lock-info $arg printed more than one line:\n$out"
done

# A machine with no battery must lose the field rather than report 0%, and one
# with a battery must show it. Neither is reproducible on the test machine, so
# both are staged under C7SHELL_ROOT.
fakeroot=$tmp/root
mkdir -p "$fakeroot/sys/class/power_supply/BAT0"
printf '62\n' > "$fakeroot/sys/class/power_supply/BAT0/capacity"
printf 'Discharging\n' > "$fakeroot/sys/class/power_supply/BAT0/status"
C7SHELL_ROOT=$fakeroot "$info" status | grep -q '62%' \
  || fail 'a battery at 62% does not reach the status line'
# Both fields present means they have to be separated. ${parts[*]} with a
# multi-character IFS joins on its first character only, which silently turns
# the mockup's " · " into a space -- close enough to read past in a diff.
if [[ -n $(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | grep -v ':loopback$') ]]; then
  C7SHELL_ROOT=$fakeroot "$info" status | grep -q ' · 62%' \
    || fail "the status fields are not joined with the mockup's separator: $(C7SHELL_ROOT=$fakeroot "$info" status)"
fi
printf 'Charging\n' > "$fakeroot/sys/class/power_supply/BAT0/status"
C7SHELL_ROOT=$fakeroot "$info" status | grep -q '62% charging' \
  || fail 'a charging battery is not reported as charging'
rm -rf "$fakeroot/sys/class/power_supply/BAT0"
C7SHELL_ROOT=$fakeroot "$info" status | grep -q '%' \
  && fail 'a machine with no battery still prints a percentage'

# An unknown argument is a bug in hyprlock.conf, and it should be loud when a
# human runs it rather than silently printing a blank line forever.
"$info" bogus >/dev/null 2>&1 && fail 'c7shell-lock-info accepted an unknown argument'

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
