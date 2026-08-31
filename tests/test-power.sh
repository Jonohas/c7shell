#!/usr/bin/env bash
# Self-check for the power feature's two non-QML pieces: the root helper's
# argument validation, and the shape of the hypridle config the settings page
# generates. Run it directly: tests/test-power.sh
#
# Nothing here needs root or touches the real machine. c7power-root is the
# trust boundary -- pkexec hands it root, so every verb it refuses is a hole
# that is not there -- and the refusals are exactly what can be tested without
# being root, because they happen before any write.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
helper=$here/../bin/c7power-root
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

fail() { printf 'FAIL: %b\n' "$1" >&2; exit 1; }

# --------------------------------------------------------------------------
# 1. c7power-root takes a verb, never a command line.
# --------------------------------------------------------------------------
[[ -x $helper ]] || fail 'bin/c7power-root is not executable'

out=$(bash "$helper" 2>&1 || true)
[[ $out == *"unknown verb"* ]] || fail "c7power-root accepted an empty verb: $out"

out=$(bash "$helper" 'charge-limit; id' 2>&1 || true)
[[ $out == *"unknown verb"* ]] || fail "c7power-root accepted a compound verb: $out"

# --------------------------------------------------------------------------
# 2. charge-limit only takes a plausible percentage.
# --------------------------------------------------------------------------
for bad in '' 'abc' '80; id' '-5' '1000' '0' '49' '101'; do
  out=$(bash "$helper" charge-limit "$bad" 2>&1 || true)
  [[ $out == *"not a percentage"* || $out == *"out of range"* ]] \
    || fail "c7power-root accepted charge limit '$bad': $out"
done

# A valid one gets past validation and fails on the machine instead, which is
# the only thing this test can assert without a writable sysfs.
out=$(bash "$helper" charge-limit 80 2>&1 || true)
[[ $out != *"not a percentage"* && $out != *"out of range"* ]] \
  || fail "c7power-root rejected a valid charge limit: $out"

# --------------------------------------------------------------------------
# 3. lid-close only takes one of logind's own actions -- and in particular
#    nothing that would land in the drop-in as a second config line.
# --------------------------------------------------------------------------
for bad in '' 'reboot' 'suspend
HandleSuspendKey=poweroff' 'suspend; id' '../../etc/passwd'; do
  out=$(bash "$helper" lid-close "$bad" 2>&1 || true)
  [[ $out == *"not a lid action"* ]] \
    || fail "c7power-root accepted lid action '$bad': $out"
done

# --------------------------------------------------------------------------
# 4. The hypridle config the settings page writes.
#
# PowerService.hypridleConf() is QML, so the generator itself cannot run here.
# What can be checked is that the file it writes is the shape hypridle parses
# and that the ordering matches the two rows on the page: blank first, then
# lock `lockAfterBlank` after it. The QML is the source of these strings, so a
# change there that this does not follow is meant to fail here.
# --------------------------------------------------------------------------
qml=$here/../quickshell/c7shell/Services/PowerService.qml
[[ -f $qml ]] || fail 'Services/PowerService.qml is missing'

grep -q 'on-timeout = hyprctl dispatch dpms off' "$qml" \
  || fail 'the generated hypridle config no longer blanks the screen'
grep -q 'on-timeout = loginctl lock-session' "$qml" \
  || fail 'the generated hypridle config no longer locks the session'
grep -q 'blankScreen + s.lockAfterBlank' "$qml" \
  || fail 'the lock listener no longer fires after the blank listener'
# The suspend listener has to stay conditional on AC, because hypridle itself
# has no notion of one: an unconditional listener suspends a docked desktop.
grep -q 'power_supply/A\*/online' "$qml" \
  || fail 'the suspend listener is no longer conditional on running off the pack'

# --------------------------------------------------------------------------
# 5. The polkit action names the helper by absolute path.
# --------------------------------------------------------------------------
policy=$here/../share/polkit-1/actions/io.crimson7.c7shell.policy
grep -q 'io.crimson7.c7shell.power' "$policy" \
  || fail 'the power polkit action is missing'
grep -q '/usr/lib/c7shell/c7power-root' "$policy" \
  || fail 'the power polkit action does not name c7power-root'
python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse('$policy')" 2>/dev/null \
  || fail 'the polkit policy is not well-formed XML'

# --------------------------------------------------------------------------
# 6. The package ships the helper where the action says it is.
# --------------------------------------------------------------------------
grep -q 'bin/c7power-root "$pkgdir/usr/lib/c7shell/c7power-root"' "$here/../PKGBUILD" \
  || fail 'PKGBUILD does not install c7power-root at the path the polkit action names'

echo 'ok: power'
