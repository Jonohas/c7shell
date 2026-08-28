#!/usr/bin/env bash
# Self-check for the wallpaper "browse" path. Run it directly:
#   tests/test-filechooser.sh
#
# Appearance -> wallpaper -> "browse →" opens the desktop's own file dialog
# through xdg-desktop-portal, the same FileChooser hyprland-portals.conf routes
# to the kde backend for every other app (issue #22). Quickshell 0.3.1 has no
# generic DBus client, so quickshell/c7shell/scripts/c7shell-filechooser.py makes
# the call and prints the path.
#
# That script is the whole feature, and every interesting thing about it -- the
# handle path it has to guess, the signal it has to subscribe to before it calls,
# the URI it has to decode, the exit status the shell reads -- is invisible
# without a portal on the bus. So this brings up a private session bus with
# tests/portal-filechooser-stub.py on it and runs the real script against it.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
repo=$here/..
shell=$repo/quickshell/c7shell
chooser=$shell/scripts/c7shell-filechooser.py
tmp=$(mktemp -d)

pids=()
cleanup() {
  for pid in ${pids+"${pids[@]}"}; do kill "$pid" 2>/dev/null || true; done
  rm -rf -- "$tmp"
}
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# --- the parts that have to stay wired together -----------------------------
[[ -f $chooser ]] || fail 'quickshell/c7shell/scripts/c7shell-filechooser.py is missing'

page=$shell/Modules/Settings/pages/AppearancePage.qml
store=$shell/Services/AppearanceStore.qml

# "browse →" used to focus the text field and do nothing else. If it goes back
# to that, nothing else here notices: the script would still pass every test
# below while being unreachable from the settings app.
grep -q 'onClicked: AppearanceStore.browseWallpaper()' "$page" \
  || fail 'the appearance page no longer opens the file chooser'
grep -q 'function browseWallpaper()' "$store" \
  || fail 'AppearanceStore does not define browseWallpaper'
grep -q 'c7shell-filechooser.py' "$store" \
  || fail 'AppearanceStore does not run the file chooser script'
# A cancelled dialog exits 1 and a missing portal exits 2. Writing the path
# regardless would clear the wallpaper every time the dialog is dismissed.
grep -q 'if (exitCode === 0 && chooser.picked !== "") root.values.wallpaper = chooser.picked' "$store" \
  || fail 'AppearanceStore sets the wallpaper without checking the exit status'

# --- the formats it offers --------------------------------------------------
# hyprpaper is what has to load the file in the end, and what it can load is
# what libhyprgraphics links a decoder for. Asserted against the library itself
# where it is installed: a list of mime types is otherwise just a claim.
if [[ -e /usr/lib/libhyprgraphics.so ]] && command -v ldd >/dev/null; then
  linked=$(ldd /usr/lib/libhyprgraphics.so)
  declare -A decoder=(
    [image/png]=libpng
    [image/jpeg]=libjpeg
    [image/webp]=libwebp
    [image/jxl]=libjxl
    [image/svg+xml]=librsvg
  )
  for mime in "${!decoder[@]}"; do
    grep -q "${decoder[$mime]}" <<<"$linked" \
      || fail "the chooser offers $mime, but libhyprgraphics links no ${decoder[$mime]}"
    grep -qF "\"$mime\"" "$chooser" \
      || fail "libhyprgraphics links ${decoder[$mime]}, but the chooser does not offer $mime"
  done
  # image/bmp has no library of its own -- hyprgraphics reads it itself -- so it
  # is listed without a linked decoder to check.
  grep -qF '"image/bmp"' "$chooser" || fail 'the chooser does not offer image/bmp'
  # gif is the one people expect and hyprpaper cannot do: nothing decodes it, so
  # offering it means a wallpaper that silently does not change.
  grep -q "libgif\|libungif" <<<"$linked" \
    && fail 'libhyprgraphics links a gif decoder now; the chooser should offer image/gif'
  grep -qF '"image/gif"' "$chooser" \
    && fail 'the chooser offers image/gif, which hyprpaper cannot load'
else
  echo 'SKIP: hyprgraphics not installed, the offered formats were not checked against it'
fi

command -v dbus-daemon >/dev/null && python3 -c 'import dbus, dbus.service, gi' 2>/dev/null || {
  echo 'SKIP: dbus-daemon or python-dbus missing, only the wiring was checked'
  exit 0
}

# --- a private bus with a fake portal on it ---------------------------------
# Private, emphatically: the real session bus has the real portal on it, and a
# test that opened a file dialog on the developer's screen would be a bug.
#
# Hand-written config rather than --session, and the difference is the whole
# point: --session reads session.conf, which pulls in the standard service
# directories, and a bus that can activate services is not empty. The "no
# portal" case below asks for org.freedesktop.portal.Desktop, and such a bus
# starts the real /usr/lib/xdg-desktop-portal -- with the real kde, gtk and
# hyprland backends behind it -- instead of refusing the call. The script then
# waits on a dialog on the developer's screen until the timeout kills it. No
# <servicedir> and no <standard_session_servicedirs/> here: the only thing on
# this bus is what the test puts there.
addr_file=$tmp/bus.addr
cat >"$tmp/bus.conf" <<'EOF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <policy context="default">
    <allow own="*"/>
    <allow send_type="method_call"/>
    <allow send_type="signal"/>
    <allow send_type="method_return"/>
    <allow send_type="error"/>
    <allow receive_type="method_call"/>
    <allow receive_type="signal"/>
    <allow receive_type="method_return"/>
    <allow receive_type="error"/>
  </policy>
</busconfig>
EOF
dbus-daemon --config-file="$tmp/bus.conf" --print-address=1 --nofork >"$addr_file" 2>"$tmp/bus.err" &
pids+=($!)
for _ in $(seq 40); do [[ -s $addr_file ]] && break; sleep 0.1; done
[[ -s $addr_file ]] || fail "the test bus did not start:\n$(cat "$tmp/bus.err")"
export DBUS_SESSION_BUS_ADDRESS
DBUS_SESSION_BUS_ADDRESS=$(cat "$addr_file")

# Brings the stub up with the given answer and leaves it running.
stub() {
  local log=$tmp/stub.log
  : > "$log"
  python3 "$here/portal-filechooser-stub.py" --record "$tmp/rec.json" "$@" >"$log" 2>&1 &
  pids+=($!)
  for _ in $(seq 40); do grep -q ready "$log" && return; sleep 0.1; done
  fail "the portal stub did not start:\n$(cat "$log")"
}

stop_stub() {
  local pid=${pids[-1]}
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  unset 'pids[-1]'
}

# Runs the real script. Its stdout lands in $out, its status in $rc.
run() {
  set +e
  out=$(timeout 30 python3 "$chooser" "$@" 2>"$tmp/err")
  rc=$?
  set -e
}

# --- a file is picked -------------------------------------------------------
# The name carries a space and a "#": the portal answers with a URI, and both
# characters are percent-encoded in it and legal in a file name.
stub --answer 'file:///tmp/some%20dir/pic%231.png'
run --title 'Choose a wallpaper' --accept 'Set wallpaper' --images --current-folder /tmp
[[ $rc -eq 0 ]] || fail "picking a file exited $rc:\n$(cat "$tmp/err")"
[[ $out == '/tmp/some dir/pic#1.png' ]] || fail "the picked path came back as '$out'"

# What the dialog was actually asked for. current_folder is what makes it open
# where the wallpaper in force lives rather than wherever it was last.
recorded() { python3 -c "
import json, sys
opts = json.load(open('$tmp/rec.json'))
print(opts['options'].get(sys.argv[1], opts.get(sys.argv[1], '')))" "$1"; }

[[ $(recorded title) == 'Choose a wallpaper' ]] || fail "title was '$(recorded title)'"
[[ $(recorded accept_label) == 'Set wallpaper' ]] || fail "accept label was '$(recorded accept_label)'"
[[ $(recorded current_folder) == '/tmp' ]] || fail "current folder was '$(recorded current_folder)'"
[[ $(recorded multiple) == 'False' ]] || fail 'the dialog allows more than one file'
[[ $(recorded directory) == 'False' ]] || fail 'the dialog picks directories'
# Mime types (filter kind 1), not globs: case folding and the long tail of
# extensions belong to the backend's mime database, not to a list here.
python3 -c "
import json, sys
filters = json.load(open('$tmp/rec.json'))['options']['filters']
kinds = {kind for _, patterns in filters for kind, _ in patterns}
sys.exit(0 if kinds == {1} else 'filters are %s, expected mime types only' % kinds)" \
  || fail 'the image filter is not a mime-type filter'
stop_stub

# --- a folder that is not there ---------------------------------------------
# The option is dropped rather than passed on: the portal rejects a
# current_folder that does not exist, and it would take the whole call with it.
stub --answer 'file:///tmp/x.png'
run --current-folder /nonexistent/nowhere
[[ $rc -eq 0 ]] || fail "a missing current folder broke the call (exit $rc)"
[[ $(recorded current_folder) == '' ]] || fail 'a missing folder was still sent to the portal'
stop_stub

# --- the response overtakes the call ----------------------------------------
# The default stub answers *before* OpenFile returns, which is the race the
# script guards against by subscribing to the handle path it works out itself.
# This is the other order, so both are covered.
stub --answer 'file:///tmp/later.png' --delay 300
run
[[ $rc -eq 0 ]] || fail "a delayed response exited $rc:\n$(cat "$tmp/err")"
[[ $out == /tmp/later.png ]] || fail "a delayed response came back as '$out'"
stop_stub

# --- cancelled --------------------------------------------------------------
# The status is the whole signal here: the store leaves the wallpaper alone
# unless this is 0, so a cancelled dialog must not be a success with no path.
# The stub sends a uri along with the cancel, which is what makes this a test of
# the response *code* rather than of an empty result.
stub --code 1 --answer 'file:///tmp/not-picked.png'
run
[[ $rc -eq 1 ]] || fail "a cancelled dialog exited $rc, expected 1"
[[ -z $out ]] || fail "a cancelled dialog printed '$out'"
stop_stub

# Success with nothing in it -- no uris at all -- is not a path either.
stub --empty
run
[[ $rc -eq 1 ]] || fail "an empty result exited $rc, expected 1"
[[ -z $out ]] || fail "an empty result printed '$out'"
stop_stub

# --- something that is not a local file -------------------------------------
# hyprpaper takes a path. A KIO location or a document-store handle is neither
# a path nor an error worth pretending is one.
stub --answer 'smb://fileserver/share/pic.png'
run
[[ $rc -eq 2 ]] || fail "a remote uri exited $rc, expected 2"
[[ -z $out ]] || fail "a remote uri printed '$out'"
grep -q 'not a local file' "$tmp/err" || fail 'a remote uri was not explained on stderr'
stop_stub

# --- no portal at all -------------------------------------------------------
# A bus with nothing on it: the script has to fail, and say so, rather than hang
# waiting for a Response that is never coming.
run
[[ $rc -eq 2 ]] || fail "a bus with no portal exited $rc, expected 2"
[[ -z $out ]] || fail "a missing portal printed '$out'"
grep -q 'file chooser unavailable' "$tmp/err" || fail 'a missing portal was not explained on stderr'

echo 'PASS: wallpaper file chooser'
