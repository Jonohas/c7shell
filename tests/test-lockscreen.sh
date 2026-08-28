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
# media and media-source are the two halves of design 15b's card -- a title
# line and a dimmer "paused · spotify" under it. One label cannot carry two
# sizes, so a card that lost one half would silently render as a bare title or
# a bare state with nothing above it.
for arg in media media-source status; do
  grep -qE "cmd\[[^]]*\]\s*c7shell-lock-info $arg\b" "$conf" \
    || fail "no label calls c7shell-lock-info $arg"
done

# It is called every two seconds behind a lock screen, so "prints nothing" is
# the only acceptable way for it to have nothing to say: a non-zero exit or a
# stray error message would be drawn as the track title.
for arg in media media-source status; do
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

# The card's two lines have to appear and disappear together: a title with no
# state under it, or a state with no title over it, is a half-drawn card. Both
# read the same player through the same helper, so the only way they can
# disagree is if one of them grows its own idea of what counts as playing.
playerctl_stub() {
  mkdir -p "$stubbin"
  printf '#!/bin/sh\n%s\n' "$1" > "$stubbin/playerctl"
  chmod +x "$stubbin/playerctl"
}
stubbin=$tmp/stub

# Nothing on the bus at all: playerctl exits 1, and both lines stay empty.
playerctl_stub 'exit 1'
for arg in media media-source; do
  [[ -z $(PATH=$stubbin:$PATH "$info" "$arg") ]] \
    || fail "c7shell-lock-info $arg drew something with no player on the bus"
done

# Playing, with everything filled in.
playerctl_stub '
case "$1" in
  status) echo Playing ;;
  metadata) case "$3" in
      *title*) echo "Ipsissimus" ;;
      *artist*) echo "Cindytalk" ;;
      *playerName*) echo "spotify" ;;
    esac ;;
esac'
PATH=$stubbin:$PATH "$info" media | grep -q 'Ipsissimus — Cindytalk' \
  || fail "the title line does not carry title and artist: $(PATH=$stubbin:$PATH "$info" media)"
PATH=$stubbin:$PATH "$info" media | grep -q 'playing' \
  && fail 'the state leaked into the title line -- it belongs on the second one'
PATH=$stubbin:$PATH "$info" media-source | grep -qx 'playing · spotify' \
  || fail "the source line is not \"<state> · <player>\": $(PATH=$stubbin:$PATH "$info" media-source)"

# Paused is still a card: it is what the mockup draws, and the media key is the
# one control the lock screen has.
playerctl_stub '
case "$1" in
  status) echo Paused ;;
  metadata) case "$3" in
      *title*) echo "Ipsissimus" ;;
      *playerName*) echo "spotify" ;;
    esac ;;
esac'
PATH=$stubbin:$PATH "$info" media-source | grep -q '^paused' \
  || fail 'a paused player is not reported as paused'
PATH=$stubbin:$PATH "$info" media | grep -q 'Ipsissimus' \
  || fail 'a paused player lost its title line'

# Stopped is a player that is open and idle. Both lines go, together.
playerctl_stub 'case "$1" in status) echo Stopped ;; esac'
for arg in media media-source; do
  [[ -z $(PATH=$stubbin:$PATH "$info" "$arg") ]] \
    || fail "c7shell-lock-info $arg drew a card for a stopped player"
done

# A player with a state but no title is a browser tab or a notification sound.
# Neither line may draw, or the card would be a lone "playing · firefox".
playerctl_stub '
case "$1" in
  status) echo Playing ;;
  metadata) case "$3" in *playerName*) echo "firefox" ;; esac ;;
esac'
for arg in media media-source; do
  [[ -z $(PATH=$stubbin:$PATH "$info" "$arg") ]] \
    || fail "c7shell-lock-info $arg drew a card for a player with no title"
done

# hyprlock parses label text as pango markup, so a track called "Q&A" is a
# markup error rather than a title.
playerctl_stub '
case "$1" in
  status) echo Playing ;;
  metadata) case "$3" in
      *title*) echo "Q&A <live>" ;;
      *playerName*) echo "mpv" ;;
    esac ;;
esac'
PATH=$stubbin:$PATH "$info" media | grep -q '&amp;A &lt;live&gt;' \
  || fail "the title line does not escape pango markup: $(PATH=$stubbin:$PATH "$info" media)"
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

# The generated overlay image sits at zindex 0, above the background's -1.
# hyprlock sorts widgets by zindex with std::ranges::sort, which is not stable,
# so anything sharing 0 with the overlay has an unspecified draw order -- the
# clock would render under the decoration on some runs and over it on others.
# Every widget in this file therefore names its own layer.
widgets=$(grep -cE '^(label|input-field) \{' "$conf")
layered=$(grep -cE '^\s*zindex = 1$' "$conf")
((widgets > 0)) || fail 'no labels or input-field found in hyprlock.conf'
((widgets == layered)) \
  || fail "$widgets widgets but $layered at zindex 1 -- one draws under the backdrop overlay on an unstable sort"

# --- c7shell-lock, the backdrop decoration ---------------------------------
# It replaces hyprlock at every call site, so its failure mode is the whole lock
# screen. Everything below is about it degrading rather than dying.
lock=$here/../bin/c7shell-lock
[[ -x $lock ]] || fail 'bin/c7shell-lock is missing or not executable -- SUPER+L runs it'
for caller in ../hypr/conf/binds.lua ../hypr/hypridle.conf; do
  grep -q 'c7shell-lock' "$here/$caller" \
    || fail "$caller does not call c7shell-lock, so it gets no backdrop decoration"
done

# A fake hyprctl and a cache of our own: the real ones would decorate against
# whatever monitors this machine happens to have.
lockdir=$tmp/lock
mkdir -p "$lockdir/bin" "$lockdir/cache" "$lockdir/conf/hypr"
cp "$here/../hypr/hyprlock.conf" "$lockdir/conf/hypr/hyprlock.conf"
# Stands in for hyprlock itself: prints its argv and exits, so we can see what
# c7shell-lock would have handed over to without locking anything.
printf '#!/bin/sh\nprintf "%%s\\n" "$@"\n' > "$lockdir/bin/hyprlock"
chmod +x "$lockdir/bin/hyprlock"
# The PATH is hermetic -- only this bin, holding just what c7shell-lock and the
# stubs invoke -- so that deleting the fake hyprctl below makes hyprctl truly
# missing. With the inherited PATH appended, the developer's real hyprctl was
# found instead and the missing-hyprctl case decorated against real monitors.
ln -s "$(command -v python3)" "$lockdir/bin/python3"
ln -s "$(command -v cat)" "$lockdir/bin/cat"
runlock() {
  PATH=$lockdir/bin XDG_CONFIG_HOME=$lockdir/conf XDG_CACHE_HOME=$lockdir/cache \
    "$lock" "$@" 2>"$lockdir/err"
}

# One monitor: a PNG the size of that monitor, and a config that points at it.
printf '#!/bin/sh\ncat <<JSON\n[{"name":"DP-1","width":1920,"height":1080,"scale":1.0}]\nJSON\n' \
  > "$lockdir/bin/hyprctl"
chmod +x "$lockdir/bin/hyprctl"
out=$(runlock) || fail "c7shell-lock exited non-zero:\n$(cat "$lockdir/err")"
grep -q -- '--config' <<<"$out" || fail "c7shell-lock did not hand hyprlock a generated config:\n$out"
gen=$lockdir/cache/c7shell/hyprlock-generated.conf
[[ -f $gen ]] || fail 'no generated config was written'
grep -q 'monitor = DP-1' "$gen" || fail "the generated config has no image for DP-1:\n$(tail -14 "$gen")"
# min(1920, 1080) at scale 1: the size that makes a screen-aspect PNG land 1:1.
grep -qE '^\s*size = 1080$' "$gen" || fail "wrong image size:\n$(tail -14 "$gen")"
# The defaults would draw a circle inside a grey frame.
grep -qE '^\s*rounding = 0$' "$gen" || fail 'the overlay image is left rounded'
grep -qE '^\s*border_size = 0$' "$gen" || fail 'the overlay image is left with a border'
# The whole config has to survive being copied into the generated one.
grep -q 'screencopy_mode = 1' "$gen" || fail 'the generated config lost the base config'
png=$(grep -oE '/[^ ]*\.png' "$gen" | head -1)
[[ -f $png ]] || fail "the overlay PNG named in the config was not written: $png"
# A PNG header, 1920x1080, 8-bit RGBA (colour type 6) -- anything else and
# hyprlock draws nothing.
python3 - "$png" <<'PYCHK' || fail 'the overlay is not a 1920x1080 RGBA PNG'
import struct, sys
d = open(sys.argv[1], "rb").read()
w, h = struct.unpack(">II", d[16:24])
sys.exit(0 if d[:8] == b"\x89PNG\r\n\x1a\n" and (w, h) == (1920, 1080)
         and d[24] == 8 and d[25] == 6 else 1)
PYCHK

# A HiDPI monitor. hyprlock lays widgets out in buffer pixels, not logical ones
# (CSessionLockSurface sets size = logical * scale), so a scale-2 panel has a
# 2560x1600 viewport. Sizing the overlay in logical units drew it at half scale,
# centred, covering a quarter of the screen -- and every earlier case here used
# scale 1, where the two are the same number and the bug is invisible.
printf '#!/bin/sh\ncat <<JSON\n[{"name":"DP-1","width":2560,"height":1600,"scale":2.0}]\nJSON\n' \
  > "$lockdir/bin/hyprctl"
runlock >/dev/null || fail "a scale-2 monitor broke c7shell-lock:\n$(cat "$lockdir/err")"
grep -qE '^\s*size = 1600$' "$gen" \
  || fail "a scale-2 monitor is sized in logical units, so the overlay covers part of the screen:\n$(grep -E '^\s*size' "$gen")"
png=$(grep -oE '/[^ ]*\.png' "$gen" | head -1)
python3 - "$png" <<'PYCHK' || fail 'the scale-2 overlay is not authored at the monitor pixel size'
import struct, sys
d = open(sys.argv[1], "rb").read()
sys.exit(0 if struct.unpack(">II", d[16:24]) == (2560, 1600) else 1)
PYCHK
# The grid is in the same units as the type in hyprlock.conf, so it does not
# change with the monitor's scale factor.
python3 - "$png" <<'PYCHK' || fail 'the grid step moved with the monitor scale'
import zlib, struct, sys
d = open(sys.argv[1], "rb").read()
w, h = struct.unpack(">II", d[16:24])
i, idat = 8, b""
while i < len(d):
    ln = struct.unpack(">I", d[i:i+4])[0]
    if d[i+4:i+8] == b"IDAT": idat += d[i+8:i+8+ln]
    i += 12 + ln
raw = zlib.decompress(idat)
stride = w * 4 + 1
def alpha(x, y): return raw[y*stride + 1 + x*4 + 3]
# 56 mockup px at 1.2 = 67; a line there and none at 66 or 68.
sys.exit(0 if alpha(67, 40) > 0 and alpha(66, 40) == 0 and alpha(68, 40) == 0 else 1)
PYCHK

# Two monitors of different sizes get one image block each -- the whole reason
# this runs at lock time instead of shipping one asset.
printf '#!/bin/sh\ncat <<JSON\n[{"name":"DP-1","width":1920,"height":1080,"scale":1.0},{"name":"HDMI-A-1","width":2560,"height":1440,"scale":1.0}]\nJSON\n' \
  > "$lockdir/bin/hyprctl"
runlock >/dev/null || fail "two monitors broke c7shell-lock:\n$(cat "$lockdir/err")"
(($(grep -c '^image {' "$gen") == 2)) || fail "expected one image block per monitor:\n$(grep -c '^image {' "$gen")"

# No hyprctl at all, an unreadable config, and a hyprctl that fails: each one
# has to reach hyprlock anyway. A lock screen with no decoration beats no lock
# screen, and this is the code path that decides which one happens.
printf '#!/bin/sh\nexit 1\n' > "$lockdir/bin/hyprctl"
out=$(runlock) || fail 'a failing hyprctl should still reach hyprlock'
grep -q -- '--config' <<<"$out" && fail 'a failing hyprctl still produced a generated config'
rm -f "$lockdir/bin/hyprctl"
out=$(runlock) || fail 'a missing hyprctl should still reach hyprlock'
grep -q -- '--config' <<<"$out" && fail 'a missing hyprctl still produced a generated config'
mv "$lockdir/conf/hypr/hyprlock.conf" "$lockdir/conf/hypr/gone"
out=$(runlock) || fail 'an unreadable base config should still reach hyprlock'
mv "$lockdir/conf/hypr/gone" "$lockdir/conf/hypr/hyprlock.conf"

# An explicit --config is the caller overriding us; decorating someone else's
# config would be a surprise, and the test harness above depends on it.
out=$(runlock --config /some/other.conf)
grep -q '/some/other.conf' <<<"$out" || fail "an explicit --config was not passed through:\n$out"
(($(grep -c -- '--config' <<<"$out") == 1)) || fail "an explicit --config was decorated anyway:\n$out"

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
