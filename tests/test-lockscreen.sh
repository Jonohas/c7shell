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

# The battery field. Matched on type rather than on a BAT* name, because the
# name is not standardised -- BAT0, BAT1, CMB0 and macsmc-battery all occur, and
# globbing BAT* reports nothing at all on the machines using the others. None of
# this is reproducible on the test machine, so every case is staged under
# C7SHELL_ROOT.
fakeroot=$tmp/root
supply=$fakeroot/sys/class/power_supply
battery() {
  rm -rf "$supply"; mkdir -p "$supply/$1"
  printf 'Battery\n' > "$supply/$1/type"
  printf '%s\n' "$2" > "$supply/$1/capacity"
  printf '%s\n' "$3" > "$supply/$1/status"
}

battery BAT0 62 Discharging
C7SHELL_ROOT=$fakeroot "$info" status | grep -q '62%' \
  || fail 'a battery at 62% does not reach the status line'
# Both fields present means they have to be separated. ${parts[*]} with a
# multi-character IFS joins on its first character only, which silently turns
# the mockup's " · " into a space -- close enough to read past in a diff.
if [[ -n $(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | grep -v ':loopback$') ]]; then
  C7SHELL_ROOT=$fakeroot "$info" status | grep -q ' · 62%' \
    || fail "the status fields are not joined with the mockup's separator: $(C7SHELL_ROOT=$fakeroot "$info" status)"
fi

battery BAT0 62 Charging
C7SHELL_ROOT=$fakeroot "$info" status | grep -q '62% charging' \
  || fail 'a charging battery is not reported as charging'

# The whole point of matching on type: a laptop whose battery is not called BAT*
# still gets a reading.
battery CMB0 41 Discharging
C7SHELL_ROOT=$fakeroot "$info" status | grep -q '41%' \
  || fail 'a battery named CMB0 is not found -- the check is still globbing BAT*'
battery macsmc-battery 88 Discharging
C7SHELL_ROOT=$fakeroot "$info" status | grep -q '88%' \
  || fail 'a battery named macsmc-battery is not found'

# A wireless mouse registers as a power supply too, with type=Battery and
# scope=Device. Reporting its charge as the machine's would be worse than
# reporting nothing.
battery hidpp_battery_0 12 Discharging
printf 'Device\n' > "$supply/hidpp_battery_0/scope"
C7SHELL_ROOT=$fakeroot "$info" status | grep -q '12%' \
  && fail "a peripheral's battery was reported as the machine's"

# Mains is not a battery at all.
rm -rf "$supply"; mkdir -p "$supply/ACAD"
printf 'Mains\n' > "$supply/ACAD/type"
printf '1\n' > "$supply/ACAD/online"
C7SHELL_ROOT=$fakeroot "$info" status | grep -q '%' \
  && fail 'a machine with only mains power still prints a percentage'
rm -rf "$supply"

# The notification count comes from the shell over IPC, because hyprlock cannot
# speak D-Bus. Stubbed here: the real one needs a running shell, and what is
# under test is that the count is parsed and worded, not that quickshell works.
stubbin=$tmp/stub
mkdir -p "$stubbin"
qs_returns() { printf '#!/bin/sh\nprintf %%s "%s"\n' "$1" > "$stubbin/qs"; chmod +x "$stubbin/qs"; }

qs_returns 3
PATH=$stubbin:$PATH C7SHELL_ROOT=$fakeroot "$info" status | grep -q '3 notifications' \
  || fail "the notification count does not reach the status line: $(PATH=$stubbin:$PATH "$info" status)"
# The mockup's badge reads "3 notifications"; one is not "1 notifications".
qs_returns 1
PATH=$stubbin:$PATH C7SHELL_ROOT=$fakeroot "$info" status | grep -q '1 notification$' \
  || fail 'a single notification is not worded in the singular'
# Nothing waiting is not a field that says zero.
qs_returns 0
PATH=$stubbin:$PATH C7SHELL_ROOT=$fakeroot "$info" status | grep -q 'notification' \
  && fail 'zero notifications still prints a field'
# A shell that is not running, or one too old to have the handler, answers with
# something that is not a number. That is a missing field, not an error on the
# lock screen.
qs_returns 'error: no such target'
PATH=$stubbin:$PATH C7SHELL_ROOT=$fakeroot "$info" status | grep -qi 'error\|notification' \
  && fail 'an IPC error was drawn on the lock screen'
rm -rf "$stubbin"

"$info" bogus >/dev/null 2>&1 && fail 'c7shell-lock-info accepted an unknown argument'

# hyprlock copies the screen at startup -- for the screenshot background and for
# the fade, which is on by default -- and its default route is a GBM buffer over
# zwp_linux_dmabuf_v1. On a virtual GPU aquamarine cannot build a DRM renderer,
# so the compositor rejects the buffer and kills the connection; hyprlock aborts
# before it draws. SUPER+L does nothing, the power menu's lock row does nothing,
# and hypridle's before_sleep_cmd fails the same way, so the machine suspends
# unlocked. Mode 1 is the shm route -- the one grim uses.
grep -qE '^\s*screencopy_mode\s*=\s*1' "$conf" \
  || fail 'screencopy_mode is not 1, so hyprlock takes the dmabuf route and aborts on any virtual GPU -- nothing locks and the machine suspends unlocked'

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
